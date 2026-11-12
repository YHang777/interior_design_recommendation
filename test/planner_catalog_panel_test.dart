import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/scanner/presentation/screens/room_scanner_screen.dart';
import 'package:interior_design_recommendation/features/customer/walkthrough/presentation/plan_preview_3d.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

void main() {
  Future<dynamic> pumpScanner(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: RoomScannerScreen(
            materialScanService: null,
            existingDesign: RoomDesign(
              id: 'd1',
              name: 'Panel Room',
              roomType: 'living_room',
              widthCm: 400,
              heightCm: 500,
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
              userId: 'u1',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.state(find.byType(RoomScannerScreen));
  }

  testWidgets('category chips filter the photo tiles', (tester) async {
    await pumpScanner(tester);

    expect(find.byKey(const ValueKey('planner-catalog-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-tile-sofa')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-tile-bed')), findsOneWidget);

    await tester.tap(find.text('Bedroom'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog-tile-sofa')), findsNothing);
    expect(find.byKey(const ValueKey('catalog-tile-bed')), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog-tile-sofa')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-tile-bed')), findsOneWidget);
  });

  testWidgets('tapping a photo tile places the piece on the plan',
      (tester) async {
    final state = await pumpScanner(tester);

    await tester.tap(find.byKey(const ValueKey('catalog-tile-sofa')));
    await tester.pumpAndSettle();

    final placed = (state as dynamic).debugFurniture as List<FurniturePlacement>;
    expect(placed, hasLength(1));
    expect(placed.single.name, 'Sofa');
  });

  testWidgets('the platform fallback preview is static 3D of the plan',
      (tester) async {
    // iOS has no SceneView — the planner falls back to the painted 3D
    // preview, which must never auto-rotate the room.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpScanner(tester);
      await tester.tap(find.byKey(const ValueKey('catalog-tile-sofa')));
      await tester.pump();

      final preview = tester.widget<PlanPreview3D>(find.byType(PlanPreview3D));
      expect(preview.spin, isFalse, reason: 'the room must never auto-rotate');
      expect(preview.design.furniture, hasLength(1));
      await tester.pumpAndSettle();
    } finally {
      // Foundation debug vars must be restored before the test ends.
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
