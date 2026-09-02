// Tests for the procedural path of ModelGlbResolver (no network, no
// Firebase — the cache directory is injected, so these run headless).
//
// The download path (ar3d ready + http url) is deliberately NOT tested here:
// it needs the network + a storage-backed fixture. Its rescale logic is
// covered by glb_rescaler_test.dart; the tripo flow by manual device tests.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/ar/data/glb_bounds.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/services/model_generation/model_glb_resolver.dart';

const _supplier = Supplier(
  id: 'supplier-test-1',
  name: 'Test Store',
  phone: '',
  address: '',
  email: '',
);

Product productWith({
  required String id,
  ProductDimensions? dimensions,
  Ar3dInfo? ar3d,
}) {
  return Product(
    id: id,
    name: 'Dining Table',
    price: 100,
    stock: 5,
    image: '',
    description: 'A test product with complete dimensions.',
    designStyle: 'Modern',
    category: 'Furniture',
    supplier: _supplier,
    supplierId: _supplier.id,
    dimensions: dimensions,
    ar3d: ar3d,
  );
}

void expectNear(double actual, double expected, double tolerance,
    [String? reason]) {
  expect((actual - expected).abs(), lessThanOrEqualTo(tolerance),
      reason: reason ?? 'expected ≈ $expected, got $actual');
}

/// Cached GLB files under the injected cache root (the resolver stores them
/// in an `ar_models/` subfolder).
List<File> cachedGlbs(Directory root) {
  final cacheDir =
      Directory('${root.path}${Platform.pathSeparator}${ModelGlbResolver.cacheDirName}');
  if (!cacheDir.existsSync()) return const [];
  return cacheDir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.glb')).toList();
}

void main() {
  late Directory tempRoot;
  late ModelGlbResolver resolver;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('ar_models_test_');
    resolver = ModelGlbResolver(cacheRootProvider: () async => tempRoot);
  });

  tearDown(() {
    resolver.dispose();
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort cleanup.
    }
  });

  group('ModelGlbResolver.resolveProductGlb', () {
    test('complete dims + ar3d none → procedural file with matching bounds',
        () async {
      final product = productWith(
        id: 'prod-a',
        dimensions: const ProductDimensions(
            widthM: 1.0, heightM: 0.75, depthM: 0.6),
      );
      final resolved = await resolver.resolveProductGlb(product);

      expect(resolved.procedural, isTrue,
          reason: 'ar3d none must resolve through the generator');
      expect(resolved.file.existsSync(), isTrue);
      expect(resolved.file.path, startsWith(tempRoot.path),
          reason: 'cached under the injected cache root');

      final bytes = resolved.file.readAsBytesSync();
      final bounds = GlbBounds.fromGlbBytes(bytes);
      expectNear(bounds.widthM, 1.0, 0.02, 'width');
      expectNear(bounds.heightM, 0.75, 0.02, 'height');
      expectNear(bounds.depthM, 0.6, 0.02, 'depth');
      expectNear(bounds.minY, 0.0, 1e-6, 'grounded');
    });

    test('second resolve reuses the cached file (same path, not rewritten)',
        () async {
      final product = productWith(
        id: 'prod-b',
        dimensions: const ProductDimensions(
            widthM: 0.8, heightM: 1.2, depthM: 0.5),
      );
      final first = await resolver.resolveProductGlb(product);
      final statBefore = first.file.statSync();

      final second = await resolver.resolveProductGlb(product);

      expect(second.file.path, first.file.path,
          reason: 'cache key must be stable → same file path');
      expect(second.procedural, isTrue);
      final statAfter = second.file.statSync();
      expect(statAfter.modified, statBefore.modified,
          reason: 'file must not be rewritten on a cache hit');
      expect(statAfter.size, statBefore.size);

      // Exactly one cached model file exists for this product.
      expect(cachedGlbs(tempRoot).length, 1,
          reason: 'prune keeps one model per product');
    });

    test('ar3d failed still resolves procedurally when dims are complete',
        () async {
      final product = productWith(
        id: 'prod-c',
        dimensions: const ProductDimensions(
            widthM: 0.6, heightM: 0.9, depthM: 0.6),
        ar3d: const Ar3dInfo(
            status: 'failed', error: 'Tripo generation failed'),
      );
      final resolved = await resolver.resolveProductGlb(product);
      expect(resolved.procedural, isTrue);
      final bounds =
          GlbBounds.fromGlbBytes(resolved.file.readAsBytesSync());
      expectNear(bounds.heightM, 0.9, 0.02, 'height');
    });

    test('dimension edit produces a NEW cache file and prunes the old one',
        () async {
      final small = productWith(
        id: 'prod-d',
        dimensions: const ProductDimensions(
            widthM: 0.8, heightM: 0.7, depthM: 0.5),
      );
      final first = await resolver.resolveProductGlb(small);

      final big = productWith(
        id: 'prod-d',
        dimensions: const ProductDimensions(
            widthM: 1.4, heightM: 1.0, depthM: 0.8),
      );
      final second = await resolver.resolveProductGlb(big);

      expect(second.file.path, isNot(first.file.path),
          reason: 'dims live in the cache key');
      expect(cachedGlbs(tempRoot).length, 1,
          reason: 'old dims file pruned');
      final bounds =
          GlbBounds.fromGlbBytes(second.file.readAsBytesSync());
      expectNear(bounds.widthM, 1.4, 0.02, 'new width');
      expectNear(bounds.heightM, 1.0, 0.02, 'new height');
    });

    test('incomplete dims + ar3d none → No3dAvailableException', () async {
      final product = productWith(
        id: 'prod-e',
        dimensions: const ProductDimensions(widthM: 0, heightM: 0, depthM: 0),
      );
      await expectLater(
        resolver.resolveProductGlb(product),
        throwsA(isA<No3dAvailableException>()),
      );
    });

    test('null dims + ar3d none → No3dAvailableException', () async {
      final product = productWith(id: 'prod-f');
      await expectLater(
        resolver.resolveProductGlb(product),
        throwsA(isA<No3dAvailableException>()),
      );
    });

    test('empty product id → No3dAvailableException', () async {
      final product = productWith(
        id: '',
        dimensions: const ProductDimensions(
            widthM: 1.0, heightM: 0.75, depthM: 0.6),
      );
      await expectLater(
        resolver.resolveProductGlb(product),
        throwsA(isA<No3dAvailableException>()),
      );
    });
  });
}
