import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../config/app_config.dart';
import '../../features/ar/data/glb_bounds.dart';
import '../../features/ar/data/glb_rescaler.dart';
import '../../models/product.dart';
import '../media/media_store.dart';
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

/// Asynchronous AI 3D generation for a single product via the Tripo 3D API
/// (image-to-model): submit → poll → download the resulting GLB → rescale it
/// to the product's exact dimensions (the AR plugin only scales uniformly at
/// placement, so true size is baked into the geometry) → publish the rescaled
/// GLB through [MediaStore] (Cloudinary raw upload) → flip `product.ar3d` to
/// `ready`.
///
/// Endpoints (doc-verified 2026-09 against
/// https://developers.tripo3d.ai — quick-start / task-query pages):
///  - submit:   POST https://openapi.tripo3d.ai/v3/generation/image-to-model
///              body: {"input": imageUrl, "texture": true, "pbr": true,
///              "face_limit": 100000, "auto_size": true,
///              "model": modelVersion} → reply {"code": 0,
///              "data": {"task_id": "task_…"}}; imageUrl must be a PUBLIC
///              image URL (Tripo fetches it server-side), modelVersion is
///              AppConfig.tripoModelVersion.
///  - query:    GET https://openapi.tripo3d.ai/v3/tasks/{task_id}
///              (NB: the query endpoint is a GET on `/v3/tasks/{id}` — not
///              `POST /generation/tasks/{id}`) → `data.status` is
///              queued | running | success | failed | cancelled (…); on
///              success `data.output.model_url` (+ `rendered_image_url`);
///              on failure `data.error_message` / `error_code`.
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
///  - the poll state machine (see tripo_poll_state.dart): a 5-minute deadline
///    leaves the doc `generating` (the server-side task may still finish);
///    after 4 consecutive transient poll failures the doc is marked `failed`
///    but KEEPS its task id so an explicit Retry re-polls the same task.
///
/// Product-doc writes are PARTIAL `.update({'ar3d': {...}})` calls only —
/// never a full-document overwrite (sales, ratings and concurrent edits must
/// survive). Published models land in Cloudinary under the public_id
/// `product_models/<productId>-<millis>` (a unique suffix is appended by the
/// store because unsigned uploads cannot overwrite an existing public_id).
///
/// Costs: Tripo is pay-as-you-go (~US$0.30 per textured model; free signup
/// credits may apply). Configure the key in LocalConfig
/// (`LocalConfig.tripoApiKey` / `--dart-define=TRIPO_API_KEY`) — see
/// https://platform.tripo3d.ai. When unconfigured [isConfigured] is false and
/// the pipeline never runs (the app stays on the free procedural generator).
class Tripo3DGenerator {
  Tripo3DGenerator(
    FirebaseFirestore db, {
    MediaStore? mediaStore,
    http.Client? httpClient,
    DateTime Function()? clock,
  })  : _db = db,
        _media = mediaStore ?? MediaStore.instance,
        _http = httpClient ?? http.Client(),
        _clock = clock ?? DateTime.now;

  static const String _apiBase = 'https://openapi.tripo3d.ai/v3';
  static const Duration _requestTimeout = Duration(seconds: 30);
  static const Duration _downloadTimeout = Duration(seconds: 120);
  static const Duration _pollInterval = Duration(seconds: 5);
  static const Duration _maxWait = Duration(minutes: 5);

  /// Remote path (Cloudinary public_id base) of a product's AI model blob.
  static String storagePathFor(String productId) =>
      'product_models/$productId';

  final FirebaseFirestore _db;
  final MediaStore _media;
  final http.Client _http;
  final DateTime Function() _clock;

