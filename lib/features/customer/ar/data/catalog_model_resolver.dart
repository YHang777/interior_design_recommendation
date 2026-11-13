import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../scanner/data/furniture_catalog.dart';
import 'furniture_model_library.dart';
import 'glb_bounds.dart';
import 'glb_generator.dart';

class CatalogModelSource {
  const CatalogModelSource.asset(this.uri)
      : file = null,
        isBundled = true;
  const CatalogModelSource.file(this.file, {this.isBundled = false})
      : uri = null;

  final String? uri;
  final File? file;

  // Third-party authored mesh (own axes/front); generated models follow the
  // W→X, D→Z, front +Z convention.
  final bool isBundled;

  String get source => uri ?? file!.path;
  String get sourceType => uri != null ? 'asset' : 'file';
}

// IconNames whose bundled GLB is a stand-in of the wrong shape — the 3D
// planner/walkthrough generates a real model at true catalog size instead.
const Set<String> kGeneratedCatalogIcons = {
  'floor_lamp',
  'rug',
};

class CatalogModelResolver {
  CatalogModelResolver({
    Future<Directory> Function()? cacheRootProvider,
    http.Client? httpClient,
    this.downloadTimeout = const Duration(seconds: 60),
  })  : _cacheRootProvider =
            cacheRootProvider ?? getApplicationDocumentsDirectory,
        _http = httpClient;

  static const String cacheDirName = 'catalog_models';

  final Future<Directory> Function() _cacheRootProvider;
  http.Client? _http;
  final Duration downloadTimeout;

  final Map<String, CatalogModelSource?> _refs = {};

  // True once [resolveModelRef] has settled for [ref] (loaded or failed) —
  // lets the 3D scene show a stand-in instead of nothing while it downloads.
  bool isModelRefSettled(String ref) => _refs.containsKey(ref.trim());

  // A placement's own model: a bundled 'assets/models/…' file or an http(s)
  // GLB (marketplace upload / Tripo). Null when it cannot be loaded — the
  // caller falls back to the catalog model, so a piece never vanishes.
  // Downloads are reused only while they still parse as GLB (a corrupt
  // cache file once kept furniture invisible across rebuilds).
  Future<CatalogModelSource?> resolveModelRef(String ref) async {
    final key = ref.trim();
    if (key.isEmpty) return null;
    if (_refs.containsKey(key)) return _refs[key];
    CatalogModelSource? src;
    try {
      final dir = await _ensureCacheDir();
      if (key.startsWith('assets/')) {
        final data = await rootBundle.load(key);
        final bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        final name = 'bundled_${_sanitize(key.split('/').last.replaceAll('.glb', ''))}';
        final file = File('${dir.path}${Platform.pathSeparator}$name.glb');
        await file.writeAsBytes(bytes, flush: true);
        src = CatalogModelSource.file(file, isBundled: true);
      } else if (key.startsWith('http://') || key.startsWith('https://')) {
        final file = File('${dir.path}${Platform.pathSeparator}'
            'market_${_fnv1a(key)}.glb');
        if (!(file.existsSync() && _parses(file.readAsBytesSync()))) {
          final resp = await (_http ??= http.Client())
              .get(Uri.parse(key))
              .timeout(downloadTimeout);
          if (resp.statusCode != 200 || !_parses(resp.bodyBytes)) {
            debugPrint('[model-3d] planner model ${resp.statusCode} for $key');
            _refs[key] = null;
            return null;
          }
          await file.writeAsBytes(resp.bodyBytes, flush: true);
        }
        src = CatalogModelSource.file(file, isBundled: true);
      }
    } catch (e) {
      debugPrint('[model-3d] planner model failed for $key: $e');
      src = null;
    }
    _refs[key] = src;
    return src;
  }

  static bool _parses(Uint8List bytes) {
    try {
      return !GlbBounds.sceneFromGlbBytes(bytes).isDegenerate;
    } catch (_) {
      return false;
    }
  }

  // addModel loads from a file path, so every source is materialized under
  // the cache dir — bundled assets included, keeping one proven load path.
  // The file is re-authored once per resolve-cache lifetime: trusting
  // whatever sits on disk kept pre-fix corrupt GLBs alive on device forever.
  final Map<String, CatalogModelSource> _resolved = {};

  Future<CatalogModelSource> resolve(RoomCatalogItem item) async {
    final bundled = !kGeneratedCatalogIcons.contains(item.iconName) &&
        ArFurnitureLibrary.hasModelFor(item.iconName);
    final key = bundled
        ? 'bundled:${ArFurnitureLibrary.forIconName(item.iconName).modelFile}'
        : 'generated:${_cacheKey(item)}';
    final memo = _resolved[key];
    if (memo != null) return memo;
    final dir = await _ensureCacheDir();
    final String name;
    final Uint8List bytes;
    if (bundled) {
      final modelFile = ArFurnitureLibrary.forIconName(item.iconName).modelFile;
      name = 'bundled_${_sanitize(modelFile.replaceAll('.glb', ''))}';
      final data = await rootBundle.load('assets/models/$modelFile');
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } else {
      name = _cacheKey(item);
      bytes = generateFurnitureGlb(
        category: item.category,
        name: item.name,
        widthM: item.defaultWidth / 100,
        heightM: item.heightCm / 100,
        depthM: item.defaultHeight / 100,
      );
    }
    final file = File('${dir.path}${Platform.pathSeparator}$name.glb');
    await file.writeAsBytes(bytes, flush: true);
    final src = CatalogModelSource.file(file, isBundled: bundled);
    _resolved[key] = src;
    return src;
  }

  Future<Directory> _ensureCacheDir() async {
    final root = await _cacheRootProvider();
    final dir = Directory('${root.path}${Platform.pathSeparator}$cacheDirName');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static String _cacheKey(RoomCatalogItem item) {
    final dims = '${item.defaultWidth}x${item.heightCm}x${item.defaultHeight}';
    return 'catalog_${_sanitize(item.iconName)}_${_fnv1a(dims)}';
  }

  static String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  static String _fnv1a(String text) {
    var h = 0x811C9DC5;
    for (final c in text.toLowerCase().codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }
}
