import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpException, SocketException;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../features/customer/ar/data/glb_bounds.dart';
import '../../features/customer/ar/data/glb_rescaler.dart';
import '../../models/product.dart';
import '../media/media_store.dart';
import 'generation_decider.dart'
    show
        needsDimensionsMessage,
        needsNetworkImageMessage,
        tripoUnavailableMessage;
import 'tripo_poll_state.dart';

/// Raised when the Tripo API rejects a call in a way retrying will NOT fix
/// (bad key, quota, invalid parameters, a terminal task failure, …). The
/// task (if any) is abandoned and the product is marked failed.
class TripoApiException implements Exception {
  const TripoApiException(this.message);

  final String message;

  @override
  String toString() => 'TripoApiException: $message';
}

/// Raised when a Tripo request failed TRANSIENTLY (network, timeout, 5xx,
/// malformed reply) — retrying the poll is worthwhile and costs nothing.
class TripoTransientApiException extends TripoApiException {
  const TripoTransientApiException(super.message);
}

/// Persistence port for `product.ar3d`. The generator talks to THIS, never
/// to Firebase directly, so unit tests inject an in-memory fake and can
/// assert every write — in particular that `taskId` survives transient
/// failures (the standing billing rule: re-polling is free, re-submitting
/// is billed, so a lost task id would cost real money).
abstract class ProductAr3dStore {
  /// PARTIAL update of the nested `ar3d` map only — never the whole product
  /// document (sales, ratings and concurrent edits must survive).
  Future<void> writeAr3d(String productId, Map<String, dynamic> ar3d);

  /// Whether the product document still exists (a deleted product has
  /// nothing to publish to).
  Future<bool> productExists(String productId);

  /// The live `ar3d` of the product, or null when the doc / record is
  /// absent or unreadable.
  Future<Ar3dInfo?> readAr3d(String productId);
}

/// Production [ProductAr3dStore] backed by Firestore.
class FirestoreAr3dStore implements ProductAr3dStore {
  FirestoreAr3dStore(this._db);

  final FirebaseFirestore _db;

  @override
  Future<void> writeAr3d(String productId, Map<String, dynamic> ar3d) {
    return _db.collection('products').doc(productId).update({'ar3d': ar3d});
  }

  @override
  Future<bool> productExists(String productId) async {
    // Firestore reads of missing docs return `exists == false` (no throw);
    // read errors are logged and treated as "can't know" → the caller
    // proceeds (its own write will surface a missing doc).
    try {
      final snap = await _db.collection('products').doc(productId).get();
      return snap.exists;
    } catch (e) {
      debugPrint('[model-3d] doc-existence check for $productId failed: $e');
      return true;
    }
  }

  @override
  Future<Ar3dInfo?> readAr3d(String productId) async {
    try {
      final snap = await _db.collection('products').doc(productId).get();
      if (!snap.exists) return null;
      final raw = snap.data()?['ar3d'];
      return raw is Map<String, dynamic> ? Ar3dInfo.fromJson(raw) : null;
    } catch (e) {
      debugPrint('[model-3d] could not re-read ar3d of $productId: $e');
      return null;
    }
  }
}

