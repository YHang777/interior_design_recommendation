// Unit tests for the pure, headless pieces of the AR viewer's product mode:
// the catalog-entry model (ArProductEntry) and the bundled-catalog fallback
// (fallbackFor). No Flutter widgets, no Firebase, no real filesystem I/O.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/ar/data/ar_product_entry.dart';
import 'package:interior_design_recommendation/features/ar/data/furniture_model_library.dart';
import 'package:interior_design_recommendation/models/product.dart';

const _supplier = Supplier(
  id: 's1',
  name: 'Seller',
  phone: '',
  address: '',
  email: '',
);

Product _product({
  String id = 'p1',
  String name = 'Oak Armchair',
  String category = 'Furniture',
  ProductDimensions? dimensions,
  Ar3dInfo? ar3d,
}) {
  return Product(
    id: id,
    name: name,
    price: 100,
    stock: 5,
    image: '',
    description: '',
    designStyle: 'Modern',
    category: category,
    supplier: _supplier,
    dimensions: dimensions,
    ar3d: ar3d,
  );
}

const _dims = ProductDimensions(widthM: 1.0, heightM: 1.5, depthM: 0.6);

void main() {
  group('ArProductEntry dimensions', () {
    test('maxDimM is the largest of width/height/depth', () {
      final entry = ArProductEntry(product: _product(dimensions: _dims));
      expect(entry.maxDimM, 1.5);
      expect(entry.hasTrueDimensions, isTrue);

      final tall = _product(
          dimensions: const ProductDimensions(
              widthM: 2.4, heightM: 0.8, depthM: 1.9));
      expect(ArProductEntry(product: tall).maxDimM, 2.4);
    });

    test('maxDimM is null without complete dimensions', () {
      expect(
        ArProductEntry(product: _product(dimensions: null)).maxDimM,
        isNull,
      );
      expect(
        ArProductEntry(
                product: _product(
                    dimensions: const ProductDimensions(widthM: 2.0)))
            .maxDimM,
        isNull,
        reason: 'height/depth are 0, so dimensions are incomplete',
      );
    });

    test('scaleToMeters equals maxDimM when dimensions are complete', () {
      // The AR plugin normalizes the model's max extent to scale.x meters —
      // passing max(W,H,D) renders our meter-authored GLB at true size.
      expect(
        ArProductEntry(product: _product(dimensions: _dims)).scaleToMeters,
        1.5,
      );
    });

    test('scaleToMeters falls back to 1.0 without dimensions', () {
      expect(
        ArProductEntry(product: _product(dimensions: null)).scaleToMeters,
        1.0,
      );
    });

    test('dimsLabel mirrors the product dimension label', () {
      final entry = ArProductEntry(product: _product(dimensions: _dims));
      expect(entry.dimsLabel, 'W 1.0 × H 1.5 × D 0.6 m');
    });

    test('dimsLabel is empty when the product has no dimensions', () {
      expect(
        ArProductEntry(product: _product(dimensions: null)).dimsLabel,
        '',
      );
    });
  });

  group('ArProductEntry catalog slot', () {
    test('name is the product name', () {
      expect(
        ArProductEntry(product: _product(name: 'Velvet Sofa')).name,
        'Velvet Sofa',
      );
    });

    test('badgeText is AI for Tripo models, Auto otherwise', () {
      const tripo =
          Ar3dInfo(status: 'ready', source: 'tripo', url: 'https://x.glb');
      const procedural =
          Ar3dInfo(status: 'ready', source: 'procedural', url: '');
      expect(
        ArProductEntry(product: _product(ar3d: tripo)).badgeText,
        'AI',
      );
      expect(
        ArProductEntry(product: _product(ar3d: procedural)).badgeText,
        'Auto',
      );
      // No ar3d record → never requested → procedural 'Auto'.
      expect(
        ArProductEntry(product: _product()).badgeText,
        'Auto',
      );
    });

    test('isResolved reflects whether a GLB file exists', () {
      expect(
        ArProductEntry(product: _product()).isResolved,
        isFalse,
      );
      expect(
        ArProductEntry(product: _product(dimensions: _dims)).isResolved,
        isFalse,
        reason: 'dims alone do not mean a file is on disk',
      );
      expect(
        ArProductEntry(
          product: _product(dimensions: _dims),
          resolvedFile: File('/cache/ar_models/p1.glb'),
        ).isResolved,
        isTrue,
      );
    });
  });

  group('fallbackFor', () {
    test('maps a product category onto the bundled catalog model', () {
      final fallback = fallbackFor(_product(category: 'Furniture'));
      expect(fallback, isNotNull);
      final expected = ArFurnitureLibrary.forCategory('Furniture');
      expect(fallback!.modelFile, expected.modelFile);
      expect(fallback.name, expected.name);
      expect(fallback.widthMeters, expected.widthMeters);
    });

    test('lowercases like ArFurnitureLibrary lookups', () {
      expect(
        fallbackFor(_product(category: 'LIGHTING'))!.modelFile,
        ArFurnitureLibrary.forCategory('lighting').modelFile,
      );
    });

    test('unknown categories still yield the library placeholder', () {
      final fallback = fallbackFor(_product(category: 'paint'));
      expect(fallback, isNotNull);
      expect(
        fallback!.modelFile,
        ArFurnitureLibrary.forCategory('paint').modelFile,
      );
    });

    test('returns null only when the product has no category', () {
      expect(fallbackFor(_product(category: '')), isNull);
      expect(fallbackFor(_product(category: '   ')), isNull);
    });
  });
}
