import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../features/customer/ar/data/glb_bounds.dart';
import '../../features/customer/ar/data/glb_rescaler.dart';
import '../../models/product.dart';

/// Thrown when a product's 3D model cannot be resolved AT ALL. The reason is
/// always specific and actionable — the resolver has exactly ONE model
/// source (a ready Tripo download) plus hard-stop preconditions, and it
/// never substitutes another model. Callers (the AR viewer screen) surface
/// [reason] verbatim instead of falling back to a catalog model.
class No3dAvailableException implements Exception {
  const No3dAvailableException([this.reason]);

  final String? reason;

  @override
  String toString() => reason == null
      ? 'No3dAvailableException: no 3D model available for this product'
      : 'No3dAvailableException: $reason';
}

/// A product's GLB materialized as a local file, ready for AR placement.
class ResolvedGlb {
  const ResolvedGlb({required this.file});

  /// Absolute path to the GLB on disk (app documents/`ar_models/`).
  ///
  /// Feed `Uri.file(file.path).toString()` to
  /// `ARNode(type: NodeType.fileSystemAppFolderGLB, …)` — the plugin reads
  /// the file directly. Geometry already spans the seller's exact W×H/D
  /// meters (grounded at y = 0), so the node's uniform scale is 1.0.
  final File file;

  @override
  String toString() => 'ResolvedGlb(${file.path})';
}

/// Materializes a [Product]'s 3D model as a local GLB file at TRUE size —
/// the single product-model path in the app.
///
/// The ONLY model source is a Tripo AI generation (`ar3d.status == 'ready'`
/// with an http(s) `url`, downloaded here). There is no procedural
/// generation, no category-default dimensions, and no bundled-catalog
/// fallback for products: every failure below throws
/// [No3dAvailableException] with a specific, actionable reason.
///
/// Pipeline: download → validate as GLB → rescale to the SELLER's declared
/// dimensions via [rescaleGlbToSellerSize] (per-axis when all of W/H/D are
/// present, uniform (height preferred) when only some are, refused when none
/// are) → ground at y = 0 → cache.
///
/// Failures are loud, not silent:
///  * empty product id → nothing to cache under;
///  * no seller dimension at all → AR needs the product's real size;
///  * `ar3d` not ready (`none` / `generating` / `failed`) → the state's own
///    message (generation still running is NOT an error — the caller shows
///    progress);
///  * download HTTP/network failure → surfaced, never swallowed into a
///    different model;
///  * malformed GLB / degenerate geometry → surfaced.
///
/// Results are cached in the `ar_models/` subfolder of the app documents
/// directory, named `<id>_ai<generatedAt>_<dims>.glb` — one file per
/// product, pruned after each successful write. The cache key carries the
/// Tripo `generatedAt` (a new AI run replaces the cached download) and the
/// seller's dims token (a dimension edit re-rescales under a fresh key).
///
/// Pure async — the caller awaits; no UI is blocked. The class has NO
/// Firebase dependency: only the product object and the local filesystem are
/// touched, so tests run headless with an injected cache directory.
class ModelGlbResolver {
  ModelGlbResolver({
    Future<Directory> Function()? cacheRootProvider,
    http.Client? httpClient,
    Duration downloadTimeout = const Duration(seconds: 60),
  })  : _cacheRootProvider =
            cacheRootProvider ?? getApplicationDocumentsDirectory,
        _http = httpClient ?? http.Client(),
        _downloadTimeout = downloadTimeout;

  /// Folder holding the GLB cache, inside the app documents directory
  /// (`.../app_flutter/ar_models/` on Android — visible to the AR plugin's
  /// `fileSystemAppFolder` node type).
  static const String cacheDirName = 'ar_models';

  final Future<Directory> Function() _cacheRootProvider;
  final http.Client _http;
  final Duration _downloadTimeout;

  /// Releases the underlying HTTP client. Idempotent.
  void dispose() => _http.close();

