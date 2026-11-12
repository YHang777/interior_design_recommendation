import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/ar/data/glb_generator.dart'
    show FloorFinishType, WallFinishType;
import 'package:interior_design_recommendation/features/customer/scanner/presentation/screens/room_scanner_screen.dart';
import 'package:interior_design_recommendation/models/room_design.dart';
import 'package:interior_design_recommendation/services/material_scan_service.dart';

void main() {
  RoomDesign design({
    String? floorType,
    int? floorColor,
    String? wallType,
    int? wallColor,
  }) =>
      RoomDesign(
        id: 'd1',
        name: 'Scan Room',
        roomType: 'living_room',
        widthCm: 400,
        heightCm: 500,
        floorFinishType: floorType,
        floorFinishColor: floorColor,
        wallFinishType: wallType,
        wallFinishColor: wallColor,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        userId: 'u1',
      );

  Future<dynamic> pumpScanner(
    WidgetTester tester, {
    RoomDesign? existing,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: RoomScannerScreen(existingDesign: existing),
        ),
      ),
    );
    await tester.pump();
    return tester.state(find.byType(RoomScannerScreen));
  }

  testWidgets('a matched scan lands on the plan snapshot', (tester) async {
    final state = await pumpScanner(tester);

    final snapshot = state.debugApplyMaterialScan(const RoomMaterialScan(
      floorType: FloorFinishType.woodPlanks,
      floorColorArgb: 0xFF6B4A32,
      wallType: WallFinishType.paint,
      wallColorArgb: 0xFF22334D,
    )) as RoomDesign;

    expect(snapshot.floorFinishType, 'woodPlanks');
    expect(snapshot.floorFinishColor, 0xFF6B4A32);
    expect(snapshot.wallFinishType, 'paint');
    expect(snapshot.wallFinishColor, 0xFF22334D);
  });

  testWidgets('existing finishes survive a scan that matched nothing',
      (tester) async {
    final state = await pumpScanner(
      tester,
      existing: design(
        floorType: 'parquet',
        floorColor: 0xFFC9A368,
        wallType: 'brick',
        wallColor: 0xFFA8442F,
      ),
    );

    final snapshot =
        state.debugApplyMaterialScan(const RoomMaterialScan()) as RoomDesign;

    expect(snapshot.floorFinishType, 'parquet');
    expect(snapshot.floorFinishColor, 0xFFC9A368);
    expect(snapshot.wallFinishType, 'brick');
    expect(snapshot.wallFinishColor, 0xFFA8442F);
  });

  testWidgets('a partial scan only replaces the side it saw', (tester) async {
    final state = await pumpScanner(
      tester,
      existing: design(
        floorType: 'parquet',
        floorColor: 0xFFC9A368,
        wallType: 'brick',
        wallColor: 0xFFA8442F,
      ),
    );

    final snapshot = state.debugApplyMaterialScan(const RoomMaterialScan(
      wallType: WallFinishType.woodPanels,
      wallColorArgb: 0xFF6B4A32,
    )) as RoomDesign;

    expect(snapshot.floorFinishType, 'parquet');
    expect(snapshot.floorFinishColor, 0xFFC9A368);
    expect(snapshot.wallFinishType, 'woodPanels');
    expect(snapshot.wallFinishColor, 0xFF6B4A32);
  });
}
