import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/catalog_model_resolver.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/planner_scene_bridge.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/scene3d_controller.dart';
import 'package:interior_design_recommendation/features/customer/scanner/presentation/screens/room_scanner_screen.dart';
import 'package:interior_design_recommendation/features/customer/walkthrough/data/showroom_designs.dart';
import 'package:interior_design_recommendation/features/customer/walkthrough/data/showroom_furnishing.dart';
import 'package:interior_design_recommendation/models/product.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

const _supplier = Supplier(
    id: 's', name: 'Seller', phone: '', address: '', email: '');

Product product({
  String id = 'p1',
  String name = 'Sofa Bed',
  String category = 'Sofa',
  String status = 'ready',
  String url = 'https://cdn.example.com/sofa-bed.glb',
  ProductDimensions? dims =
      const ProductDimensions(widthM: 2.1, heightM: 0.85, depthM: 0.95),
}) =>
    Product(
      id: id,
      name: name,
      price: 1299,
      stock: 3,
      image: 'https://cdn.example.com/sofa-bed.jpg',
      description: '',
      designStyle: 'Modern',
      category: category,
      supplier: _supplier,
      dimensions: dims,
      ar3d: Ar3dInfo(status: status, url: url),
    );

Future<Uint8List> bundled(String file) async {
  final data = await rootBundle.load('assets/models/$file');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('marketplace product → plan piece', () {
    test('seller width × DEPTH on the floor, seller height in 3D, own GLB',
        () {
      final f = placementForProduct(product(), id: 'x');
      expect(f.width, closeTo(210, 1e-9));
      expect(f.height, closeTo(95, 1e-9),
          reason: 'plan depth comes from depthM, not the vertical height');
      expect(f.heightCm, closeTo(85, 1e-9));
      expect(f.iconName, 'sofa');
      expect(f.productId, 'p1');
      expect(f.modelUrl, 'https://cdn.example.com/sofa-bed.glb');
      expect(plannerHeightMOf(f), closeTo(0.85, 1e-9));
    });

    test('only ready models with a complete seller size qualify', () {
      expect(productHasReady3d(product()), isTrue);
      expect(productHasReady3d(product(status: 'generating')), isFalse);
      expect(productHasReady3d(product(status: 'failed', url: '')), isFalse);
      expect(
          productHasReady3d(product(
              dims: const ProductDimensions(widthM: 2, heightM: 0.8))),
          isFalse);
      expect(placementForProduct(product(status: 'generating'), id: 'x')
          .modelUrl, isNull);
    });

    test('new placement fields round-trip and stay out of legacy JSON', () {
      final f = placementForProduct(product(), id: 'x');
      final back = FurniturePlacement.fromJson(f.toJson());
      expect(back.productId, f.productId);
      expect(back.modelUrl, f.modelUrl);
      expect(back.heightCm, f.heightCm);
      expect(back.imageUrl, f.imageUrl);
      const legacy = FurniturePlacement(
          id: 'l', name: 'Sofa', iconName: 'sofa', x: 0, y: 0, width: 1, height: 1);
      expect(legacy.toJson().keys,
          isNot(anyOf(contains('modelUrl'), contains('productId'))));
    });
  });

  group('showroom furnishing', () {
    test('a matching marketplace GLB replaces the sofa; footprint kept', () {
      final room = showroomRooms.firstWhere((r) => r.name == 'Modern Living Room');
      final sofa = room.design.furniture.firstWhere((f) => f.iconName == 'sofa');
      expect(sofa.modelUrl, 'assets/models/tuxedo_sofa.glb',
          reason: 'bundled variant is the default');
      final furnished = furnishWithMarketplace(room.design, [product()]);
      final s = furnished.furniture.firstWhere((f) => f.id == sofa.id);
      expect(s.modelUrl, 'https://cdn.example.com/sofa-bed.glb');
      expect(s.name, 'Sofa Bed');
      expect(s.x, sofa.x);
      expect(s.width, sofa.width);
      expect(s.height, sofa.height);
      final lamp = furnished.furniture.firstWhere((f) => f.iconName == 'floor_lamp');
      expect(lamp.modelUrl, isNull, reason: 'no lamp product — catalog model');
    });

    test('no ready products leaves the curated design untouched', () {
      final d = showroomRooms.first.design;
      expect(identical(furnishWithMarketplace(d, const []), d), isTrue);
      expect(
          identical(
              furnishWithMarketplace(d, [product(status: 'generating')]), d),
          isTrue);
    });
  });

  group('model resolution', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('market3d'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('a bundled variant path materializes as a bundled source', () async {
      final r = CatalogModelResolver(cacheRootProvider: () async => tmp);
      final src = await r.resolveModelRef('assets/models/tuxedo_sofa.glb');
      expect(src, isNotNull);
      expect(src!.isBundled, isTrue);
      expect(src.file!.existsSync(), isTrue);
    });

    test('a marketplace GLB downloads once and is reused from cache',
        () async {
      final glb = await bundled('three_seater_sofa.glb');
      var hits = 0;
      final client = MockClient((req) async {
        hits++;
        return http.Response.bytes(glb, 200);
      });
      final url = 'https://cdn.example.com/sofa-bed.glb';
      final a = CatalogModelResolver(
          cacheRootProvider: () async => tmp, httpClient: client);
      expect(await a.resolveModelRef(url), isNotNull);
      final b = CatalogModelResolver(
          cacheRootProvider: () async => tmp, httpClient: client);
      expect(await b.resolveModelRef(url), isNotNull);
      expect(hits, 1);
    });

    test('a corrupt or failed download falls back (null), never crashes',
        () async {
      final r = CatalogModelResolver(
          cacheRootProvider: () async => tmp,
          httpClient: MockClient(
              (_) async => http.Response.bytes([1, 2, 3, 4], 200)));
      expect(await r.resolveModelRef('https://x.example/bad.glb'), isNull);
      final r404 = CatalogModelResolver(
          cacheRootProvider: () async => tmp,
          httpClient: MockClient((_) async => http.Response('', 404)));
      expect(await r404.resolveModelRef('https://x.example/gone.glb'), isNull);
    });

    test('the 3D scene loads the piece\'s own GLB', () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('scene3d_88');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async {
        calls.add(c);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final bridge = PlannerSceneBridge(
          controller: Scene3DController(),
          cacheRootProvider: () async => tmp);
      bridge.controller.bindTo(88);
      await bridge.syncFurniture([
        const FurniturePlacement(
          id: 's1',
          name: 'Sofa',
          iconName: 'sofa',
          x: 0,
          y: 0,
          width: 180,
          height: 90,
          modelUrl: 'assets/models/tuxedo_sofa.glb',
        ),
      ]);
      final add = calls.firstWhere((c) => c.method == 'addModel');
      expect((add.arguments as Map)['source'] as String,
          contains('bundled_tuxedo_sofa'));
    });
  });

  test('a downloading marketplace GLB shows the catalog stand-in, then '
      'swaps to the real model', () async {
    final tmp = Directory.systemTemp.createTempSync('swap3d');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final calls = <MethodCall>[];
    const channel = MethodChannel('scene3d_99');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
      calls.add(c);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final glb = await bundled('three_seater_sofa.glb');
    final gate = Completer<void>();
    final resolver = CatalogModelResolver(
      cacheRootProvider: () async => tmp,
      httpClient: MockClient((_) async {
        await gate.future;
        return http.Response.bytes(glb, 200);
      }),
    );
    final bridge = PlannerSceneBridge(
        controller: Scene3DController(),
        catalogResolver: resolver,
        cacheRootProvider: () async => tmp);
    bridge.controller.bindTo(99);
    await bridge.syncFurniture([placementForProduct(product(), id: 'm1')]);
    String lastSource() => (calls.lastWhere((c) => c.method == 'addModel')
        .arguments as Map)['source'] as String;
    expect(lastSource(), isNot(contains('market_')),
        reason: 'stand-in while the GLB downloads');
    gate.complete();
    for (var i = 0; i < 50 && !lastSource().contains('market_'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(lastSource(), contains('market_'));
  });

  group('planner marketplace tab', () {
    Future<void> pumpPlanner(WidgetTester tester, List<Product> market) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [marketplace3dProductsProvider.overrideWithValue(market)],
        child: MaterialApp(
          home: RoomScannerScreen(
            existingDesign: RoomDesign(
              id: 'd1',
              name: 'Test Room',
              roomType: 'living_room',
              widthCm: 400,
              heightCm: 500,
              furniture: const [],
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
              userId: 'u1',
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('ready products appear as catalogue tiles under Marketplace',
        (tester) async {
      await pumpPlanner(tester, [product()]);
      expect(find.text('Marketplace'), findsOneWidget);
      expect(find.byKey(const ValueKey('catalog-product-p1')), findsOneWidget);
    });

    testWidgets('no ready products → no Marketplace tab', (tester) async {
      await pumpPlanner(tester, const []);
      expect(find.text('Marketplace'), findsNothing);
    });

    testWidgets('placing a product keeps its id, size and GLB', (tester) async {
      await pumpPlanner(tester, [product()]);
      final state = tester.state(find.byType(RoomScannerScreen)) as dynamic;
      state.debugAddFromProduct(product());
      await tester.pump();
      final items = (state.debugFurniture as List).cast<FurniturePlacement>();
      expect(items, hasLength(1));
      expect(items.single.productId, 'p1');
      expect(items.single.modelUrl, 'https://cdn.example.com/sofa-bed.glb');
      expect({items.single.width, items.single.height}, {210.0, 95.0});
    });
  });
}
