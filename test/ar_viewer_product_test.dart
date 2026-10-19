import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/ar_product_entry.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_generator.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_rescaler.dart';
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

File _resolvedGlb(ProductDimensions dims) {
  final bytes = rescaleGlbToDimensions(
    generateWallGlb(
        finish: const WallFinish(
            type: WallFinishType.paint, colorArgb: 0xFFE9E4DA)),
    targetWidthM: dims.widthM,
    targetHeightM: dims.heightM,
    targetDepthM: dims.depthM,
  );
  final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'ar_entry_test_${dims.widthM}_${dims.heightM}_${dims.depthM}.glb');
  file.writeAsBytesSync(bytes, flush: true);
  return file;
}

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

  group('scaleToMeters (strict — never a guessed scale)', () {
    test('equals the resolved GLB’s max extent (the seller’s size)', () {
      final file = _resolvedGlb(_dims);
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      final entry = ArProductEntry(
        product: _product(dimensions: _dims),
        resolvedFile: file,
      );
      expect(entry.scaleToMeters, 1.5,
          reason: 'max(1.0, 1.5, 0.6) of the resolved geometry');
    });

    test('throws StateError when there is no resolved file', () {
      final entry = ArProductEntry(product: _product(dimensions: _dims));
      expect(entry.isResolved, isFalse);
      expect(
        () => entry.scaleToMeters,
        throwsStateError,
        reason: 'an unresolved product must never be placed at a guessed '
            'scale',
      );
    });

    test('throws StateError when the file is not a GLB', () {
      final file = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'ar_entry_garbage.glb')
        ..writeAsStringSync('not a glb');
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      expect(
        () => ArProductEntry(
          product: _product(dimensions: _dims),
          resolvedFile: file,
        ).scaleToMeters,
        throwsStateError,
      );
    });

    test('the parsed scale is memoized', () {
      final file = _resolvedGlb(_dims);
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      final entry = ArProductEntry(
        product: _product(dimensions: _dims),
        resolvedFile: file,
      );
      expect(entry.scaleToMeters, entry.scaleToMeters);
    });
  });

  group('ArProductEntry catalog slot', () {
    test('name is the product name', () {
      expect(
        ArProductEntry(product: _product(name: 'Velvet Sofa')).name,
        'Velvet Sofa',
      );
    });

    test('badgeText is always AI (Tripo is the only model source)', () {
      const ready =
          Ar3dInfo(status: 'ready', source: 'tripo', url: 'https://x.glb');
      expect(
        ArProductEntry(product: _product(ar3d: ready)).badgeText,
        'AI',
      );
      expect(
        ArProductEntry(product: _product()).badgeText,
        'AI',
      );
    });

    test('isResolved reflects whether a GLB file exists', () {
      expect(
        ArProductEntry(product: _product()).isResolved,
        isFalse,
      );
      expect(
        ArProductEntry(
          product: _product(dimensions: _dims),
          resolvedFile: File('/cache/ar_models/p1.glb'),
        ).isResolved,
        isTrue,
      );
    });

    test('productError is carried verbatim and flags the slot as failed',
        () {
      const reason = "This product's size hasn't been set yet, so it "
          "can't be shown in AR.";
      final entry = ArProductEntry(
        product: _product(dimensions: _dims),
        productError: reason,
      );
      expect(entry.hasError, isTrue);
      expect(entry.productError, reason);
      expect(entry.isResolved, isFalse,
          reason: 'a failed slot is never placeable');
    });

    test('a clean entry has no error', () {
      final entry = ArProductEntry(product: _product());
      expect(entry.hasError, isFalse);
      expect(entry.productError, isNull);
    });
  });

  // ─── NodeType.fileSystemAppFolderGLB URI form (SceneView contract) ───
  group('product GLB URI form', () {
    test('Uri.file(...).toString() carries the file scheme SceneView needs',
        () {
      final path =
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'ar_uri_form${Platform.pathSeparator}p1.glb';
      final uri = Uri.file(path).toString();

      expect(uri, startsWith('file://'));
      final parsed = Uri.parse(uri);
      expect(parsed.scheme, 'file',
          reason: 'FileLoader only reads from disk on the "file" scheme; '
              'anything else is treated as an Android asset path');
      expect(parsed.toFilePath(), path,
          reason: 'the path component must round-trip so File(uri.path) '
              'opens exactly the resolved GLB');
    });

    test('a bare filesystem path carries NO file scheme (would hit assets)',
        () {
      expect(Uri.parse('/data/user/0/app_flutter/ar_models/p1.glb').scheme,
          isNot('file'),
          reason: 'documents why _buildNode must NOT pass a raw path');
    });
  });
}