/// Asynchronous AI 3D generation for a single product via the app's Tripo
/// proxy (`{tripoApiUrl}/api/tripo/*`): submit → poll → download the resulting
/// GLB → rescale it to the SELLER's declared dimensions (the AR plugin only
/// scales uniformly at placement, so true size is baked into the geometry) →
/// publish the rescaled GLB through [MediaStore] → flip `product.ar3d` to
/// `ready`.
///
/// Tripo is the ONLY product-model source — there is no procedural
/// generator and no bundled-catalog fallback anywhere in this pipeline.
/// Every failure below therefore surfaces a specific, actionable message
/// (service not set up, out of credits, missing dimensions, network, timeout)
/// instead of quietly substituting another model.
///
/// THE KEY IS NOT IN THIS APP. The Tripo credential is an env var on the
/// backend (`web/backend`, TRIPO_API_KEY) and this class authenticates with
/// the signed-in user's Firebase ID token instead. That is the whole point:
/// anything compiled into an APK can be pulled out of the binary, so a client
/// holding a paid key is holding a leaked key. The backend owns the model
/// version too — a Tripo version bump is one env var on Render, not an app
/// release.
///
/// Endpoints (the backend forwards these to
/// https://openapi.tripo3d.ai/v3 and hands the reply back untouched):
///  - submit:   POST {base}/api/tripo/generation/image-to-model
///              body: {"input": imageUrl, "texture": true, "pbr": true,
///              "face_limit": 100000, "auto_size": true} → reply {"code": 0,
///              "data": {"task_id": "task_…"}}; imageUrl must be a PUBLIC
///              image URL (Tripo fetches it server-side).
///  - query:    GET {base}/api/tripo/tasks/{task_id} → `data.status` is
///              queued | running | success | failed | cancelled (…); on
///              success `data.output.model_url` (+ `rendered_image_url`);
///              on failure `data.error_message` / `error_code`.
///
/// The pass-through matters: Tripo's HTTP status and `{code, data}` envelope
/// reach this class unchanged, so the retry policy below still reads the real
/// upstream outcome (429/5xx = retryable, 401/402/4xx = not). Proxy-level
/// failures (no server key, expired sign-in) arrive as a short
/// `{"error":{"message"}}` sentence instead and are surfaced as-is.
///
/// CRASH-AND-RESUME SAFETY (this class never double-bills a seller):
///  - every product-doc write carries the FULL ar3d key set (status/source/
///    url/error/taskId/attempts/submittedAt/generatedAt) — Firestore updates
///    replace the whole nested map, so a partial write would drop state;
///  - [generateForProduct] (NEW submission, bills credits) persists
///    `generating` + attempts+1 + submittedAt BEFORE the POST, then persists
///    the `taskId` IMMEDIATELY after the POST answers — the crash window
///    between the two leaves no task id, and boot-resume then submits at most
///    once more (bounded by the attempts cap in the trigger's decider);
///  - [pollExistingTask] (free) re-checks a persisted task id — resuming a
///    stuck generation NEVER submits a second paid task when the first one
///    may still be running server-side;
///  - STANDING RULE: `ar3d.taskId` is NEVER cleared on a transient failure.
///    The poll state machine (tripo_poll_state.dart) leaves the task id in
///    place for: 4 consecutive transient poll failures, the 5-minute
///    deadline (the server-side task may still finish), download failures
///    of a finished task, auth/credits errors mid-poll (sign in again, Retry
///    re-polls the SAME already-paid task) — every one of those failures
///    writes `failed` WITH the task id so an explicit Retry re-polls instead
///    of re-billing. Only a server-side terminal task failure (failed /
///    cancelled) or unusable output (bad geometry) clears the id, because
///    nothing is left to poll and a fresh submission is the only way ahead.
///  - preconditions (service / photo / dimensions) never silently no-op: they
///    write `failed` with the exact missing precondition so the operator
///    knows what to fix.
///
/// Product-doc writes are PARTIAL `.update({'ar3d': {...}})` calls only —
/// never a full-document overwrite (sales, ratings and concurrent edits must
/// survive). Published models land in Supabase Storage under
/// `product_models/<productId>` (see MediaStore).
///
/// Costs: Tripo is pay-as-you-go (~US$0.30 per textured model; free signup
/// credits may apply). The key is set as TRIPO_API_KEY in the backend's env /
/// Render → Environment — see https://platform.tripo3d.ai. When the server
/// has no key it answers 503 and the seller records `failed` with
/// [tripoUnavailableMessage]; there is no other model source.
class Tripo3DGenerator {
  Tripo3DGenerator(
    ProductAr3dStore store, {
    MediaStore? mediaStore,
    http.Client? httpClient,
    DateTime Function()? clock,
    Duration? pollInterval,
    Duration? maxWait,
    Future<String?> Function()? idTokenProvider,
  })  : _store = store,
        _media = mediaStore ?? MediaStore.instance,
        _http = httpClient ?? http.Client(),
        _clock = clock ?? DateTime.now,
        _pollInterval = pollInterval ?? _defaultPollInterval,
        _maxWait = maxWait ?? _defaultMaxWait,
        _idTokenProvider = idTokenProvider ?? _firebaseIdToken;

  static const Duration _requestTimeout = Duration(seconds: 30);
  static const Duration _downloadTimeout = Duration(seconds: 120);
  static const Duration _defaultPollInterval = Duration(seconds: 5);
  static const Duration _defaultMaxWait = Duration(minutes: 5);

  /// Remote path (Supabase object path) of a product's AI model blob.
  static String storagePathFor(String productId) =>
      'product_models/$productId';

