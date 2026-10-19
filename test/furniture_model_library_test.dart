import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/furniture_model_library.dart';

void main() {
  test('every catalog model file exists under assets/models/', () {
    final files = <String>{};
    for (final item in ArFurnitureLibrary.all) {
      files.add(item.modelFile);
      expect(
        File('assets/models/${item.modelFile}').existsSync(),
        isTrue,
        reason: '${item.modelFile} is referenced by ArFurnitureLibrary but '
            'missing from assets/models/',
      );
    }
    expect(files, isNotEmpty);
  });

  test('catalog lookups (icon-based) resolve to existing model files', () {
    final items = <ArFurnitureItem>{
      ArFurnitureLibrary.forIconName('sofa'),
      ArFurnitureLibrary.forIconName('bookshelf'),
      ArFurnitureLibrary.forIconName('floor_lamp'),
      ArFurnitureLibrary.forIconName('unknown-thing'),
      ArFurnitureLibrary.forIconName('plant'),
      ArFurnitureLibrary.forIconName('rug'),
      ...ArFurnitureLibrary.fromIconNames(
          ['sofa', 'armchair', 'coffee_table', 'dining_table', 'bed']),
    };
    for (final item in items) {
      expect(
        File('assets/models/${item.modelFile}').existsSync(),
        isTrue,
        reason: '${item.modelFile} (from lookup) missing in assets/models/',
      );
    }
  });

  // ─── Regression guards for the AR plugin's asset-key contract ───

  test('every ArFurnitureItem.uri is the full pubspec asset key on disk',
      () {
    final items = <ArFurnitureItem>{
      ...ArFurnitureLibrary.all,
      ArFurnitureLibrary.forIconName(null),
      ArFurnitureLibrary.forIconName('unknown-thing'),
      ArFurnitureLibrary.forIconName('plant'),
      ArFurnitureLibrary.forIconName('rug'),
      ArFurnitureLibrary.forIconName('tv_stand'),
      ArFurnitureLibrary.fromIconNames(['cabinet', 'rug', 'tv_stand']).first,
    };
    expect(items, isNotEmpty);
    for (final item in items) {
      expect(
        item.uri,
        'assets/models/${item.modelFile}',
        reason: '${item.name}: uri must be the exact pubspec-relative asset '
            'key that getLookupKeyForAsset receives',
      );
      expect(
        item.uri,
        startsWith('assets/'),
        reason: '${item.name}: regression guard — the assets/ prefix is '
            'required; without it the plugin cannot resolve the model',
      );
      expect(
        File(item.uri).existsSync(),
        isTrue,
        reason: '${item.uri} must exist on disk at the same path the asset '
            'bundle uses',
      );
    }
  });

  test('pubspec.yaml declares assets/models/ (keeps the asset keys valid)',
      () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      contains('- assets/models/'),
      reason: 'ArFurnitureItem.uri keys start with assets/models/, so that '
          'directory must stay registered under flutter: assets:',
    );
  });

  test('every modelFile referenced anywhere in the library exists on disk',
      () {
    final source = File(
            'lib/features/customer/ar/data/furniture_model_library.dart')
        .readAsStringSync();
    final modelFiles = RegExp(r"modelFile:\s*'([^']+)'")
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();
    expect(modelFiles, isNotEmpty,
        reason: 'regex should find the modelFile literals in the source');
    for (final file in modelFiles) {
      expect(
        File('assets/models/$file').existsSync(),
        isTrue,
        reason: '$file is referenced by ArFurnitureLibrary but missing from '
            'assets/models/',
      );
    }
  });
}