  /// Resolves the product's Tripo GLB at the seller's size.
  ///
  /// Throws [No3dAvailableException] (with an actionable reason) whenever
  /// the model cannot be produced — see the class docs for the full list.
  Future<ResolvedGlb> resolveProductGlb(Product product) async {
    final dims = product.dimensions;
    final id = product.id.trim();
    if (id.isEmpty) {
      throw const No3dAvailableException(
          'product id is empty — cannot cache a 3D model for it');
    }
    // Seller dimensions are the only source of truth for size. Without at
    // least one declared axis there is no true size to place at → refuse
    // (never guess, never substitute another model).
    if (!hasAnySellerDimension(dims)) {
      throw const No3dAvailableException(
          'This product has no Width/Height/Depth yet. AR needs the '
          "product's real-world size — open the product form and set its "
          'dimensions (meters), then reopen AR.');
    }
    final ar3d = product.ar3d;
    if (ar3d == null || ar3d.isNone) {
      throw const No3dAvailableException(
          'No 3D model has been generated for this product yet. In the '
          "seller's product list, tap Regenerate 3D to create the AI model "
          '(a Tripo generation), then reopen AR.');
    }
    if (ar3d.status == 'generating') {
      // Not an error — the viewer shows generation progress instead.
      throw const No3dAvailableException('generating');
    }
    if (ar3d.status == 'failed') {
      final detail = ar3d.error.trim();
      throw No3dAvailableException(
          detail.isEmpty
              ? '3D generation failed for this product. In the seller’s '
                  'product list, tap Retry to re-check the Tripo task '
                  '(no new charge) or start a new generation.'
              : '3D generation failed: $detail — in the seller’s product '
                  'list, tap Retry to re-check the Tripo task (no new '
                  'charge).');
    }
    if (ar3d.status != 'ready') {
      throw No3dAvailableException(
          'unexpected 3D state "${ar3d.status}" for this product.');
    }
    if (!ar3d.url.startsWith('http')) {
      // A ready record without a downloadable URL is a legacy / broken
      // record (the old procedural path could stamp `ready` with url '').
      throw const No3dAvailableException(
          'This product’s 3D record has no downloadable model URL. In the '
          "seller's product list, tap Regenerate 3D to create a fresh Tripo "
          'model.');
    }

    final cacheDir = await _ensureCacheDir();
    final dimsToken = _sanitize(dims!.label); // non-null: guarded above
    final target = File('${cacheDir.path}${Platform.pathSeparator}'
        '${_sanitize(id)}_${_aiStamp(ar3d)}_$dimsToken.glb');
    if (target.existsSync() && target.lengthSync() > 0) {
      return ResolvedGlb(file: target);
    }

    // Download. ANY failure is a hard stop with a specific reason — there
    // is no other model to fall through to.
    final Uint8List bytes;
    try {
      final resp =
          await _http.get(Uri.parse(ar3d.url)).timeout(_downloadTimeout);
      if (resp.statusCode != 200) {
        throw No3dAvailableException(
            'downloading the 3D model failed (HTTP ${resp.statusCode}). '
            'Check the connection and tap Retry — re-downloading is free.');
      }
      if (resp.bodyBytes.isEmpty) {
        throw const No3dAvailableException(
            'the downloaded 3D model was empty. Tap Retry to download it '
            'again.');
      }
      bytes = resp.bodyBytes;
    } on No3dAvailableException {
      rethrow;
    } on TimeoutException {
      throw const No3dAvailableException(
          'downloading the 3D model timed out. Check the connection and '
          'tap Retry — re-downloading is free.');
    } catch (e) {
      debugPrint('[model-3d] download of ${ar3d.url} failed: $e');
      throw No3dAvailableException(
          'downloading the 3D model failed ($e). Check the connection and '
          'tap Retry — re-downloading is free.');
    }

    // Validate + resize to the seller's declared size (throws
    // GlbParseException / GlbRescaleException / MissingDimensionsException
    // with specifics — all surfaced verbatim).
    final Uint8List prepared;
    try {
      GlbBounds.fromGlbBytes(bytes); // throws GlbParseException on garbage
      prepared = rescaleGlbToSellerSize(bytes, dims);
    } on MissingDimensionsException {
      throw const No3dAvailableException(
          'This product has no Width/Height/Depth yet. AR needs the '
          "product's real-world size — set its dimensions (meters) in the "
          'product form.');
    } catch (e) {
      debugPrint('[model-3d] prepare of ${ar3d.url} failed: $e');
      throw No3dAvailableException(
          'the 3D model could not be prepared at the product’s size ($e). '
          'Tap Regenerate 3D to create a fresh model.');
    }

    await _writeAndPrune(cacheDir, id, target, prepared);
    return ResolvedGlb(file: target);
  }

  /// The cache-stamp segment of a ready network model: the Tripo
  /// `generatedAt` epoch (a new AI run replaces the cached download), or a
  /// URL hash for legacy ready docs without a timestamp.
  static String _aiStamp(Ar3dInfo ar3d) {
    final at = ar3d.generatedAt;
    return at != null
        ? 'ai${at.millisecondsSinceEpoch}'
        : 'ai_${_fnv1a(ar3d.url)}';
  }

  Future<Directory> _ensureCacheDir() async {
    final root = await _cacheRootProvider();
    final dir = Directory('${root.path}${Platform.pathSeparator}$cacheDirName');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<void> _writeAndPrune(Directory cacheDir, String productId,
      File target, Uint8List bytes) async {
    await target.writeAsBytes(bytes, flush: true);
    // Keep exactly one cached model per product.
    final prefix = '${_sanitize(productId)}_';
    try {
      for (final f in cacheDir.listSync()) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last;
        if (name.startsWith(prefix) &&
            name.endsWith('.glb') &&
            f.path != target.path) {
          f.deleteSync();
        }
      }
    } catch (e) {
      debugPrint('[model-3d] cache prune failed: $e');
    }
  }

  /// Deletes every cached GLB belonging to [productId]. Best-effort — used
  /// when a product is deleted so its documents-cache model goes too.
  static Future<void> pruneCacheForProduct(String productId) async {
    if (productId.trim().isEmpty) return;
    try {
      final root = await getApplicationDocumentsDirectory();
      final dir =
          Directory('${root.path}${Platform.pathSeparator}$cacheDirName');
      if (!dir.existsSync()) return;
      final prefix = '${_sanitize(productId)}_';
      for (final f in dir.listSync()) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last;
        if (name.startsWith(prefix) && name.endsWith('.glb')) {
          f.deleteSync();
        }
      }
    } catch (e) {
      debugPrint('[model-3d] cache prune for $productId failed: $e');
    }
  }

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  /// Deterministic FNV-1a (model output must not depend on VM hashing).
  static String _fnv1a(String text) {
    var h = 0x811C9DC5;
    for (final c in text.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }
}
