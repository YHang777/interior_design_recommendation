import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/scanner/data/camera_rig.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/scene3d_controller.dart';
import 'package:interior_design_recommendation/features/customer/scanner/presentation/scene3d_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('scene3d_7');
  final log = <MethodCall>[];
  Object? response;

  setUp(() {
    log.clear();
    response = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.add(call);
      return response;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('setCamera sends eye/target/up/fov as lists of doubles', () async {
    final ctl = Scene3DController(viewId: 7);
    final pose = FirstPersonRig().pose(
      walkerXCm: 200,
      walkerYCm: 250,
      headingRad: 0,
    );
    await ctl.setCamera(pose);

    expect(log.single.method, 'setCamera');
    final args = log.single.arguments as Map<Object?, Object?>;
    expect(args['eye'], [pose.eyeX, pose.eyeY, pose.eyeZ]);
    expect(args['target'], [pose.targetX, pose.targetY, pose.targetZ]);
    expect(args['up'], [0.0, 1.0, 0.0]);
    expect(args['fovDeg'], pose.fovDeg);
  });

  test('addModel names its source kind and full transform', () async {
    final ctl = Scene3DController(viewId: 7);
    await ctl.addModel(const SceneModel(
      id: 'sofa-1',
      source: 'assets/models/three_seater_sofa.glb',
      xM: 1.6,
      yM: 0,
      zM: 3.05,
      yawDeg: -90,
      scaleX: 0.9,
      scaleY: 0.9,
      scaleZ: 0.9,
    ));
    await ctl.addModel(const SceneModel(
      id: 'product-2',
      source: '/data/user/0/app/cache/p.glb',
      fromAsset: false,
    ));

    expect(log.map((c) => c.method), ['addModel', 'addModel']);
    final first = log[0].arguments as Map<Object?, Object?>;
    expect(first['id'], 'sofa-1');
    expect(first['source'], 'assets/models/three_seater_sofa.glb');
    expect(first['sourceType'], 'asset');
    expect(first['x'], 1.6);
    expect(first['y'], 0);
    expect(first['z'], 3.05);
    expect(first['yawDeg'], -90);
    expect(first['scale'], [0.9, 0.9, 0.9]);
    final second = log[1].arguments as Map<Object?, Object?>;
    expect(second['sourceType'], 'file');
    expect(second['source'], '/data/user/0/app/cache/p.glb');
  });

  test('updateModel sends transforms without reloading the source', () async {
    final ctl = Scene3DController(viewId: 7);
    await ctl.updateModel(const SceneModel(
      id: 'sofa-1',
      source: 'ignored.glb',
      xM: 2,
      yM: 0,
      zM: 2,
      yawDeg: 180,
    ));

    final args = log.single.arguments as Map<Object?, Object?>;
    expect(log.single.method, 'updateModel');
    expect(args.containsKey('source'), isFalse);
    expect(args.containsKey('sourceType'), isFalse);
    expect(args['id'], 'sofa-1');
    expect(args['x'], 2);
    expect(args['yawDeg'], 180);
  });

  test('removeModel and clearModels round out the model lifecycle', () async {
    final ctl = Scene3DController(viewId: 7);
    await ctl.removeModel('sofa-1');
    await ctl.clearModels();

    expect(log.map((c) => c.method), ['removeModel', 'clearModels']);
    expect(log[0].arguments, {'id': 'sofa-1'});
    expect(log[1].arguments, isNull);
  });

  test('hitTest maps native hits and preserves distance order', () async {
    response = [
      {'id': 'sofa-1', 'distance': 1.5, 'x': 1.0, 'y': 0.4, 'z': 2.0},
      {'id': 'table-2', 'distance': 3.25, 'x': 0.5, 'y': 0.3, 'z': 1.0},
    ];
    final ctl = Scene3DController(viewId: 7);
    final hits = await ctl.hitTest(const Offset(120, 340));

    final args = log.single.arguments as Map<Object?, Object?>;
    expect(args['x'], 120);
    expect(args['y'], 340);
    expect(hits.map((h) => h.id), ['sofa-1', 'table-2']);
    expect(hits.first.distanceM, 1.5);
    expect(hits.first.yM, 0.4);
  });

  test('worldToScreen returns a pixel offset or null', () async {
    response = {'x': 512.5, 'y': 200.0};
    final ctl = Scene3DController(viewId: 7);
    expect(await ctl.worldToScreen(1, 0, 2), const Offset(512.5, 200));

    response = null;
    expect(await ctl.worldToScreen(1, 0, 2), isNull);
  });

  test('an unbound controller is a silent no-op', () async {
    final ctl = Scene3DController();
    await ctl.setCamera(FirstPersonRig().pose(
      walkerXCm: 0,
      walkerYCm: 0,
      headingRad: 0,
    ));
    await ctl.addModel(const SceneModel(id: 'x', source: 'x.glb'));
    expect(await ctl.hitTest(Offset.zero), isEmpty);
    expect(await ctl.worldToScreen(0, 0, 0), isNull);
    expect(log, isEmpty);
  });

  testWidgets('renders the fallback where 3D is unsupported', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(MaterialApp(
        home: Scene3DView(
          controller: Scene3DController(),
          fallback: const Text('2D fallback'),
        ),
      ));
      expect(Scene3DView.supported, isFalse);
      expect(find.text('2D fallback'), findsOneWidget);
    } finally {
      // Foundation debug vars must be restored before the test ends.
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('builds the platform surface and forwards taps', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter/platform_views'), (call) async => 1);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('flutter/platform_views'), null);
    });

    final taps = <Offset>[];
    await tester.pumpWidget(MaterialApp(
      home: Scene3DView(
        controller: Scene3DController(viewId: 7),
        onTap: taps.add,
      ),
    ));
    expect(Scene3DView.supported, isTrue);
    expect(tester.getSize(find.byType(AndroidView)), const Size(800, 600));

    await tester.tap(find.byType(AndroidView));
    await tester.pump();
    expect(taps, hasLength(1));
  });
}