  final ProductAr3dStore _store;
  final MediaStore _media;
  final http.Client _http;
  final DateTime Function() _clock;
  final Duration _pollInterval;
  final Duration _maxWait;
  final Future<String?> Function() _idTokenProvider;

  /// Backend base for the Tripo proxy routes, or empty when this build has no
  /// backend URL. The suffixes the call sites use (`/generation/image-to-model`,
  /// `/tasks/{id}`) match Tripo's own path shapes on purpose — the proxy is a
  /// thin forwarder.
  static String get _apiBase {
    final base = AppConfig.tripoApiUrl.trim();
    if (base.isEmpty) return '';
    return '${base.replaceAll(RegExp(r'/+$'), '')}/api/tripo';
  }

  static Future<String?> _firebaseIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  /// Whether this build has a 3D-generation backend to call. The Tripo key
  /// itself is no longer this app's business — it is an env var on that
  /// backend — so "configured" only means "there is somewhere to send the
  /// request". A server without TRIPO_API_KEY answers 503 and the seller sees
  /// [tripoUnavailableMessage].
  static bool get isConfigured => AppConfig.tripoApiUrl.trim().isNotEmpty;

  /// Product ids with a generation already in flight in this process —
  /// guards the form/kick-off paths from double-submitting (each submission
  /// is a paid Tripo task).
  static final Set<String> _inFlight = {};

  /// Whether a generation is currently running for [productId].
  static bool isRunning(String productId) => _inFlight.contains(productId);

  /// Runs the full NEW-submission flow for one product: marks `generating`
  /// (attempts + 1), POSTs the image-to-model task, persists the task id,
  /// then polls/downloads/rescales/uploads/marks-ready. Fire-and-forget
  /// friendly: every failure inside is caught and reflected on the product
  /// doc (`ar3d.status == 'failed'`) — the only uncaught paths are store
  /// failures after the doc has been deleted (logged), so callers may safely
  /// `unawaited(...)`.
  ///
  /// Preconditions are LOUD, never silent: a missing key / photo / seller
  /// dimension writes `failed` with the exact reason (and keeps any
  /// persisted task id), so the operator sees what to fix instead of a
  /// product stuck in limbo.
  Future<void> generateForProduct(Product product) async {
    final id = product.id.trim();
    if (id.isEmpty) return; // nothing to write to
    if (!_inFlight.add(id)) {
      debugPrint('[model-3d] generation already running for $id — skipped');
      return;
    }
    final ar3d = product.ar3d;
    var attempts = ar3d?.attempts ?? 0;
    var submittedAt = ar3d?.submittedAt;
    // Task id persisted so far — preserved across ANY failure below so a
    // later Retry re-polls (free) instead of re-submitting (billed).
    var taskId = ar3d?.taskId ?? '';
    try {
      // ── Preconditions: fail loudly with the exact missing input. ────────
      if (!isConfigured) {
        await _tryWriteFailedKeepTask(id, attempts, submittedAt, taskId,
            tripoUnavailableMessage);
        return;
      }
      if (!product.hasNetworkImage) {
        await _tryWriteFailedKeepTask(id, attempts, submittedAt, taskId,
            needsNetworkImageMessage);
        return;
      }
      final dims = product.dimensions;
      if (!hasAnySellerDimension(dims)) {
        await _tryWriteFailedKeepTask(
            id, attempts, submittedAt, taskId, needsDimensionsMessage);
        return;
      }
      final sellerDims = dims!; // non-null: the guard above returned otherwise

      attempts = attempts + 1;
      submittedAt = _clock().toUtc();
      debugPrint('[model-3d] Tripo submission #$attempts for '
          '"${product.name}" ($id)');

      // 1) Visible state FIRST (crash-safe resume point). Persisting the
      //    incremented attempts here means even a crash before the POST can
      //    never spin an unbounded auto-submit loop — the decider caps it.
      await _writeDoc(id, _ar3dMap(
            status: 'generating',
            taskId: '',
            attempts: attempts,
            submittedAt: submittedAt,
          ));

      // 2) Submit the image-to-model task. The backend owns the Tripo model
      //    version — it is billed, so it is not this client's to pick.
      final submitData = await _postJson(
        '$_apiBase/generation/image-to-model',
        body: {
          'input': product.image, // Tripo fetches the public URL server-side
          'texture': true,
          'pbr': true,
          'face_limit': 100000,
          'auto_size': true,
        },
      );
      taskId = (submitData['task_id'] as String?)?.trim() ?? '';
      if (taskId.isEmpty) {
        throw const TripoApiException(
            'Tripo accepted the task but returned no task_id');
      }
      debugPrint('[model-3d] task $taskId submitted for $id');

      // 3) Persist the task id right away — a crash AFTER the POST but
      //    BEFORE this write leaves `generating` with no task id; boot-resume
      //    then re-submits at most once (attempts already > 0, cap in the
      //    decider), instead of double-billing on every resume of a
      //    perfectly healthy in-flight task.
      await _writeDoc(id, _ar3dMap(
            status: 'generating',
            taskId: taskId,
            attempts: attempts,
            submittedAt: submittedAt,
          ));

      // 4) Poll → download → rescale → upload → mark ready.
      await _pollToPublish(
        id: id,
        name: product.name,
        dims: sellerDims,
        taskId: taskId,
        attempts: attempts,
        submittedAt: submittedAt,
      );
    } catch (e) {
      // Any failure reaching here keeps the task id when one exists: a POST
      // that already answered has already billed us, and re-polling it later
      // is free. Only an empty id (nothing submitted) lands as a plain
      // failure.
      debugPrint('[model-3d] generation failed for $id: $e');
      await _tryWriteFailedKeepTask(
          id, attempts, submittedAt, taskId, _describe(e));
    } finally {
      _inFlight.remove(id);
    }
  }

