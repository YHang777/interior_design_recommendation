import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../scanner/data/furniture_catalog.dart';
import 'furniture_model_library.dart';
import 'glb_generator.dart';

class CatalogModelSource {
  const CatalogModelSource.asset(this.uri) : file = null;
  const CatalogModelSource.file(this.file) : uri = null;

  final String? uri;
  final File? file;

  String get source => uri ?? file!.path;
  String get sourceType => uri != null ? 'asset' : 'file';
}

// IconNames whose bundled GLB is a stand-in of the wrong shape — the 3D
// planner/walkthrough generates a real model at true catalog size instead.
const Set<String> kGeneratedCatalogIcons = {
  'cabinet',
  'floor_lamp',
  'plant',
  'tv_stand',
  'rug',
  'bookshelf',
};

class CatalogModelResolver {
  CatalogModelResolver({Future<Directory> Function()? cacheRootProvider})
      : _cacheRootProvider =
            cacheRootProvider ?? getApplicationDocumentsDirectory;

  static const String cacheDirName = 'catalog_models';

  final Future<Directory> Function() _cacheRootProvider;

  // Bundled pieces come back as their asset URI (the 3D views scale them to
  // catalog size); the six stand-ins are generated to a cached file at exact
  // catalog dimensions so addModel needs no further scaling.
  Future<CatalogModelSource> resolve(RoomCatalogItem item) async {
    // Bundled piece only when the library really models that shape; the six
    // stand-ins and anything unknown generate instead of borrowing the
    // fallback model's shape.
    if (!kGeneratedCatalogIcons.contains(item.iconName) &&
        ArFurnitureLibrary.hasModelFor(item.iconName)) {
      return CatalogModelSource.asset(
          ArFurnitureLibrary.forIconName(item.iconName).uri);
    }
    final dir = await _ensureCacheDir();
    final file =
        File('${dir.path}${Platform.pathSeparator}${_cacheKey(item)}.glb');
    if (file.existsSync() && file.lengthSync() > 0) {
      return CatalogModelSource.file(file);
    }
    final bytes = generateFurnitureGlb(
      category: item.category,
      name: item.name,
      widthM: item.defaultWidth / 100,
      heightM: item.heightCm / 100,
      depthM: item.defaultHeight / 100,
    );
    await file.writeAsBytes(bytes, flush: true);
    return CatalogModelSource.file(file);
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
