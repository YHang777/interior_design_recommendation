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

class TripoApiException implements Exception {
  const TripoApiException(this.message);

  final String message;

  @override
  String toString() => 'TripoApiException: $message';
}

class TripoTransientApiException extends TripoApiException {
  const TripoTransientApiException(super.message);
}

abstract class ProductAr3dStore {
  Future<void> writeAr3d(String productId, Map<String, dynamic> ar3d);

  Future<bool> productExists(String productId);

  Future<Ar3dInfo?> readAr3d(String productId);
}

class FirestoreAr3dStore implements ProductAr3dStore {
  FirestoreAr3dStore(this._db);

  final FirebaseFirestore _db;

  @override
  Future<void> writeAr3d(String productId, Map<String, dynamic> ar3d) {
    return _db.collection('products').doc(productId).update({'ar3d': ar3d});
  }

  @override
  Future<bool> productExists(String productId) async {
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

  static String storagePathFor(String productId) =>
      'product_models/$productId';

  final ProductAr3dStore _store;
  final MediaStore _media;
  final http.Client _http;
  final DateTime Function() _clock;
  final Duration _pollInterval;
  final Duration _maxWait;
  final Future<String?> Function() _idTokenProvider;

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

  static bool get isConfigured => AppConfig.tripoApiUrl.trim().isNotEmpty;

  static final Set<String> _inFlight = {};

  static bool isRunning(String productId) => _inFlight.contains(productId);

  Future<void> generateForProduct(Product product) async {
    final id = product.id.trim();
    if (id.isEmpty) return;
    if (!_inFlight.add(id)) {
      debugPrint('[model-3d] generation already running for $id — skipped');
      return;
    }
    final ar3d = product.ar3d;
    var attempts = ar3d?.attempts ?? 0;
    var submittedAt = ar3d?.submittedAt;
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
      final sellerDims = dims!;

      attempts = attempts + 1;
      submittedAt = _clock().toUtc();
      debugPrint('[model-3d] Tripo submission #$attempts for '
          '"${product.name}" ($id)');

      await _writeDoc(id, _ar3dMap(
            status: 'generating',
            taskId: '',
            attempts: attempts,
            submittedAt: submittedAt,
          ));

      final submitData = await _postJson(
        '$_apiBase/generation/image-to-model',
        body: {
          'input': product.image,
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

      await _writeDoc(id, _ar3dMap(
            status: 'generating',
            taskId: taskId,
            attempts: attempts,
            submittedAt: submittedAt,
          ));

      await _pollToPublish(
        id: id,
        name: product.name,
        dims: sellerDims,
        taskId: taskId,
        attempts: attempts,
        submittedAt: submittedAt,
      );
    } catch (e) {
      debugPrint('[model-3d] generation failed for $id: $e');
      await _tryWriteFailedKeepTask(
          id, attempts, submittedAt, taskId, _describe(e));
    } finally {
      _inFlight.remove(id);
    }
  }

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
      if (!await _store.productExists(id)) {
        debugPrint('[model-3d] product $id was deleted — poll abandoned');
        return;
      }
      final dims = product.dimensions;
      if (!hasAnySellerDimension(dims)) {
        await _tryWriteFailedKeepTask(id, ar3d.attempts, ar3d.submittedAt,
            ar3d.taskId, needsDimensionsMessage);
        return;
      }
      final sellerDims = dims!;
      await _pollToPublish(
        id: id,
        name: product.name,
        dims: sellerDims,
        taskId: ar3d.taskId,
        attempts: ar3d.attempts,
        submittedAt: ar3d.submittedAt,
      );
    } catch (e) {
      debugPrint('[model-3d] re-poll failed for $id: $e');
      await _tryWriteFailedKeepTask(id, ar3d.attempts, ar3d.submittedAt,
          ar3d.taskId, _describe(e));
    } finally {
      _inFlight.remove(id);
    }
  }

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
          await _tryMarkTerminalFailed(id, attempts, submittedAt,
              pStep.terminalError ?? 'Tripo generation failed');
          return;
        case PollOutcome.timedOutLeftRunning:
        case PollOutcome.transientCapReached:
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
            taskId: '',
            attempts: attempts,
            submittedAt: submittedAt,
            generatedAt: _clock().toUtc(),
          ));
      debugPrint('[model-3d] "$name" ($id) is 3D-ready ($url)');
      return;
    }
  }

  Uint8List _rescaleToProduct(Uint8List raw, ProductDimensions dims) {
    final bounds = GlbBounds.fromGlbBytes(raw);
    if (bounds.isDegenerate) {
      throw TripoApiException(
          'Generated model has degenerate geometry '
          '(${bounds.widthM} × ${bounds.heightM} × ${bounds.depthM} m)');
    }
    return rescaleGlbToSellerSize(raw, dims);
  }

  // ── Store writes (ar3d only — never the whole product doc) ────────────────

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
      debugPrint('[model-3d] could not mark $id failed: $e');
    }
  }

  Future<void> _tryWriteFailedKeepTask(String id, int attempts,
      DateTime? submittedAt, String knownTaskId, String error) async {
    try {
      Ar3dInfo? live;
      var readOk = false;
      try {
        live = await _store.readAr3d(id);
        readOk = true;
      } catch (_) {
        readOk = false;
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

  static bool isTransientHttpStatus(int status) =>
      status >= 500 || status == 429 || status == 408;

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
    return '3D generation hit an unexpected problem — tap Regenerate 3D.';
  }
}
