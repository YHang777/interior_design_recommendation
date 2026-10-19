import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/user_errors.dart';
import '../../features/customer/ar/data/glb_bounds.dart';
import '../../features/customer/ar/data/glb_rescaler.dart';
import '../../models/product.dart';

class No3dAvailableException implements Exception, UserFacingException {
  const No3dAvailableException([this.reason]);

  static const String generatingSentinel = 'generating';

  final String? reason;

  @override
  String get userMessage =>
      (reason == null || reason == generatingSentinel)
          ? "This product doesn't have a 3D view right now."
          : reason!;

  @override
  String toString() => reason == null
      ? 'No3dAvailableException: no 3D model available for this product'
      : 'No3dAvailableException: $reason';
}

class ResolvedGlb {
  const ResolvedGlb({required this.file});

  final File file;

  @override
  String toString() => 'ResolvedGlb(${file.path})';
}

class ModelGlbResolver {
  ModelGlbResolver({
    Future<Directory> Function()? cacheRootProvider,
    http.Client? httpClient,
    Duration downloadTimeout = const Duration(seconds: 60),
  })  : _cacheRootProvider =
            cacheRootProvider ?? getApplicationDocumentsDirectory,
        _http = httpClient ?? http.Client(),
        _downloadTimeout = downloadTimeout;

  static const String cacheDirName = 'ar_models';

  final Future<Directory> Function() _cacheRootProvider;
  final http.Client _http;
  final Duration _downloadTimeout;

  void dispose() => _http.close();

  Future<ResolvedGlb> resolveProductGlb(Product product) async {
    final dims = product.dimensions;
    final id = product.id.trim();
    if (id.isEmpty) {
      throw const No3dAvailableException(
          'product id is empty — cannot cache a 3D model for it');
    }
    if (!hasAnySellerDimension(dims)) {
      throw const No3dAvailableException(
          "This product's size hasn't been set yet, so it can't be shown "
          'in AR.');
    }
    final ar3d = product.ar3d;
    if (ar3d == null || ar3d.isNone) {
      throw const No3dAvailableException(
          "This product doesn't have a 3D view yet. Check back later.");
    }
    if (ar3d.status == 'generating') {
      throw const No3dAvailableException(
          No3dAvailableException.generatingSentinel);
    }
    if (ar3d.status == 'failed') {
      final detail = ar3d.error.trim();
      if (detail.isNotEmpty) {
        debugPrint('[model-3d] ar3d failed for $id: $detail');
      }
      throw const No3dAvailableException(
          "This product's 3D view isn't ready yet. Check back later.");
    }
    if (ar3d.status != 'ready') {
      throw const No3dAvailableException(
          "This product's 3D view isn't ready yet. Check back later.");
    }
    if (!ar3d.url.startsWith('http')) {
      throw const No3dAvailableException(
          "This product's 3D view isn't ready yet. Check back later.");
    }

    final cacheDir = await _ensureCacheDir();
    final dimsToken = _sanitize(dims!.label);
    final target = File('${cacheDir.path}${Platform.pathSeparator}'
        '${_sanitize(id)}_${_aiStamp(ar3d)}_$dimsToken.glb');
    if (target.existsSync() && target.lengthSync() > 0) {
      return ResolvedGlb(file: target);
    }

    final Uint8List bytes;
    try {
      final resp =
          await _http.get(Uri.parse(ar3d.url)).timeout(_downloadTimeout);
      if (resp.statusCode != 200) {
        debugPrint(
            '[model-3d] download HTTP ${resp.statusCode} for ${ar3d.url}');
        throw const No3dAvailableException(
            "Couldn't load this product's 3D view. Check your connection "
            'and try again.');
      }
      if (resp.bodyBytes.isEmpty) {
        throw const No3dAvailableException(
            "This product's 3D view couldn't be loaded. Try again.");
      }
      bytes = resp.bodyBytes;
    } on No3dAvailableException {
      rethrow;
    } on TimeoutException {
      throw const No3dAvailableException(
          'This is taking too long. Check your connection and try again.');
    } catch (e) {
      debugPrint('[model-3d] download of ${ar3d.url} failed: $e');
      throw const No3dAvailableException(
          "Couldn't load this product's 3D view. Check your connection "
          'and try again.');
    }

    final Uint8List prepared;
    try {
      GlbBounds.fromGlbBytes(bytes);
      prepared = rescaleGlbToSellerSize(bytes, dims);
    } on MissingDimensionsException {
      throw const No3dAvailableException(
          "This product's size hasn't been set yet, so it can't be shown "
          'in AR.');
    } catch (e) {
      debugPrint('[model-3d] prepare of ${ar3d.url} failed: $e');
      throw const No3dAvailableException(
          "This product's 3D view couldn't be prepared. Try again later.");
    }

    await _writeAndPrune(cacheDir, id, target, prepared);
    return ResolvedGlb(file: target);
  }

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

  static String _fnv1a(String text) {
    var h = 0x811C9DC5;
    for (final c in text.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }
}
