// Tests for ModelGlbResolver — the app's ONE product-model path: a ready
// Tripo download, rescaled to the SELLER's declared dimensions and cached.
// There is no procedural generation and no bundled-catalog fallback, so
// every failure must surface a specific No3dAvailableException reason
// (never silently substitute another model).
//
// Network is faked with an injected http.Client (package:http/testing);
// the cache directory is injected too — these tests run fully headless.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_bounds.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_generator.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_rescaler.dart';
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
  String image = '',
  String category = 'Furniture',
}) {
  return Product(
    id: id,
    name: 'Side Table',
    price: 100,
    stock: 5,
    image: image,
    description: 'A test product.',
    designStyle: 'Modern',
    category: category,
    supplier: _supplier,
    supplierId: _supplier.id,
    dimensions: dimensions,
    ar3d: ar3d,
  );
}

/// A "Tripo-like" mesh at a known arbitrary scale: 0.6 × 0.7 × 0.4 m —
/// the 0.70 m height of the spec's 0.70 m → 0.50 m example.
Uint8List meshAt070Height() => rescaleGlbToDimensions(
      generateWallGlb(
          finish: const WallFinish(
              type: WallFinishType.paint, colorArgb: 0xFFE9E4DA)),
      targetWidthM: 0.6,
      targetHeightM: 0.7,
      targetDepthM: 0.4,
    );

const _readyUrl = 'https://cdn.example.tripo.test/models/p1.glb';

Ar3dInfo readyAr3d({String url = _readyUrl}) => Ar3dInfo(
      status: 'ready',
      source: 'tripo',
      url: url,
      generatedAt: DateTime.utc(2026, 1, 1, 12),
    );

void expectNear(double actual, double expected, double tolerance,
    [String? reason]) {
  expect((actual - expected).abs(), lessThanOrEqualTo(tolerance),
      reason: reason ?? 'expected ≈ $expected, got $actual');
}

