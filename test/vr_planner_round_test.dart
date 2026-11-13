import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_bounds.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_generator.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/camera_rig.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/furniture_catalog.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/plan_scene_math.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/planner_scene_bridge.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/room_fit.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/room_shell.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/scene3d_controller.dart';
import 'package:interior_design_recommendation/features/customer/scanner/presentation/screens/room_scanner_screen.dart';
import 'package:interior_design_recommendation/features/customer/walkthrough/presentation/walkthrough_controller.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

FurniturePlacement piece(String id,
        {double x = 0,
        double y = 0,
        double w = 100,
        double h = 50,
        String icon = 'sofa',
        double rotation = 0}) =>
    FurniturePlacement(
      id: id,
      name: id,
      iconName: icon,
      x: x,
      y: y,
      width: w,
      height: h,
      rotation: rotation,
    );

Map<String, dynamic> glbJson(Uint8List bytes) {
  final len = ByteData.sublistView(bytes, 12, 16).getUint32(0, Endian.little);
  return jsonDecode(utf8.decode(bytes.sublist(20, 20 + len)))
      as Map<String, dynamic>;
}

void main() {
  group('room-size validation', () {
    test('a piece bigger than the room either way is refused', () {
      expect(
          fitInRoom(piece('huge', w: 450, h: 480),
              roomW: 400, roomH: 500, walls: const []),
          isNull);
    });

    test('a piece that only fits turned is placed turned', () {
      final r = fitInRoom(piece('long', w: 450, h: 90),
          roomW: 400, roomH: 500, walls: const []);
      expect(r, isNotNull);
      expect(r!.rotation % 180, 90);
      expect(placementFits(r, roomW: 400, roomH: 500, walls: const []),
          isTrue);
    });

    test('a polygon room smaller than its bounding rect still refuses', () {
      // L-shape: 400×500 rect but the widest clear run is 200 cm.
      const walls = [
        Offset(0, 0),
        Offset(200, 0),
        Offset(200, 300),
        Offset(400, 300),
        Offset(400, 500),
        Offset(0, 500),
      ];
      expect(
          fitInRoom(piece('bed', w: 300, h: 300),
              roomW: 400, roomH: 500, walls: walls),
          isNull);
    });

    test('unfitPlacements names only the pieces that fit nowhere', () {
      final items = [piece('ok', w: 100, h: 50), piece('big', w: 350, h: 350)];
      final unfit =
          unfitPlacements(items, roomW: 300, roomH: 300, walls: const []);
      expect(unfit.map((f) => f.id), ['big']);
    });
  });

  group('clear-floor drops', () {
    test('a new piece never lands inside another one', () {
      final sofa = piece('sofa', x: 20, y: 15, w: 180, h: 90);
      final chair = piece('chair', x: 20, y: 15, w: 70, h: 70, icon: 'armchair');
      final placed = resolveDrop(chair,
          roomW: 400, roomH: 500, walls: const [], others: [sofa]);
      expect(footprintsOverlap(placed, sofa), isFalse);
      expect(placementFits(placed, roomW: 400, roomH: 500, walls: const []),
          isTrue);
    });

    test('a rug may sit under furniture', () {
      final sofa = piece('sofa', x: 20, y: 15, w: 180, h: 90);
      final rug = piece('rug', x: 0, y: 0, w: 240, h: 170, icon: 'rug');
      expect(isFloorCovering(rug), isTrue);
      final placed = resolveDrop(rug,
          roomW: 400, roomH: 500, walls: const [], others: [sofa]);
      expect(placed.x, 0);
      expect(placed.y, 0);
    });

    test('a full room falls back to the walls-only fit', () {
      final block = piece('block', x: 0, y: 0, w: 300, h: 300);
      final chair = piece('chair', x: 10, y: 10, w: 290, h: 290);
      final placed = resolveDrop(chair,
          roomW: 300, roomH: 300, walls: const [], others: [block]);
      expect(placementFits(placed, roomW: 300, roomH: 300, walls: const []),
          isTrue);
    });

    test('the walkthrough refuses a piece the room cannot hold', () {
      final ctl = WalkthroughController(
        design: RoomDesign(
          id: 'r',
          name: 'r',
          roomType: 'living_room',
          widthCm: 300,
          heightCm: 300,
          furniture: const [],
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          userId: 'u',
        ),
      );
      expect(ctl.ghostFits(piece('ok', w: 120, h: 60)), isTrue);
      expect(ctl.ghostFits(piece('huge', w: 350, h: 320)), isFalse);
    });
  });

  group('camera framing', () {
    test('the fitted orbit keeps every room corner (incl. wall tops) on '
        'screen for a portrait viewport', () {
      const viewport = Size(400, 700);
      final rig = OrbitRig.frameRoom(roomWCm: 400, roomHCm: 500);
      rig.distanceM = fitRoomDistanceM(
          roomWCm: 400, roomHCm: 500, fovDeg: rig.fovDeg, aspect: 400 / 700);
      final pose = rig.pose;
      for (final x in [-0.1, 4.1]) {
        for (final z in [-0.1, 5.1]) {
          for (final y in [0.0, 2.7]) {
            final p = projectWorldPoint(pose, viewport, x, y, z);
            expect(p, isNotNull);
            expect(p!.dx, inInclusiveRange(0, viewport.width),
                reason: 'corner ($x, $y, $z) off screen at $p');
            expect(p.dy, inInclusiveRange(0, viewport.height),
                reason: 'corner ($x, $y, $z) off screen at $p');
          }
        }
      }
    });

    test('portrait walkthrough widens the lens; landscape keeps 70°', () {
      final rig = FirstPersonRig();
      rig.setZoom(1, aspect: 0.5);
      expect(rig.fovDeg, greaterThan(85));
      expect(rig.fovDeg, lessThanOrEqualTo(95));
      rig.setZoom(1);
      expect(rig.fovDeg, 70);
      rig.setZoom(2, aspect: 0.5);
      expect(rig.fovDeg, lessThan(60));
    });

    test('zoom can dolly closer than before (0.8 m floor)', () {
      final rig = OrbitRig(distanceM: 1.0);
      rig.dolly(0.1);
      expect(rig.distanceM, closeTo(0.8, 1e-9));
    });
  });

  group('3D model fitting', () {
    test('scene bounds apply node transforms (Z-up bundled bed)', () {
      final bytes = File('assets/models/double_bed.glb').readAsBytesSync();
      final raw = GlbBounds.fromGlbBytes(bytes);
      final scene = GlbBounds.sceneFromGlbBytes(bytes);
      expect(raw.maxExtent, lessThan(0.1), reason: 'raw units are mm-scale');
      expect(scene.widthM, inInclusiveRange(1.0, 3.0));
      expect(scene.depthM, inInclusiveRange(1.0, 3.0));
      expect(scene.heightM, inInclusiveRange(0.4, 1.6));
    });

    test('long-axis disagreement turns only elongated pieces', () {
      expect(longAxisDisagrees(0.39, 0.80, 2.0, 0.9), isTrue);
      expect(longAxisDisagrees(2.0, 0.9, 2.0, 0.9), isFalse);
      expect(longAxisDisagrees(1.0, 1.05, 2.0, 0.9), isFalse,
          reason: 'square-ish models are never turned');
    });
  });

  group('walls while drawing', () {
    test('one corner is a post, two corners a wall run, three a ring', () {
      expect(draftWallsFor(wallsCm: const [], roomWCm: 400, roomHCm: 500),
          isEmpty);
      final post = draftWallsFor(
          wallsCm: const [Offset(50, 50)], roomWCm: 400, roomHCm: 500);
      expect(post, hasLength(1));
      expect(post.single.aCm, post.single.bCm);
      final run = draftWallsFor(
          wallsCm: const [Offset(0, 200), Offset(400, 200)],
          roomWCm: 400,
          roomHCm: 500);
      expect(run.single.aCm, const Offset(0, 200));
      expect(run.single.bCm, const Offset(400, 200));
      expect(
          draftWallsFor(
              wallsCm: const [Offset(0, 0), Offset(1, 0), Offset(0, 1)],
              roomWCm: 400,
              roomHCm: 500),
          isEmpty);
    });

    test('a run between the camera and the room center is cut', () {
      final drafts = draftWallsFor(
          wallsCm: const [Offset(0, 450), Offset(400, 450)],
          roomWCm: 400,
          roomHCm: 500,
          cameraCm: const Offset(200, 900));
      expect(drafts.single.cut, isTrue);
      final far = draftWallsFor(
          wallsCm: const [Offset(0, 50), Offset(400, 50)],
          roomWCm: 400,
          roomHCm: 500,
          cameraCm: const Offset(200, 900));
      expect(far.single.cut, isFalse);
    });

    test('a draft run renders as a real slab with thickness and height', () {
      final shell = ShellGeometry(
          ringCm: shellRing(wallsCm: const [], roomWCm: 400, roomHCm: 500));
      const floor = FloorFinish(
          type: FloorFinishType.woodPlanks, colorArgb: 0xFFC8A27A, sizeM: 0.2);
      const wall = WallFinish(type: WallFinishType.paint, colorArgb: 0xFFEDE8E0);
      final plain =
          generateRoomShellGlb(shell: shell, floor: floor, wall: wall);
      final drafted = generateRoomShellGlb(
          shell: shell,
          floor: floor,
          wall: wall,
          draftWalls: const [DraftWall(Offset(100, 250), Offset(300, 250))]);
      expect(drafted.length, greaterThan(plain.length));
      final b = GlbBounds.fromGlbBytes(drafted);
      expect(b.heightM, closeTo(2.7, 0.02));
    });
  });

  group('walkthrough ceiling', () {
    test('the ceiling is an unlit slab at wall height', () {
      final shell = ShellGeometry(
          ringCm: shellRing(wallsCm: const [], roomWCm: 400, roomHCm: 500));
      final bytes = generateRoomCeilingGlb(
          shell: shell,
          wall: const WallFinish(
              type: WallFinishType.paint, colorArgb: 0xFFEDE8E0));
      final b = GlbBounds.fromGlbBytes(bytes);
      expect(b.minY, closeTo(2.7, 1e-6));
      expect(b.maxY, closeTo(2.7, 1e-6));
      final json = glbJson(bytes);
      expect(json['extensionsUsed'], contains('KHR_materials_unlit'));
    });

    test('the bridge adds the ceiling as a shadowless node lifted to the '
        'wall tops', () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('scene3d_77');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async {
        calls.add(c);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final tmp = Directory.systemTemp.createTempSync('ceil');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final bridge = PlannerSceneBridge(
          controller: Scene3DController(), cacheRootProvider: () async => tmp);
      bridge.controller.bindTo(77);
      await bridge.syncShell(
        wallsCm: const [],
        roomWCm: 400,
        roomHCm: 500,
        floor: const FloorFinish(
            type: FloorFinishType.woodPlanks,
            colorArgb: 0xFFC8A27A,
            sizeM: 0.2),
        wall: const WallFinish(
            type: WallFinishType.paint, colorArgb: 0xFFEDE8E0),
        ceiling: true,
      );
      final ceiling = calls.firstWhere((c) =>
          c.method == 'addModel' &&
          (c.arguments as Map)['id'] == PlannerSceneBridge.ceilingId);
      final args = ceiling.arguments as Map;
      expect(args['castShadows'], false);
      expect(args['y'], closeTo(2.7, 1e-9));
    });
  });

  group('planner screen', () {
    Future<void> pumpPlanner(WidgetTester tester,
        {List<FurniturePlacement> furniture = const [],
        double w = 400,
        double h = 500}) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: RoomScannerScreen(
            existingDesign: RoomDesign(
              id: 'd1',
              name: 'Test Room',
              roomType: 'living_room',
              widthCm: w,
              heightCm: h,
              furniture: furniture,
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
              userId: 'u1',
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    dynamic stateOf(WidgetTester tester) =>
        tester.state(find.byType(RoomScannerScreen));

    testWidgets('zoom buttons dolly the orbit camera', (tester) async {
      await pumpPlanner(tester);
      final start = stateOf(tester).debugCameraDistanceM as double;
      await tester.tap(find.byKey(const ValueKey('planner-zoom-in')));
      await tester.pump();
      final closer = stateOf(tester).debugCameraDistanceM as double;
      expect(closer, lessThan(start));
      await tester.tap(find.byKey(const ValueKey('planner-zoom-out')));
      await tester.pump();
      expect(stateOf(tester).debugCameraDistanceM as double,
          closeTo(start, 1e-6));
    });

    testWidgets('full view hides the catalogue and toolbar', (tester) async {
      await pumpPlanner(tester);
      expect(find.byKey(const ValueKey('planner-catalog-panel')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('planner-expand')));
      await tester.pump();
      expect(find.byKey(const ValueKey('planner-catalog-panel')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('planner-expand')));
      await tester.pump();
      expect(find.byKey(const ValueKey('planner-catalog-panel')), findsOneWidget);
    });

    testWidgets('a catalogue piece bigger than the room is refused',
        (tester) async {
      await pumpPlanner(tester, w: 120, h: 120);
      final bed = roomCatalog.firstWhere((c) => c.iconName == 'bed');
      expect(math.min(bed.defaultWidth, bed.defaultHeight), greaterThan(120));
      stateOf(tester).debugAddFromCatalog(bed);
      await tester.pump();
      expect((stateOf(tester).debugFurniture as List), isEmpty);
      expect(find.textContaining('is bigger than this room'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('consecutive catalogue adds land on clear floor',
        (tester) async {
      await pumpPlanner(tester);
      final sofa = roomCatalog.firstWhere((c) => c.iconName == 'sofa');
      final chair = roomCatalog.firstWhere((c) => c.iconName == 'armchair');
      stateOf(tester).debugAddFromCatalog(sofa);
      stateOf(tester).debugAddFromCatalog(chair);
      stateOf(tester).debugAddFromCatalog(chair);
      await tester.pump();
      final items =
          (stateOf(tester).debugFurniture as List).cast<FurniturePlacement>();
      expect(items, hasLength(3));
      for (var i = 0; i < items.length; i++) {
        for (var j = i + 1; j < items.length; j++) {
          expect(footprintsOverlap(items[i], items[j]), isFalse,
              reason: '${items[i].name} overlaps ${items[j].name}');
        }
      }
    });
  });
}