  /// Re-polls a PERSISTED Tripo task — the free half of the pipeline (fixes
  /// the crash/resume double-billing: never a new submission, never a new
  /// charge). Used by the trigger on a `pollExistingTask` decision for
  /// `generating` docs (boot resume) and for `failed` docs that ended on a
  /// transient error (Retry re-checks the same task).
  ///
  /// No product-doc write happens unless the poll reaches a terminal state —
  /// and every failure write KEEPS the task id (see the class doc), so an
  /// explicit Retry always re-polls the SAME already-paid task.
  Future<void> pollExistingTask(Product product) async {
    final id = product.id.trim();
    final ar3d = product.ar3d;
    if (id.isEmpty || ar3d == null || !ar3d.hasTaskId) return;
    if (!_inFlight.add(id)) {
      debugPrint('[model-3d] generation already running for $id — skipped');
      return;
    }
    debugPrint('[model-3d] re-polling task ${ar3d.taskId} for $id');
    try {
      // A deleted product has no doc to poll for.
      if (!await _store.productExists(id)) {
        debugPrint('[model-3d] product $id was deleted — poll abandoned');
        return;
      }
      final dims = product.dimensions;
      if (!hasAnySellerDimension(dims)) {
        // The task may finish server-side, but without ANY seller dimension
        // we cannot size the model (AR never guesses one) — surface that
        // specific, fixable failure and KEEP the task id so that once the
        // seller adds dimensions a Retry publishes the already-paid task.
        await _tryWriteFailedKeepTask(id, ar3d.attempts, ar3d.submittedAt,
            ar3d.taskId, needsDimensionsMessage);
        return;
      }
      final sellerDims = dims!; // non-null: the guard above returned otherwise
      await _pollToPublish(
        id: id,
        name: product.name,
        dims: sellerDims,
        taskId: ar3d.taskId,
        attempts: ar3d.attempts,
        submittedAt: ar3d.submittedAt,
      );
    } catch (e) {
      // Keeps the persisted task id: auth/credits/network trouble on the
      // poll must never destroy the handle to an already-paid task.
      debugPrint('[model-3d] re-poll failed for $id: $e');
      await _tryWriteFailedKeepTask(id, ar3d.attempts, ar3d.submittedAt,
          ar3d.taskId, _describe(e));
    } finally {
      _inFlight.remove(id);
    }
  }