/// Cached GLB files under the injected cache root (the resolver stores them
/// in an `ar_models/` subfolder).
List<File> cachedGlbs(Directory root) {
  final cacheDir = Directory(
      '${root.path}${Platform.pathSeparator}${ModelGlbResolver.cacheDirName}');
  if (!cacheDir.existsSync()) return const [];
  return cacheDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.glb'))
      .toList();
}

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('ar_models_test_');
  });

  tearDown(() {
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort cleanup.
    }
  });

  ModelGlbResolver resolverWith(MockClient http) => ModelGlbResolver(
        cacheRootProvider: () async => tempRoot,
        httpClient: http,
      );

  group('hard-stop preconditions (specific reasons, never a substitute)',
      () {
    test('empty product id → No3dAvailableException', () async {
      final resolver = resolverWith(MockClient((_) async => throw StateError(
          'no request may happen for an empty product id')));
      addTearDown(resolver.dispose);
      await expectLater(
        resolver.resolveProductGlb(productWith(
          id: '',
          dimensions: const ProductDimensions(
              widthM: 1.0, heightM: 0.75, depthM: 0.6),
          ar3d: readyAr3d(),
        )),
        throwsA(isA<No3dAvailableException>().having(
            (e) => e.reason, 'reason', contains('id is empty'))),
      );
    });

    test('no seller dimensions at all → refuses with the dimensions '
        'message', () async {
      final resolver = resolverWith(MockClient(
          (_) async => throw StateError('no request may happen without dims')));
      addTearDown(resolver.dispose);
      await expectLater(
        resolver.resolveProductGlb(productWith(
          id: 'prod-nodims',
          dimensions: const ProductDimensions(widthM: 0, heightM: 0, depthM: 0),
          ar3d: readyAr3d(),
        )),
        throwsA(isA<No3dAvailableException>().having(
            (e) => e.reason,
            'reason',
            allOf(contains('Width/Height/Depth'), contains('dimensions')))),
      );
    });

    test('null dims → same refusal', () async {
      final resolver = resolverWith(MockClient(
          (_) async => throw StateError('no request may happen without dims')));
      addTearDown(resolver.dispose);
      await expectLater(
        resolver.resolveProductGlb(
            productWith(id: 'prod-nulldims', ar3d: readyAr3d())),
        throwsA(isA<No3dAvailableException>().having(
            (e) => e.reason, 'reason', contains('Width/Height/Depth'))),
      );
    });

    test('ar3d none → tells the seller to generate first', () async {
      final resolver = resolverWith(
          MockClient((_) async => throw StateError('nothing to download')));
      addTearDown(resolver.dispose);
      await expectLater(
        resolver.resolveProductGlb(productWith(
          id: 'prod-none',
          dimensions: const ProductDimensions(
              widthM: 1.0, heightM: 0.75, depthM: 0.6),
        )),
        throwsA(isA<No3dAvailableException>().having(
            (e) => e.reason,
            'reason',
            contains('No 3D model has been generated'))),
      );
    });

    test('generating → the "generating" sentinel (progress, not an error)',
        () async {
      final resolver = resolverWith(
          MockClient((_) async => throw StateError('nothing to download')));
      addTearDown(resolver.dispose);
      await expectLater(
        resolver.resolveProductGlb(productWith(
          id: 'prod-gen',
          dimensions: const ProductDimensions(
              widthM: 1.0, heightM: 0.75, depthM: 0.6),
          ar3d: const Ar3dInfo(
              status: 'generating', taskId: 'task_123', attempts: 1),
        )),
        throwsA(isA<No3dAvailableException>()
            .having((e) => e.reason, 'reason', 'generating')),
      );
    });

    test('failed → the stored reason + Retry (no new charge)', () async {
      final resolver = resolverWith(
          MockClient((_) async => throw StateError('nothing to download')));
      addTearDown(resolver.dispose);
      await expectLater(
        resolver.resolveProductGlb(productWith(
          id: 'prod-failed',
          dimensions: const ProductDimensions(
              widthM: 1.0, heightM: 0.75, depthM: 0.6),
          ar3d: const Ar3dInfo(
              status: 'failed',
              error: 'Tripo is out of credits (HTTP 402)'),
        )),
        throwsA(isA<No3dAvailableException>().having(
            (e) => e.reason,
            'reason',
            allOf(contains('Tripo is out of credits'),
                contains('no new charge')))),
      );
    });

    test('ready without a downloadable URL → Regenerate hint', () async {
      final resolver = resolverWith(
          MockClient((_) async => throw StateError('no URL, no request')));
      addTearDown(resolver.dispose);
      await expectLater(
        resolver.resolveProductGlb(productWith(
          id: 'prod-nourl',
          dimensions: const ProductDimensions(
              widthM: 1.0, heightM: 0.75, depthM: 0.6),
          ar3d: readyAr3d(url: ''),
        )),
        throwsA(isA<No3dAvailableException>().having(
            (e) => e.reason, 'reason', contains('no downloadable model URL'))),
      );
    });
  });

  group('download + rescale to the seller’s size (single real path)', () {
    test('spec example: seller height 0.50 m, Tripo mesh 0.70 m → 0.50 m',
        () async {
      var downloads = 0;
      final resolver = resolverWith(MockClient((request) async {
        downloads++;
        expect(request.url.toString(), _readyUrl);
        return http.Response.bytes(meshAt070Height(), 200);
      }));
      addTearDown(resolver.dispose);

      final resolved = await resolver.resolveProductGlb(productWith(
        id: 'prod-5070',
        dimensions: const ProductDimensions(heightM: 0.50),
        ar3d: readyAr3d(),
      ));

      expect(downloads, 1, reason: 'exactly one download, no fallbacks');
      expect(resolved.file.existsSync(), isTrue);
      final bounds = GlbBounds.fromGlbBytes(resolved.file.readAsBytesSync());
      expectNear(bounds.heightM, 0.50, 0.005, 'seller height 0.50 m');
      // Uniform scale (5/7): proportions of the 0.6 × 0.7 × 0.4 mesh hold.
      expectNear(bounds.widthM, 0.6 * 5 / 7, 0.005, 'width scaled uniformly');
      expectNear(bounds.depthM, 0.4 * 5 / 7, 0.005, 'depth scaled uniformly');
      expectNear(bounds.minY, 0.0, 1e-6, 'grounded at y = 0');
    });

    test('all three dims → per-axis true size (mesh 0.6×0.7×0.4 → '
        '1.0×0.5×0.6)', () async {
      final resolver = resolverWith(
          MockClient((_) async => http.Response.bytes(meshAt070Height(), 200)));
      addTearDown(resolver.dispose);

      final resolved = await resolver.resolveProductGlb(productWith(
        id: 'prod-all3',
        dimensions: const ProductDimensions(
            widthM: 1.0, heightM: 0.5, depthM: 0.6),
        ar3d: readyAr3d(),
      ));

      final bounds = GlbBounds.fromGlbBytes(resolved.file.readAsBytesSync());
      expectNear(bounds.widthM, 1.0, 0.01, 'width');
      expectNear(bounds.heightM, 0.5, 0.01, 'height');
      expectNear(bounds.depthM, 0.6, 0.01, 'depth');
      expectNear(bounds.minY, 0.0, 1e-6, 'grounded');
    });

    test('second resolve is a cache hit (same path, no re-download)',
        () async {
      var downloads = 0;
      final resolver = resolverWith(MockClient((_) async {
        downloads++;
        return http.Response.bytes(meshAt070Height(), 200);
      }));
      addTearDown(resolver.dispose);

      final product = productWith(
        id: 'prod-cache',
        dimensions: const ProductDimensions(
            widthM: 1.0, heightM: 0.5, depthM: 0.6),
        ar3d: readyAr3d(),
      );
      final first = await resolver.resolveProductGlb(product);
      final statBefore = first.file.statSync();

      final second = await resolver.resolveProductGlb(product);
      expect(downloads, 1, reason: 'cache hit must not touch the network');
      expect(second.file.path, first.file.path);
      final statAfter = second.file.statSync();
      expect(statAfter.modified, statBefore.modified,
          reason: 'file must not be rewritten on a cache hit');
      expect(cachedGlbs(tempRoot).length, 1,
          reason: 'prune keeps one model per product');
    });

    test('dimension edit produces a NEW cache file and prunes the old one',
        () async {
      final resolver = resolverWith(
          MockClient((_) async => http.Response.bytes(meshAt070Height(), 200)));
      addTearDown(resolver.dispose);

      final small = productWith(
        id: 'prod-dims',
        dimensions: const ProductDimensions(
            widthM: 1.0, heightM: 0.5, depthM: 0.6),
        ar3d: readyAr3d(),
      );
      final first = await resolver.resolveProductGlb(small);

      final big = productWith(
        id: 'prod-dims',
        dimensions: const ProductDimensions(
            widthM: 1.4, heightM: 1.0, depthM: 0.8),
        ar3d: readyAr3d(),
      );
      final second = await resolver.resolveProductGlb(big);

      expect(second.file.path, isNot(first.file.path),
          reason: 'dims live in the cache key');
      expect(cachedGlbs(tempRoot).length, 1,
          reason: 'old dims file pruned');
      final bounds = GlbBounds.fromGlbBytes(second.file.readAsBytesSync());
      expectNear(bounds.widthM, 1.4, 0.01, 'new width');
      expectNear(bounds.heightM, 1.0, 0.01, 'new height');
    });

    test('new Tripo run (new generatedAt) replaces the cached download',
        () async {
      final resolver = resolverWith(
          MockClient((_) async => http.Response.bytes(meshAt070Height(), 200)));
      addTearDown(resolver.dispose);

      final before = productWith(
        id: 'prod-regen',
        dimensions: const ProductDimensions(
            widthM: 1.0, heightM: 0.5, depthM: 0.6),
        ar3d: readyAr3d(),
      );
      final first = await resolver.resolveProductGlb(before);

      final after = productWith(
        id: 'prod-regen',
        dimensions: const ProductDimensions(
            widthM: 1.0, heightM: 0.5, depthM: 0.6),
        ar3d: Ar3dInfo(
          status: 'ready',
          source: 'tripo',
          url: _readyUrl,
          generatedAt: DateTime.utc(2026, 2, 2, 12),
        ),
      );
      final second = await resolver.resolveProductGlb(after);

      expect(second.file.path, isNot(first.file.path),
          reason: 'generatedAt is part of the cache key');
      expect(cachedGlbs(tempRoot).length, 1);
    });
  });

  group('download failures are loud (no substitute model)', () {
    test('HTTP 500 → specific reason, no file written', () async {
      final resolver =
          resolverWith(MockClient((_) async => http.Response('boom', 500)));
      addTearDown(resolver.dispose);

      await expectLater(
        resolver.resolveProductGlb(productWith(
          id: 'prod-500',
          dimensions: const ProductDimensions(
              widthM: 1.0, heightM: 0.75, depthM: 0.6),
          ar3d: readyAr3d(),
        )),
        throwsA(isA<No3dAvailableException>().having(
            (e) => e.reason, 'reason', contains('HTTP 500'))),
      );
      expect(cachedGlbs(tempRoot), isEmpty,
          reason: 'a failed download must not leave a model behind');
    });

    test('empty body → specific reason', () async {
      final resolver = resolverWith(
          MockClient((_) async => http.Response.bytes(const [], 200)));
      addTearDown(resolver.dispose);

      await expectLater(
        resolver.resolveProductGlb(productWith(
          id: 'prod-empty',
          dimensions: const ProductDimensions(
              widthM: 1.0, heightM: 0.75, depthM: 0.6),
          ar3d: readyAr3d(),
        )),
        throwsA(isA<No3dAvailableException>().having(
            (e) => e.reason, 'reason', contains('empty'))),
      );
      expect(cachedGlbs(tempRoot), isEmpty);
    });

    test('non-GLB payload → parse failure surfaces, nothing cached',
        () async {
      final resolver = resolverWith(MockClient(
          (_) async => http.Response.bytes(const [1, 2, 3, 4, 5], 200)));
      addTearDown(resolver.dispose);

      await expectLater(
        resolver.resolveProductGlb(productWith(
          id: 'prod-garbage',
          dimensions: const ProductDimensions(
              widthM: 1.0, heightM: 0.75, depthM: 0.6),
          ar3d: readyAr3d(),
        )),
        throwsA(isA<No3dAvailableException>()),
      );
      expect(cachedGlbs(tempRoot), isEmpty);
    });
  });
}
