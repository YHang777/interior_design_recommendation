import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/ar/data/glb_generator.dart'
    show FloorFinishType;
import 'package:interior_design_recommendation/features/customer/ar/data/room_finishes.dart';
import 'package:interior_design_recommendation/features/customer/walkthrough/presentation/plan_preview_3d.dart';
import 'package:interior_design_recommendation/features/customer/walkthrough/presentation/walkthrough_painter.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

void main() {
  RoomDesign design({
    double widthCm = 400,
    List<FurniturePlacement> furniture = const [],
  }) =>
      RoomDesign(
        id: 'd1',
        name: 'Preview',
        roomType: 'living_room',
        widthCm: widthCm,
        heightCm: 500,
        furniture: furniture,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        userId: 'u1',
      );

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  WalkthroughPainter painterOf(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is WalkthroughPainter));
    return paint.painter as WalkthroughPainter;
  }

  testWidgets('renders the walkthrough painter and orbits over time',
      (tester) async {
    await tester.pumpWidget(host(PlanPreview3D(design: design())));
    await tester.pump();

    final painter = painterOf(tester);
    expect(painter.controller.roomW, 400);

    final before = painter.controller.heading;
    await tester.pump(const Duration(milliseconds: 500));
    expect(painterOf(tester).controller.heading, isNot(before));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('only a geometry change resets the preview pose',
      (tester) async {
    await tester.pumpWidget(host(PlanPreview3D(design: design())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final moved = painterOf(tester).controller;
    expect(moved.heading, isNot(0));

    // The planner rebuilds a fresh snapshot per edit; same content must
    // not reset the orbit.
    await tester.pumpWidget(host(PlanPreview3D(design: design())));
    await tester.pump();
    expect(identical(painterOf(tester).controller, moved), isTrue);

    await tester.pumpWidget(host(PlanPreview3D(
      design: design(
        widthCm: 600,
        furniture: const [
          FurniturePlacement(
            id: 'sofa-1',
            name: 'Sofa',
            iconName: 'sofa',
            x: 20,
            y: 20,
            width: 180,
            height: 90,
          ),
        ],
      ),
    )));
    await tester.pump();
    final rebuilt = painterOf(tester).controller;
    expect(identical(rebuilt, moved), isFalse);
    expect(rebuilt.roomW, 600);
    expect(rebuilt.furniture, hasLength(1));
    expect(rebuilt.heading, 0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the orbit stops when the preview leaves the tree',
      (tester) async {
    await tester.pumpWidget(host(PlanPreview3D(design: design())));
    await tester.pump();
    expect(find.byType(PlanPreview3D), findsOneWidget);

    await tester.pumpWidget(host(const SizedBox()));
    expect(find.byType(PlanPreview3D), findsNothing);
    // A live orbit timer would throw on the next time elapse.
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('design finishes reach the painter', (tester) async {
    const sel = FinishSelection(floorType: FloorFinishType.cement);
    await tester
        .pumpWidget(host(PlanPreview3D(design: design(), finishes: sel)));
    await tester.pump();
    expect(painterOf(tester).finishes, sel);

    await tester.pumpWidget(const SizedBox());
  });
}
