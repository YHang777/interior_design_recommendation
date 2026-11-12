import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/scanner/data/scene3d_controller.dart';
import 'package:interior_design_recommendation/features/customer/scanner/presentation/scene3d_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter/platform_views'), (call) async => 1);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter/platform_views'), null);
  });

  Widget host({
    void Function(Offset)? onTap,
    void Function(Offset)? onLongPress,
    void Function(ScaleStartDetails)? onScaleStart,
    void Function(ScaleUpdateDetails)? onScaleUpdate,
    void Function(ScaleEndDetails)? onScaleEnd,
  }) =>
      MaterialApp(
        home: Scene3DView(
          controller: Scene3DController(),
          onTap: onTap,
          onLongPress: onLongPress,
          onScaleStart: onScaleStart,
          onScaleUpdate: onScaleUpdate,
          onScaleEnd: onScaleEnd,
        ),
      );

  testWidgets('a quick tap fires onTap and nothing else', (tester) async {
    final taps = <Offset>[];
    final scales = <String>[];
    await tester.pumpWidget(host(
      onTap: taps.add,
      onScaleStart: (_) => scales.add('start'),
      onScaleEnd: (_) => scales.add('end'),
    ));

    await tester.tap(find.byType(AndroidView));
    await tester.pump();

    expect(taps, hasLength(1));
    expect(scales, isEmpty);
  });

  testWidgets('a one-finger drag is a scale sequence, not a tap',
      (tester) async {
    final taps = <Offset>[];
    final starts = <int>[];
    final updates = <ScaleUpdateDetails>[];
    var ends = 0;
    await tester.pumpWidget(host(
      onTap: taps.add,
      onScaleStart: (d) => starts.add(d.pointerCount),
      onScaleUpdate: updates.add,
      onScaleEnd: (_) => ends++,
    ));

    final g = await tester.startGesture(tester.getCenter(find.byType(AndroidView)));
    await g.moveBy(const Offset(40, 0));
    await g.moveBy(const Offset(30, 0));
    await g.up();
    await tester.pump();

    expect(taps, isEmpty);
    expect(starts, [1]);
    expect(updates, hasLength(2));
    expect(updates.last.focalPointDelta, const Offset(30, 0));
    expect(updates.last.scale, 1.0);
    expect(ends, 1);
  });

  testWidgets('a held press fires onLongPress and suppresses the tap',
      (tester) async {
    final taps = <Offset>[];
    final presses = <Offset>[];
    await tester.pumpWidget(host(
      onTap: taps.add,
      onLongPress: presses.add,
    ));

    await tester.longPress(find.byType(AndroidView));
    await tester.pump();

    expect(presses, hasLength(1));
    expect(taps, isEmpty);
  });

  testWidgets('two fingers pinch with a distance-ratio scale', (tester) async {
    final updates = <ScaleUpdateDetails>[];
    final starts = <int>[];
    var ends = 0;
    await tester.pumpWidget(host(
      onScaleStart: (d) => starts.add(d.pointerCount),
      onScaleUpdate: updates.add,
      onScaleEnd: (_) => ends++,
    ));

    final center = tester.getCenter(find.byType(AndroidView));
    final a = await tester.startGesture(center + const Offset(-40, 0));
    await tester.pump();
    final b = await tester.startGesture(center + const Offset(40, 0));
    await tester.pump();
    // Baseline span 80 → move the fingers to span 160.
    await a.moveBy(const Offset(-40, 0));
    await b.moveBy(const Offset(40, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pump();

    // Lifting the first finger ends the pinch and hands the last finger a
    // fresh one-finger drag, which then ends on its lift.
    expect(starts, [2, 1]);
    expect(updates, isNotEmpty);
    expect(updates.last.scale, closeTo(160 / 80, 0.01));
    expect(ends, 2);
  });
}