  /// Polls [taskId] until the pure state machine (tripo_poll_state.dart)
  /// reaches a terminal outcome, then publishes the model. Writes:
  ///  - success → download/rescale → (product-doc-exists check) → Storage
  ///    upload → (second exists check) → `ready`;
  ///  - server terminal failure → `failed` (task id cleared — nothing left
  ///    to poll, a fresh submission is the only way ahead);
  ///  - 4 consecutive transient poll failures → `failed` WITH the task id
  ///    kept (an explicit Retry re-polls the same — already paid — task);
  ///  - 5-minute deadline → `failed` WITH the task id kept and a timeout
  ///    message: the server-side task may still finish, so Retry re-checks
  ///    it for free instead of submitting a new paid task.
  Future<void> _pollToPublish({
    required String id,
    required String name,
    required ProductDimensions dims,
    required String taskId,
    required int attempts,
    DateTime? submittedAt,
  }) async {
    final deadline = _clock().add(_maxWait);
    var transients = 0;
    while (true) {
      // ── Deadline: the task keeps running server-side; record a visible,
      //    retryable timeout that KEEPS the task id. ────────────────────────
      final step = nextPollStep(
        consecutiveTransients: transients,
        deadlineReached: !_clock().isBefore(deadline),
        lastRequestTransientFailure: false,
        taskStatus: '',
      );
      if (step.outcome == PollOutcome.timedOutLeftRunning) {
        debugPrint('[model-3d] task $taskId passed ${_maxWait.inMinutes} min — '
            'recording a retryable timeout for $id (task id kept)');
        await _tryWriteFailedKeepTask(
            id, attempts, submittedAt, taskId, _timeoutMessage);
        return;
      }
      await Future<void>.delayed(_pollInterval);

      Map<String, dynamic> data;
      try {
        data = await _getJson('$_apiBase/tasks/$taskId');
      } on TripoTransientApiException {
        final tStep = nextPollStep(
          consecutiveTransients: transients,
          deadlineReached: false,
          lastRequestTransientFailure: true,
          taskStatus: '',
        );
        transients = tStep.consecutiveTransients;
        if (tStep.outcome == PollOutcome.transientCapReached) {
          await _tryWriteFailedKeepTask(id, attempts, submittedAt, taskId,
              tStep.terminalError ?? _capMessage);
          return;
        }
        continue;
      }
      final status = data['status']?.toString() ?? '';
      final serverError =
          (data['error_message'] ?? data['message'])?.toString() ?? '';
      final pStep = nextPollStep(
        consecutiveTransients: transients,
        deadlineReached: false,
        lastRequestTransientFailure: false,
        taskStatus: status,
        errorMessage: serverError.isEmpty ? null : serverError,
      );
      transients = pStep.consecutiveTransients;
      switch (pStep.outcome) {
        case PollOutcome.keepPolling:
          continue;
        case PollOutcome.taskFailedTerminal:
          // Server says the task is dead — nothing left to poll, so the id
          // is cleared and a later Regenerate may submit fresh.
          await _tryMarkTerminalFailed(id, attempts, submittedAt,
              pStep.terminalError ?? 'Tripo generation failed');
          return;
        case PollOutcome.timedOutLeftRunning:
        case PollOutcome.transientCapReached:
          // Unreachable here (deadline handled above; not a transient step).
          return;
        case PollOutcome.taskSucceeded:
          break;
      }

      // ── Success: download promptly — Tripo URLs expire (~5 min). ───────
      final output = data['output'];
      if (output is! Map<String, dynamic>) {
        await _tryWriteFailedKeepTask(
            id,
            attempts,
            submittedAt,
            taskId,
            'Tripo task $taskId succeeded but returned no output — Retry '
            're-checks the task (no new charge).');
        return;
      }
      final modelUrl = output['model_url']?.toString() ?? '';
      if (!modelUrl.startsWith('http')) {
        await _tryWriteFailedKeepTask(
            id,
            attempts,
            submittedAt,
            taskId,
            'Tripo task $taskId succeeded but has no model_url — Retry '
            're-checks the task (no new charge).');
        return;
      }
      final credits = data['credits_consumed'];
      debugPrint('[model-3d] task $taskId done'
          '${credits != null ? ' ($credits credits)' : ''}');

      Uint8List glb;
      try {
        final resp =
            await _http.get(Uri.parse(modelUrl)).timeout(_downloadTimeout);
        if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
          // A FINISHED paid task whose CDN blipped (5xx/429/short expiry) —
          // keep the task id so Retry re-polls the SAME task for free
          // instead of submitting a new paid one.
          await _tryWriteFailedKeepTask(
              id,
              attempts,
              submittedAt,
              taskId,
              'Could not download the finished model '
              '(HTTP ${resp.statusCode}) — Retry re-checks the task '
              '(no new charge).');
          return;
        }
        glb = _rescaleToProduct(resp.bodyBytes, dims);
      } on TimeoutException {
        await _tryWriteFailedKeepTask(
            id,
            attempts,
            submittedAt,
            taskId,
            'Downloading the finished model timed out — Retry re-checks the '
            'task (no new charge).');
        return;
      } on http.ClientException {
        await _tryWriteFailedKeepTask(
            id,
            attempts,
            submittedAt,
            taskId,
            'Network error while downloading the finished model — Retry '
            're-checks the task (no new charge).');
        return;
      } on MissingDimensionsException {
        await _tryWriteFailedKeepTask(id, attempts, submittedAt, taskId,
            needsDimensionsMessage);
        return;
      } on TripoApiException catch (e) {
        // Only the degenerate-geometry check in _rescaleToProduct reaches
        // here — a data-quality problem: nothing is left to poll, so the
        // task id is cleared and a regeneration may submit fresh geometry.
        await _tryMarkTerminalFailed(
            id, attempts, submittedAt, e.message);
        return;
      } on GlbParseException {
        await _tryMarkTerminalFailed(
            id,
            attempts,
            submittedAt,
            'The generated model could not be parsed as GLB — tap '
            'Regenerate 3D for fresh geometry.');
        return;
      } on GlbRescaleException {
        await _tryMarkTerminalFailed(
            id,
            attempts,
            submittedAt,
            'The generated model could not be rescaled to the product '
            'size — tap Regenerate 3D for fresh geometry.');
        return;
      }

      // ── Publish. A product deleted mid-generation is never charged a
      //    media upload or flipped to ready — the doc is checked BEFORE the
      //    upload AND again before the terminal update. ─────────────────────
      if (!await _store.productExists(id)) {
        debugPrint('[model-3d] product $id was deleted mid-generation — '
            'dropping the model');
        return;
      }
      final url = await _media.uploadModelBytes(glb, storagePathFor(id));
      if (!await _store.productExists(id)) {
        debugPrint('[model-3d] product $id was deleted before publishing — '
            'model kept in storage for nothing, doc untouched');
        return;
      }
      await _writeDoc(id, _ar3dMap(
            status: 'ready',
            url: url,
            taskId: '', // no task left to poll
            attempts: attempts,
            submittedAt: submittedAt,
            generatedAt: _clock().toUtc(),
          ));
      debugPrint('[model-3d] "$name" ($id) is 3D-ready ($url)');
      return;
    }
  }

  /// Rescales Tripo output (arbitrary baked scale — e.g. a 0.70 m mesh for a
  /// 0.50 m product) to the SELLER's declared size and grounds it at y = 0.
  /// Per-axis when all of W/H/D exist, uniform (height preferred) when only
  /// some do, and a [MissingDimensionsException] when none do — AR never
  /// guesses a size.
  Uint8List _rescaleToProduct(Uint8List raw, ProductDimensions dims) {
    // Validate parse before rescaling.
    final bounds = GlbBounds.fromGlbBytes(raw);
    if (bounds.isDegenerate) {
      throw TripoApiException(
          'Generated model has degenerate geometry '
          '(${bounds.widthM} × ${bounds.heightM} × ${bounds.depthM} m)');
    }
    return rescaleGlbToSellerSize(raw, dims);
  }

  // ── Store writes (ar3d only — never the whole product doc) ────────────────

  /// Full ar3d key set for every product-doc write. Firestore `.update`
  /// REPLACES the whole nested `ar3d` map, so partial writes would silently
  /// drop persisted state (taskId/attempts/submittedAt) — every write must
  /// carry the complete record.
  Map<String, dynamic> _ar3dMap({
    required String status,
    String source = 'tripo',
    String url = '',
    String error = '',
    String taskId = '',
    required int attempts,
    DateTime? submittedAt,
    DateTime? generatedAt,
  }) {
    return {
      'status': status,
      'source': source,
      'url': url,
      'error': error,
      'taskId': taskId,
      'attempts': attempts,
      if (submittedAt != null)
        'submittedAt': submittedAt.toUtc().toIso8601String(),
      if (generatedAt != null)
        'generatedAt': generatedAt.toUtc().toIso8601String(),
    };
  }

  Future<void> _writeDoc(String id, Map<String, dynamic> ar3d) {
    return _store.writeAr3d(id, ar3d);
  }

  /// Terminal failure: no task id survives (nothing left to poll — the
  /// server declared the task dead, or its output is unusable), attempts
  /// survive (they bound future AUTOMATIC submissions — the seller can still
  /// Retry explicitly).
  Future<void> _tryMarkTerminalFailed(String id, int attempts,
      [DateTime? submittedAt, String error = '']) async {
    try {
      await _writeDoc(id, _ar3dMap(
            status: 'failed',
            error: error,
            attempts: attempts,
            submittedAt: submittedAt,
          ));
      debugPrint('[model-3d] $id marked failed (task cleared): $error');
    } catch (e) {
      // Product may have been deleted mid-generation — nothing to mark.
      debugPrint('[model-3d] could not mark $id failed: $e');
    }
  }

  /// Retryable failure: the task id SURVIVES so an explicit Retry re-polls
  /// the same — already paid for — task (never a second submission).
  ///
  /// [knownTaskId] is this run's local task id. The live doc is read first
  /// (a stale caller snapshot must not erase a newer persisted id); when the
  /// live read FAILS and no local id is known, the write is REFUSED — an
  /// empty taskId write could erase the persisted one and turn a free retry
  /// into a new paid submission later. When the read succeeds and there is
  /// genuinely no id, `failed` + `''` is written (correct: nothing to keep).
  Future<void> _tryWriteFailedKeepTask(String id, int attempts,
      DateTime? submittedAt, String knownTaskId, String error) async {
    try {
      Ar3dInfo? live;
      var readOk = false;
      try {
        live = await _store.readAr3d(id);
        readOk = true;
      } catch (_) {
        readOk = false; // store implementations usually swallow this; be safe
      }
      final String taskId;
      if (readOk) {
        taskId = (live?.taskId ?? '').isNotEmpty
            ? live!.taskId
            : knownTaskId;
      } else {
        taskId = knownTaskId;
        if (taskId.isEmpty) {
          debugPrint('[model-3d] cannot keep the task for $id (live read '
              'failed and no local task id) — leaving the doc as-is: $error');
          return;
        }
      }
      await _writeDoc(id, _ar3dMap(
            status: 'failed',
            error: error,
            taskId: taskId,
            attempts: attempts,
            submittedAt: submittedAt ?? live?.submittedAt,
          ));
      debugPrint('[model-3d] $id marked failed '
          '${taskId.isEmpty ? '(no task to keep)' : '(task kept: $taskId)'}: '
          '$error');
    } catch (e) {
      debugPrint('[model-3d] could not mark $id failed: $e');
    }
  }

  String get _timeoutMessage {
    final unit = _maxWait.inMinutes >= 1
        ? '${_maxWait.inMinutes} minute${_maxWait.inMinutes == 1 ? '' : 's'}'
        : '${_maxWait.inSeconds} second${_maxWait.inSeconds == 1 ? '' : 's'}';
    return '3D generation timed out after $unit — Tripo may still finish '
        'it. Tap Retry to re-check the task (no new charge).';
  }

  static const String _capMessage = 'Tripo is unreachable — the task is '
      'still queued server-side. Retry later to check on it (no new charge).';

  // ── Proxy HTTP helpers ───────────────────────────────────────────────────

  /// Human-readable message for a non-2xx reply, phrased for the seller
  /// tapping Retry: short and plain, no HTTP codes and no JSON dumps (those
  /// go to the log in [_send], never on screen).
  ///
  /// Checked first is the PROXY's own error envelope (`{"error":{…}}`): when
  /// the request never reached Tripo — sign-in expired, server has no key —
  /// the backend already wrote the sentence, and it is the only layer that
  /// knows which it was.
  static String describeHttpFailure(int status, String body) {
    final proxied = _proxySentence(body);
    if (proxied != null) return proxied;
    if (status == 401 || status == 403) {
      return '3D generation is not authorized right now. Try again later.';
    }
    if (status == 402) {
      return '3D generation is out of credit. Top up the Tripo account and '
          'tap Retry.';
    }
    if (status == 429) {
      return 'Tripo is busy right now. Wait a moment and tap Retry.';
    }
    if (status >= 500) {
      return '3D generation is unavailable right now. Try again later.';
    }
    return '3D generation request failed. Try again.';
  }

  /// The sentence the backend proxy writes for its OWN failures, or null when
  /// the body is Tripo's (or not JSON at all).
  static String? _proxySentence(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final error = decoded['error'];
    if (error is! Map<String, dynamic>) return null;
    final message = error['message']?.toString().trim();
    return (message == null || message.isEmpty) ? null : message;
  }

  /// Which class of failure an HTTP status is: 5xx / 429 / 408 are worth
  /// retrying (transient), everything else 4xx is a request problem that a
  /// retry cannot fix (terminal).
  static bool isTransientHttpStatus(int status) =>
      status >= 500 || status == 429 || status == 408;

  /// Firebase ID token for the proxy — the paid Tripo key never leaves the
  /// backend, so this is the only credential this class carries.
  Future<String> _authToken() async {
    final String? token;
    try {
      token = await _idTokenProvider();
    } catch (e) {
      debugPrint('[model-3d] could not read the sign-in token: $e');
      throw const TripoTransientApiException(
          'Could not confirm your sign-in. Try again.');
    }
    if (token == null || token.trim().isEmpty) {
      // Fail fast: an unauthenticated call would only earn a 401 from the
      // proxy. The caller keeps any persisted task id either way.
      throw const TripoApiException('Please sign in to generate 3D models.');
    }
    return token;
  }

  Future<Map<String, dynamic>> _send(
      Future<http.Response> Function() request) async {
    http.Response resp;
    try {
      resp = await request().timeout(_requestTimeout);
    } on TimeoutException {
      throw const TripoTransientApiException('3D generation timed out');
    } on http.ClientException catch (e) {
      throw TripoTransientApiException('3D generation network error: ${e.message}');
    } on SocketException catch (e) {
      // dart:io failures (no route to host, connection reset) must be
      // TRANSIENT — they previously escaped as generic errors and destroyed
      // the persisted task id.
      throw TripoTransientApiException('3D generation network error: ${e.message}');
    } on HttpException catch (e) {
      throw TripoTransientApiException('3D generation network error: ${e.message}');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      _logDiagnostic(resp.statusCode, resp.body);
      final message = describeHttpFailure(resp.statusCode, resp.body);
      if (isTransientHttpStatus(resp.statusCode)) {
        throw TripoTransientApiException(message);
      }
      throw TripoApiException(message);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } on FormatException catch (e) {
      throw TripoTransientApiException(
          '3D generation returned malformed JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const TripoTransientApiException(
          '3D generation returned a non-JSON-object body');
    }
    final code = decoded['code'];
    if (code is num && code != 0) {
      final data = decoded['data'];
      final raw = data is Map<String, dynamic>
          ? (data['message'] ?? data['error_message'])?.toString()
          : decoded['message']?.toString();
      final detail = raw ?? 'error code $code';
      final lower = detail.toLowerCase();
      if (lower.contains('credit') || lower.contains('insufficient')) {
        _logDiagnostic(code, detail);
        throw const TripoApiException(
            '3D generation is out of credit. Top up the Tripo account and '
            'tap Retry.');
      }
      if (lower.contains('unauthorized') ||
          lower.contains('forbidden') ||
          lower.contains('api key') ||
          lower.contains('apikey')) {
        _logDiagnostic(code, detail);
        throw const TripoApiException(
            '3D generation is not authorized right now. Try again later.');
      }
      _logDiagnostic(code, detail);
      throw const TripoApiException('3D generation failed. Try again.');
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw const TripoApiException(
          '3D generation returned no result. Try again.');
    }
    return data;
  }

  /// Diagnostics belong in the log, never on the seller's product chip.
  static void _logDiagnostic(Object code, String body) {
    final excerpt = body.length > 200 ? '${body.substring(0, 200)}…' : body;
    debugPrint('[model-3d] upstream $code: $excerpt');
  }

  Future<Map<String, dynamic>> _postJson(
    String url, {
    required Map<String, dynamic> body,
  }) async {
    final token = await _authToken();
    return _send(() => _http.post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(body),
        ));
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final token = await _authToken();
    return _send(() => _http.get(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $token'},
        ));
  }

  static String _describe(Object e) {
    if (e is TripoApiException) return e.message;
    if (e is MissingDimensionsException) return needsDimensionsMessage;
    if (e is GlbRescaleException || e is GlbParseException) {
      return 'The generated model could not be prepared at the product’s '
          'size — tap Regenerate 3D for fresh geometry.';
    }
    // Never surface a raw exception dump; the stack is already in the logs.
    return '3D generation hit an unexpected problem — tap Regenerate 3D.';
  }
}
