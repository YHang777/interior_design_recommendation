// Verifies the AR furniture library stays consistent with the bundled
// model files in assets/models/ (tests run from the project root).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/ar/data/furniture_model_library.dart';

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
    // The catalog must actually reference bundled models (not be empty).
    expect(files, isNotEmpty);
  });

  test('catalog lookups (icon/category) resolve to existing model files', () {
    final items = <ArFurnitureItem>{
      ArFurnitureLibrary.forIconName('sofa'),
      ArFurnitureLibrary.forIconName('bookshelf'),
      ArFurnitureLibrary.forIconName('floor_lamp'),
      ArFurnitureLibrary.forIconName('unknown-thing'),
      ArFurnitureLibrary.forCategory('lighting'),
      ArFurnitureLibrary.forCategory('textiles'),
      ArFurnitureLibrary.forCategory('nothing'),
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
}
