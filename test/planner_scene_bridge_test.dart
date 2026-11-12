import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/ar/data/glb_bounds.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_generator.dart'
    show FloorFinish, FloorFinishType, WallFinish, WallFinishType;
import 'package:interior_design_recommendation/features/customer/scanner/data/planner_scene_bridge.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/scene3d_controller.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('scene3d_7');
  final log = <MethodCall>[];
  late Directory cacheRoot;

  const floor = FloorFinish(type: FloorFinishType.woodPlanks, colorArgb: 0xFFB08D6B);
  const wall = WallFinish(type: WallFinishType.paint, colorArgb: 0xFFF5F3EE);

  setUp(() async {
    log.clear();
    cacheRoot = await Directory.systemTemp.createTemp('planner_bridge');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    try {
      await cacheRoot.delete(recursive: true);
    } catch (_) {}
  });

  PlannerSceneBridge makeBridge() => PlannerSceneBridge(
        controller: Scene3DController(viewId: 7),
        cacheRootProvider: () async => cacheRoot,
      );

  FurniturePlacement cabinet({double x = 100, double y = 200, double rotation = 0}) =>
      FurniturePlacement(
        id: 'f1',
        name: 'Cabinet',
        iconName: 'cabinet',
        x: x,
        y: y,
        width: 90,
        height: 50,
        rotation: rotation,
      );

  Map<Object?, Object?> argsOf(MethodCall call) =>
      call.arguments as Map<Object?, Object?>;

  test('syncShell writes a shell GLB and adds it exactly once', () async {
    final bridge = makeBridge();
    await bridge.syncShell(
        wallsCm: const [],
        roomWCm: 400,
        roomHCm: 500,
        floor: floor,
        wall: wall);

    final adds = log.where((c) => c.method == 'addModel').toList();
    expect(adds, hasLength(1));
    final args = argsOf(adds.single);
    expect(args['id'], PlannerSceneBridge.shellId);
    expect(args['sourceType'], 'file');
    final file = File(args['source']! as String);
    expect(file.existsSync(), isTrue);
    final bounds = GlbBounds.fromGlbBytes(file.readAsBytesSync());
    // 4×5 m room plus 10 cm wall thickness on each side.
    expect(bounds.widthM, moreOrLessEquals(4.2, epsilon: 0.01));
    expect(bounds.depthM, moreOrLessEquals(5.2, epsilon: 0.01));
    expect(bounds.heightM, moreOrLessEquals(2.7, epsilon: 0.01));

    log.clear();
    await bridge.syncShell(
        wallsCm: const [],
        roomWCm: 400,
        roomHCm: 500,
        floor: floor,
        wall: wall);
    expect(log, isEmpty, reason: 'unchanged inputs must not churn the scene');
  });

  test('a finish change replaces the shell node', () async {
    final bridge = makeBridge();
    await bridge.syncShell(
        wallsCm: const [],
        roomWCm: 400,
        roomHCm: 500,
        floor: floor,
        wall: wall);
    log.clear();

    await bridge.syncShell(
        wallsCm: const [],
        roomWCm: 400,
        roomHCm: 500,
        floor: const FloorFinish(
            type: FloorFinishType.ceramicTiles, colorArgb: 0xFFF2F0EA),
        wall: wall);
    expect(log.map((c) => c.method), ['removeModel', 'addModel']);
    expect(argsOf(log.first)['id'], PlannerSceneBridge.shellId);
    expect(argsOf(log.last)['id'], PlannerSceneBridge.shellId);
  });

  test('a wall outline change regenerates the shell', () async {
    final bridge = makeBridge();
    await bridge.syncShell(
        wallsCm: const [],
        roomWCm: 400,
        roomHCm: 500,
        floor: floor,
        wall: wall);
    log.clear();

    await bridge.syncShell(
        wallsCm: const [
          Offset(0, 0),
          Offset(400, 0),
          Offset(400, 260),
          Offset(150, 260),
          Offset(150, 120),
          Offset(0, 120),
        ],
        roomWCm: 400,
        roomHCm: 500,
        floor: floor,
        wall: wall);
    expect(log.map((c) => c.method), ['removeModel', 'addModel']);
  });

  test('furniture syncs add, update and remove by diff', () async {
    final bridge = makeBridge();
    await bridge.syncFurniture([cabinet()]);

    final add = log.single;
    expect(add.method, 'addModel');
    final args = argsOf(add);
    expect(args['id'], 'f1');
    expect(args['sourceType'], 'file');
    // Placement (100,200) 90×50 → plan center (145,225) cm = (1.45, 2.25) m.
    // (Model detail like handles shifts natural bounds by a few mm.)
    expect(args['x'], moreOrLessEquals(1.45, epsilon: 0.02));
    expect(args['y'], 0);
    expect(args['z'], moreOrLessEquals(2.25, epsilon: 0.02));
    expect(args['yawDeg'], 0);
    // Catalog-sized placement over the catalog-sized model → unit scale.
    final scale = args['scale']! as List;
    expect(scale[0], moreOrLessEquals(1.0, epsilon: 0.02));
    expect(scale[1], moreOrLessEquals(1.0, epsilon: 0.02));
    expect(scale[2], moreOrLessEquals(1.0, epsilon: 0.02));

    log.clear();
    await bridge.syncFurniture([cabinet()]);
    expect(log, isEmpty, reason: 'an unchanged placement must not churn');

    log.clear();
    await bridge.syncFurniture([cabinet(x: 150)]);
    expect(log.map((c) => c.method), ['updateModel']);
    final upd = argsOf(log.single);
    expect(upd.containsKey('source'), isFalse,
        reason: 'updates must not resend the model source');
    expect(upd['x'], moreOrLessEquals(1.95, epsilon: 0.02));

    log.clear();
    await bridge.syncFurniture([]);
    expect(log.map((c) => c.method), ['removeModel']);
    expect(argsOf(log.single)['id'], 'f1');
  });

  test('rotation turns the model the opposite of the plan angle', () async {
    final bridge = makeBridge();
    await bridge.syncFurniture([cabinet(rotation: 90)]);

    final args = argsOf(log.single);
    expect(args['yawDeg'], -90);
    // Rotated footprint swaps W/H: center (100+25, 200+45) cm.
    expect(args['x'], moreOrLessEquals(1.25, epsilon: 0.02));
    expect(args['z'], moreOrLessEquals(2.45, epsilon: 0.02));
  });

  test('models scale per-axis to fill the validated footprint', () async {
    final bridge = makeBridge();
    await bridge.syncFurniture([
      FurniturePlacement(
        id: 'f1',
        name: 'Cabinet',
        iconName: 'cabinet',
        x: 0,
        y: 0,
        width: 45,
        height: 100,
      ),
    ]);

    final args = argsOf(log.single);
    // Scale is target ÷ the model's own natural box, per axis. Generated
    // detail (handles) nudges that box by a few mm, so the expectations are
    // read from the GLB — that also pins the axis mapping W→X, H→Y, D→Z and
    // the height coming from the catalog, not the plan.
    final nat = GlbBounds.fromGlbBytes(
        File(args['source']! as String).readAsBytesSync());
    final scale = args['scale']! as List;
    expect(scale[0], moreOrLessEquals(0.45 / nat.widthM, epsilon: 1e-6));
    expect(scale[1], moreOrLessEquals(1.8 / nat.heightM, epsilon: 1e-6));
    expect(scale[2], moreOrLessEquals(1.0 / nat.depthM, epsilon: 1e-6));
    // Per-axis, not uniform: squashed in x, stretched in z.
    expect(scale[0], lessThan(scale[1]));
    expect(scale[2], greaterThan(scale[1]));
    // XZ-centered model: origin lands on the placement center.
    expect(args['x'], moreOrLessEquals(0.225, epsilon: 0.02));
    expect(args['z'], moreOrLessEquals(0.5, epsilon: 0.02));
  });

  test('clearAll empties the scene and re-adds cleanly', () async {
    final bridge = makeBridge();
    await bridge.syncShell(
        wallsCm: const [],
        roomWCm: 400,
        roomHCm: 500,
        floor: floor,
        wall: wall);
    await bridge.syncFurniture([cabinet()]);
    log.clear();

    await bridge.clearAll();
    expect(log.map((c) => c.method), ['clearModels']);

    log.clear();
    await bridge.syncFurniture([cabinet()]);
    expect(log.map((c) => c.method), ['addModel']);
    await bridge.syncShell(
        wallsCm: const [],
        roomWCm: 400,
        roomHCm: 500,
        floor: floor,
        wall: wall);
    expect(log.map((c) => c.method), ['addModel', 'addModel'],
        reason: 'the shell key reset with clearAll, so it adds again');
  });

  test('an unknown icon generates a model at placement size', () async {
    final bridge = makeBridge();
    await bridge.syncFurniture([
      const FurniturePlacement(
        id: 'x1',
        name: 'Mystery Block',
        iconName: 'mystery_block',
        x: 0,
        y: 0,
        width: 120,
        height: 30,
      ),
    ]);

    final args = argsOf(log.single);
    expect(args['sourceType'], 'file');
    // Unknown icons are not modelled by the bundled library — a generated
    // stand-in fills the placement box (height falls back to the 30–220 cm
    // clamp of the plan height).
    final scale = args['scale']! as List;
    expect(scale[0], moreOrLessEquals(1.0, epsilon: 0.02));
    expect(scale[1], moreOrLessEquals(1.0, epsilon: 0.02));
    expect(scale[2], moreOrLessEquals(1.0, epsilon: 0.02));
  });

  test('a dropped pre-bind sync stays retryable once the view binds', () async {
    final bridge = PlannerSceneBridge(
      controller: Scene3DController(),
      cacheRootProvider: () async => cacheRoot,
    );
    await bridge.syncShell(
        wallsCm: const [], roomWCm: 400, roomHCm: 500, floor: floor, wall: wall);
    await bridge.syncFurniture([cabinet()]);
    expect(log, isEmpty, reason: 'no view is bound yet — the pushes are dropped');

    bridge.controller.bindTo(7);
    log.clear();
    await bridge.syncShell(
        wallsCm: const [], roomWCm: 400, roomHCm: 500, floor: floor, wall: wall);
    await bridge.syncFurniture([cabinet()]);
    expect(log.map((c) => c.method), ['addModel', 'addModel'],
        reason: 'dropped pushes must not read as already-synced');
  });

  test('a rebind re-pushes the whole scene instead of trusting stale caches',
      () async {
    final other = MethodChannel('scene3d_8');
    final otherLog = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(other, (call) async {
      otherLog.add(call);
      return null;
    });
    addTearDown(() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(other, null));

    final bridge = PlannerSceneBridge(
      controller: Scene3DController(),
      cacheRootProvider: () async => cacheRoot,
    );
    bridge.controller.bindTo(7);
    await bridge.syncShell(
        wallsCm: const [], roomWCm: 400, roomHCm: 500, floor: floor, wall: wall);
    await bridge.syncFurniture([cabinet()]);
    expect(log.map((c) => c.method), ['addModel', 'addModel']);

    // The view is recreated (stage switch, remount) → a fresh empty native
    // scene under a new id. The bind hook must have forgotten the caches.
    var bound = 0;
    bridge.onBound = (_) => bound++;
    bridge.controller.bindTo(8);
    expect(bound, 1);
    await bridge.syncShell(
        wallsCm: const [], roomWCm: 400, roomHCm: 500, floor: floor, wall: wall);
    await bridge.syncFurniture([cabinet()]);
    expect(otherLog.map((c) => c.method), ['addModel', 'addModel'],
        reason: 'the new view starts empty — everything must re-push');
  });

  test('a generated mesh change re-adds instead of a bare transform update',
      () async {
    final bridge = makeBridge();
    await bridge.syncFurniture([
      const FurniturePlacement(
          id: 'x1',
          name: 'Mystery Block',
          iconName: 'mystery_block',
          x: 100,
          y: 200,
          width: 90,
          height: 50),
    ]);
    expect(log.single.method, 'addModel');
    final firstSource = argsOf(log.single)['source']! as String;

    log.clear();
    // Resizing an unknown-icon piece re-authors its generated GLB at the new
    // size; the unit-scale transform can come out numerically unchanged, so
    // only the source reveals the swap — and updateModel carries no source.
    await bridge.syncFurniture([
      const FurniturePlacement(
          id: 'x1',
          name: 'Mystery Block',
          iconName: 'mystery_block',
          x: 100,
          y: 200,
          width: 120,
          height: 50),
    ]);
    expect(log.map((c) => c.method), ['addModel'],
        reason: 'the mesh itself changed — it must be re-added');
    expect(argsOf(log.single)['source'], isNot(firstSource));
  });

  test('the cutaway mask keys the shell — crossings regen, drift does not',
      () async {
    final bridge = makeBridge();
    Future<void> sync({Offset? cam}) => bridge.syncShell(
        wallsCm: const [],
        roomWCm: 400,
        roomHCm: 500,
        floor: floor,
        wall: wall,
        cutawayCameraCm: cam);

    await sync(cam: const Offset(200, -200)); // outside the bottom run
    expect(log.single.method, 'addModel');
    log.clear();

    // Free motion on the same side of every wall keeps the same mask.
    await sync(cam: const Offset(250, -400));
    expect(log, isEmpty, reason: 'same mask must not churn the scene');

    // Crossing to the far side flips the mask and swaps the shell.
    await sync(cam: const Offset(200, 700));
    expect(log.map((c) => c.method), ['removeModel', 'addModel']);
    log.clear();

    // Walkthrough-style full walls are a different key again.
    await sync();
    expect(log.map((c) => c.method), ['removeModel', 'addModel']);
    log.clear();
    await sync();
    expect(log, isEmpty, reason: 'unchanged full-wall sync must be free');
  });
}