  /// Whether an API key is configured (LocalConfig → TRIPO_API_KEY dart-
  /// define). Without one the pipeline never runs (and never spends money).
  static bool get isConfigured => AppConfig.tripoApiKey.trim().isNotEmpty;

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
  /// doc (`ar3d.status == 'failed'`) — the only uncaught paths are Firestore
  /// failures after the doc has been deleted (logged), so callers may safely
  /// `unawaited(...)`.
  ///
  /// Callers gate this via `decideGeneration` (see generation_decider.dart):
  /// only a `submitNewTripo` decision reaches here, so eligibility
  /// (configured key, network image, complete dimensions) is guaranteed —
  /// the guards below are belt-and-braces that silently skip otherwise.
  Future<void> generateForProduct(Product product) async {
    final id = product.id.trim();
    if (id.isEmpty || !isConfigured) {
      debugPrint('[model-3d] Tripo not configured — skipping generation '
          'for "${product.name}"');
      return;
    }
    final dims = product.dimensions;
    if (!product.hasNetworkImage ||
        dims == null ||
        !dims.isComplete) {
      debugPrint('[model-3d] product ${product.name} is not Tripo-eligible '
          '(needs a public photo URL and complete dims) — skipped');
      return;
    }
    if (!_inFlight.add(id)) {
      debugPrint('[model-3d] generation already running for $id — skipped');
      return;
    }
    final attempts = (product.ar3d?.attempts ?? 0) + 1;
    final submittedAt = _clock().toUtc();
    debugPrint('[model-3d] Tripo submission #$attempts for '
        '"${product.name}" ($id)');
    try {
      // 1) Visible state FIRST (crash-safe resume point). Persisting the
      //    incremented attempts here means even a crash before the POST can
      //    never spin an unbounded auto-submit loop — the decider caps it.
      await _writeDoc(id, _ar3dMap(
            status: 'generating',
            source: 'tripo',
            taskId: '',
            attempts: attempts,
            submittedAt: submittedAt,
          ));

      // 2) Submit the image-to-model task.
      final submitData = await _postJson(
        '$_apiBase/generation/image-to-model',
        body: {
          'input': product.image, // Tripo fetches the public URL server-side
          'texture': true,
          'pbr': true,
          'face_limit': 100000,
          'auto_size': true,
          'model': AppConfig.tripoModelVersion,
        },
      );
      final taskId = (submitData['task_id'] as String?)?.trim();
      if (taskId == null || taskId.isEmpty) {
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
            source: 'tripo',
            taskId: taskId,
            attempts: attempts,
            submittedAt: submittedAt,
          ));

      // 4) Poll → download → rescale → upload → mark ready.
      await _pollToPublish(
        id: id,
        name: product.name,
        dims: dims,
        taskId: taskId,
        attempts: attempts,
        submittedAt: submittedAt,
      );
    } catch (e) {
      debugPrint('[model-3d] generation failed for $id: $e');
      await _tryMarkTerminalFailed(id, attempts, _describe(e));
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
  /// No product-doc write happens unless the poll reaches a terminal state
  /// (success → ready; server failure → failed; transient cap → failed with
  /// the task id KEPT; deadline → the doc stays as it was, re-poll later).
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
      if (!await _productDocExists(id)) {
        debugPrint('[model-3d] product $id was deleted — poll abandoned');
        return;
      }
      final dims = product.dimensions;
      if (dims == null || !dims.isComplete) {
        // The task may finish server-side, but without dimensions we cannot
        // bake true size — surface a retryable failure instead of a stuck
        // `generating` doc.
        await _tryMarkTerminalFailed(id, ar3d.attempts,
            'Missing dimensions — set Width/Height/Depth in meters');
        return;
      }
      await _pollToPublish(
        id: id,
        name: product.name,
        dims: dims,
        taskId: ar3d.taskId,
        attempts: ar3d.attempts,
        submittedAt: ar3d.submittedAt,
      );
    } catch (e) {
      debugPrint('[model-3d] re-poll failed for $id: $e');
      await _tryMarkTerminalFailed(id, ar3d.attempts, _describe(e));
    } finally {
      _inFlight.remove(id);
    }
  }

  /// Polls [taskId] until the pure state machine (tripo_poll_state.dart)
  /// reaches a terminal outcome, then publishes the model. Writes:
  ///  - success → download/rescale → (product-doc-exists check) → Storage
  ///    upload → (second exists check) → `ready`;
  ///  - server terminal failure → `failed` (task id cleared);
  ///  - 4 consecutive transient poll failures → `failed` WITH the task id
  ///    kept (an explicit Retry re-polls the same — already paid — task);
  ///  - 5-minute deadline → NO write: the doc stays `generating` with its
  ///    task id, and boot-resume / Retry re-checks it later.
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
      // ── Deadline: leave the task running server-side, no write. ────────
      final step = nextPollStep(
        consecutiveTransients: transients,
        deadlineReached: !_clock().isBefore(deadline),
        lastRequestTransientFailure: false,
        taskStatus: '',
      );
      if (step.outcome == PollOutcome.timedOutLeftRunning) {
        debugPrint('[model-3d] task $taskId passed ${_maxWait.inMinutes} min — '
            'leaving it running; a later retry will re-check it for $id');
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
      final serverError = (data['error_message']?.toString() ??
              data['message']?.toString()) ??
          '';
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
          await _tryMarkTerminalFailed(id, attempts,
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
        await _tryMarkTerminalFailed(
            id, attempts, 'Tripo task $taskId succeeded but returned no output');
        return;
      }
      final modelUrl = output['model_url']?.toString() ?? '';
      if (!modelUrl.startsWith('http')) {
        await _tryMarkTerminalFailed(
            id, attempts, 'Tripo task $taskId succeeded but has no model_url');
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
              id, attempts, submittedAt, taskId,
              'Could not download the finished model '
              '(HTTP ${resp.statusCode}) — Retry re-checks the task '
              '(no new charge).');
          return;
        }
        glb = _rescaleToProduct(resp.bodyBytes, dims);
      } on TimeoutException {
        await _tryWriteFailedKeepTask(
            id, attempts, submittedAt, taskId,
            'Downloading the finished model timed out — Retry re-checks the '
            'task (no new charge).');
        return;
      } on http.ClientException {
        await _tryWriteFailedKeepTask(
            id, attempts, submittedAt, taskId,
            'Network error while downloading the finished model — Retry '
            're-checks the task (no new charge).');
        return;
      } on TripoApiException catch (e) {
        // Only the degenerate-geometry check in _rescaleToProduct reaches
        // here — a data-quality problem, terminal: clearing the task lets a
        // regeneration submit fresh (a new task may produce valid geometry).
        await _tryMarkTerminalFailed(id, attempts, e.message);
        return;
      } on GlbParseException {
        await _tryMarkTerminalFailed(id, attempts,
            'The generated model could not be parsed as GLB');
        return;
      } on GlbRescaleException {
        await _tryMarkTerminalFailed(id, attempts,
            'The generated model could not be rescaled to the product '
            'dimensions');
        return;
      }

      // ── Publish. Fix: a product deleted mid-generation is never charged
      //    a media upload or flipped to ready — the doc is checked BEFORE
      //    the upload AND again before the terminal update. ───────────────
      if (!await _productDocExists(id)) {
        debugPrint('[model-3d] product $id was deleted mid-generation — '
            'dropping the model');
        return;
      }
      final url = await _media.uploadModelBytes(glb, storagePathFor(id));
      if (!await _productDocExists(id)) {
        debugPrint('[model-3d] product $id was deleted before publishing — '
            'model kept in storage for nothing, doc untouched');
        return;
      }
      await _writeDoc(id, _ar3dMap(
            status: 'ready',
            source: 'tripo',
            url: url,
            taskId: '', // no task left to poll
            attempts: attempts,
            generatedAt: _clock().toUtc(),
          ));
      debugPrint('[model-3d] "$name" ($id) is 3D-ready ($url)');
      return;
    }
  }

  /// Rescales Tripo output (arbitrary baked scale, float-unsafe for exact
  /// dims) to the product's exact W×H×D and grounds it at y = 0.
  Uint8List _rescaleToProduct(Uint8List raw, ProductDimensions dims) {
    // Validate parse before rescaling.
    final bounds = GlbBounds.fromGlbBytes(raw);
    if (bounds.isDegenerate) {
      throw TripoApiException(
          'Generated model has degenerate geometry '
          '(${bounds.widthM} × ${bounds.heightM} × ${bounds.depthM} m)');
    }
    return rescaleGlbToDimensions(
      raw,
      targetWidthM: dims.widthM,
      targetHeightM: dims.heightM,
      targetDepthM: dims.depthM,
    );
  }

  // ── Firestore partial updates (ar3d only — never the whole doc) ─────────

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

  Future<void> _writeDoc(String id, Map<String, dynamic> ar3d) async {
    await _db.collection('products').doc(id).update({'ar3d': ar3d});
  }

  /// Whether the product doc still exists. Firestore reads of missing docs
  /// return `exists == false` (no throw); read errors are logged and treated
  /// as "can't know" → the caller proceeds (its own write will surface a
  /// missing doc).
  Future<bool> _productDocExists(String id) async {
    try {
      final snap = await _db.collection('products').doc(id).get();
      return snap.exists;
    } catch (e) {
      debugPrint('[model-3d] doc-existence check for $id failed: $e');
      return true;
    }
  }

  /// Terminal failure: no task id survives (nothing left to poll), attempts
  /// survive (they bound future AUTOMATIC submissions — the seller can still
  /// Retry explicitly).
  Future<void> _tryMarkTerminalFailed(
      String id, int attempts, String error) async {
    try {
      await _writeDoc(id, _ar3dMap(
            status: 'failed',
            error: error,
            attempts: attempts,
          ));
      debugPrint('[model-3d] $id marked failed (task cleared): $error');
    } catch (e) {
      // Product may have been deleted mid-generation — nothing to mark.
      debugPrint('[model-3d] could not mark $id failed: $e');
    }
  }

  /// Transient-cap failure: the task id SURVIVES so an explicit Retry
  /// re-polls the same — already paid for — task (never a second submission).
  /// [knownTaskId] is this run's local task id, used when the live doc read
  /// fails; if neither source yields an id the write is REFUSED (an empty
  /// taskId write would erase the persisted one and turn a free retry into a
  /// new paid submission later).
  Future<void> _tryWriteFailedKeepTask(String id, int attempts,
      DateTime? submittedAt, String knownTaskId, String error) async {
    try {
      final ar3d = await _currentAr3d(id);
      final taskId = ar3d?.taskId ?? knownTaskId;
      if (taskId.isEmpty) {
        debugPrint('[model-3d] cannot keep the task for $id (no task id '
            'known) — leaving the doc as-is: $error');
        return;
      }
      await _writeDoc(id, _ar3dMap(
            status: 'failed',
            error: error,
            taskId: taskId,
            attempts: attempts,
            submittedAt: submittedAt,
          ));
      debugPrint('[model-3d] $id marked failed (task kept): $error');
    } catch (e) {
      debugPrint('[model-3d] could not mark $id failed: $e');
    }
  }

  /// Reads the live `ar3d` of [id] (null when absent / unreadable) — used to
  /// preserve the task id across a transient-cap write without trusting a
  /// possibly stale caller snapshot.
  Future<Ar3dInfo?> _currentAr3d(String id) async {
    try {
      final snap = await _db.collection('products').doc(id).get();
      if (!snap.exists) return null;
      final data = snap.data();
      final raw = data?['ar3d'];
      return raw is Map<String, dynamic>
          ? Ar3dInfo.fromJson(raw)
          : null;
    } catch (e) {
      debugPrint('[model-3d] could not re-read ar3d of $id: $e');
      return null;
    }
  }

  static const String _capMessage = 'Tripo is unreachable — the task is '
      'still queued server-side. Retry later to check on it (no new charge).';

  // ── Tripo HTTP helpers ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _send(
      Future<http.Response> Function() request) async {
    http.Response resp;
    try {
      resp = await request().timeout(_requestTimeout);
    } on TimeoutException {
      throw const TripoTransientApiException('Tripo request timed out');
    } on http.ClientException catch (e) {
      throw TripoTransientApiException('Tripo network error: ${e.message}');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final message =
          'Tripo HTTP ${resp.statusCode}: ${resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body}';
      if (resp.statusCode >= 500) {
        // A 5xx is a server hiccup — retrying the poll may get past it.
        throw TripoTransientApiException(message);
      }
      throw TripoApiException(message);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } on FormatException catch (e) {
      throw TripoTransientApiException(
          'Tripo returned malformed JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const TripoTransientApiException(
          'Tripo returned a non-JSON-object body');
    }
    final code = decoded['code'];
    if (code is num && code != 0) {
      final data = decoded['data'];
      final message = data is Map<String, dynamic>
          ? (data['message'] ?? data['error_message'])?.toString()
          : decoded['message']?.toString();
      throw TripoApiException(message ?? 'Tripo error code $code');
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw const TripoApiException('Tripo response has no "data" object');
    }
    return data;
  }

  Future<Map<String, dynamic>> _postJson(
    String url, {
    required Map<String, dynamic> body,
  }) {
    return _send(() => _http.post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${AppConfig.tripoApiKey}',
          },
          body: jsonEncode(body),
        ));
  }

  Future<Map<String, dynamic>> _getJson(String url) {
    return _send(() => _http.get(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer ${AppConfig.tripoApiKey}'},
        ));
  }

  static String _describe(Object e) {
    if (e is TripoApiException) return e.message;
    return e.toString().replaceFirst('Exception: ', '');
  }
}
