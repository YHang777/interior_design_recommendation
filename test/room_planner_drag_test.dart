import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/datasources/supabase_room_design_datasource.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/scanner/presentation/screens/room_scanner_screen.dart';
import 'package:interior_design_recommendation/models/room_design.dart';
import 'package:interior_design_recommendation/shared/widgets/float_button.dart';

class _CapturingDatasource extends SupabaseRoomDesignDatasource {
  final List<Map<String, dynamic>> payloads = [];

  @override
  Future<void> createDesign({
    required String designId,
    required Map<String, dynamic> data,
  }) async {
    payloads.add({'id': designId, ...data});
  }

  @override
  Future<void> updateDesign(
    String designId,
    Map<String, dynamic> data,
  ) async {
    payloads.add({'id': designId, ...data});
  }
}

class _TimeoutDatasource extends SupabaseRoomDesignDatasource {
  @override
  Future<void> createDesign({
    required String designId,
    required Map<String, dynamic> data,
  }) async {
    throw TimeoutException('slow');
  }

  @override
  Future<void> updateDesign(
    String designId,
    Map<String, dynamic> data,
  ) async {
    throw TimeoutException('slow');
  }
}

void main() {
  Future<void> pumpPlanner(
    WidgetTester tester, {
    List<FurniturePlacement> furniture = const [],
    List<Offset> walls = const [],
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          home: RoomScannerScreen(
            existingDesign: RoomDesign(
              id: 'd1',
              name: 'Test Room',
              roomType: 'living_room',
              widthCm: 400,
              heightCm: 500,
              furniture: furniture,
              walls: walls,
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
              userId: 'u1',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  FurniturePlacement sofa({double x = 40, double y = 40}) => FurniturePlacement(
        id: 'sofa-1',
        name: 'Sofa',
        iconName: 'sofa',
        x: x,
        y: y,
        width: 180,
        height: 90,
      );

  Finder sofaTile() => find.descendant(
        of: find.byKey(const ValueKey('sofa-1')),
        matching: find.text('Sofa'),
      );

  Finder canvas() => find.byWidgetPredicate(
        (w) => w is Listener && w.onPointerMove != null,
      );

  Future<Offset> dragAndHold(
    WidgetTester tester,
    Finder finder,
    Offset delta,
  ) async {
    final gesture = await tester.startGesture(tester.getCenter(finder));
    await gesture.moveBy(delta / 2);
    await tester.pump();
    await gesture.moveBy(delta / 2);
    await tester.pump();
    final during = tester.getCenter(finder);
    await gesture.up();
    await tester.pump();
    return during;
  }

  testWidgets('furniture tile is placed and rendered on the plan',
      (tester) async {
    await pumpPlanner(tester, furniture: [sofa()]);
    expect(sofaTile(), findsOneWidget);
  });

  testWidgets('drag moves the tile and commits it on release', (tester) async {
    await pumpPlanner(tester, furniture: [sofa(x: 40, y: 40)]);

    final before = tester.getCenter(sofaTile());
    final during = await dragAndHold(
        tester, sofaTile(), const Offset(200, 160));
    final after = tester.getCenter(sofaTile());

    expect(during.dx - before.dx, greaterThan(80));
    expect(during.dy - before.dy, greaterThan(60));

    expect(after.dx, moreOrLessEquals(during.dx, epsilon: 1));
    expect(after.dy, moreOrLessEquals(during.dy, epsilon: 1));
  });

  testWidgets('drag is clamped to the room rectangle', (tester) async {
    await pumpPlanner(tester, furniture: [sofa(x: 200, y: 400)]);

    await dragAndHold(tester, sofaTile(), const Offset(2000, 2000));

    final bounds = tester.getRect(canvas());
    final dropped = tester.getRect(sofaTile());
    expect(dropped.left, greaterThanOrEqualTo(bounds.left - 1));
    expect(dropped.top, greaterThanOrEqualTo(bounds.top - 1));
    expect(dropped.right, lessThanOrEqualTo(bounds.right + 1));
    expect(dropped.bottom, lessThanOrEqualTo(bounds.bottom + 1));
  });

  testWidgets('a tile at the room edge sits flush inside the canvas frame',
      (tester) async {
    await pumpPlanner(tester, furniture: [sofa(x: 220, y: 410)]);

    final bounds = tester.getRect(canvas());
    final tile = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('sofa-1')),
        matching: find.byType(Container),
      ).first,
    );
    expect(tile.right, moreOrLessEquals(bounds.right, epsilon: 1));
    expect(tile.bottom, moreOrLessEquals(bounds.bottom, epsilon: 1));
    expect(tile.left, greaterThanOrEqualTo(bounds.left - 1));
    expect(tile.top, greaterThanOrEqualTo(bounds.top - 1));
  });

  testWidgets('a cancelled drag still commits where the tile was left',
      (tester) async {
    await pumpPlanner(tester, furniture: [sofa(x: 40, y: 40)]);

    final before = tester.getCenter(sofaTile());
    final gesture = await tester.startGesture(before);
    await gesture.moveBy(const Offset(120, 80));
    await tester.pump();
    await gesture.moveBy(const Offset(120, 80));
    await tester.pump();
    final during = tester.getCenter(sofaTile());
    await gesture.cancel();
    await tester.pump();

    final after = tester.getCenter(sofaTile());
    expect(after.dx, moreOrLessEquals(during.dx, epsilon: 1));
    expect(after.dy, moreOrLessEquals(during.dy, epsilon: 1));
    expect(after.dx, greaterThan(before.dx + 40));
  });

  Finder selectionBar() => find.byKey(const ValueKey('planner-selection-bar'));

  testWidgets('long-press removes a tile', (tester) async {
    await pumpPlanner(tester, furniture: [sofa()]);
    expect(sofaTile(), findsOneWidget);

    await tester.longPress(sofaTile());
    await tester.pump();
    expect(sofaTile(), findsNothing);
  });

  testWidgets('removing a tile can be undone from the snackbar',
      (tester) async {
    await pumpPlanner(tester, furniture: [sofa()]);

    await tester.longPress(sofaTile());
    await tester.pump();
    expect(sofaTile(), findsNothing);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(sofaTile(), findsOneWidget);
  });

  testWidgets('tap selects a tile and shows the selection bar', (tester) async {
    await pumpPlanner(tester, furniture: [sofa()]);
    await tester.tap(sofaTile());
    await tester.pump();
    expect(selectionBar(), findsOneWidget);
    expect(find.descendant(of: selectionBar(), matching: find.text('Rotate')),
        findsOneWidget);
  });

  testWidgets('rotate turns the tile footprint on its side', (tester) async {
    await pumpPlanner(tester, furniture: [sofa()]);
    await tester.tap(sofaTile());
    await tester.pump();

    final before = tester.getRect(find.byKey(const ValueKey('sofa-1')));
    expect(before.width, greaterThan(before.height));

    await tester.tap(find.text('Rotate'));
    await tester.pump();

    final after = tester.getRect(find.byKey(const ValueKey('sofa-1')));
    expect(after.width, lessThan(after.height));
    expect(after.width, moreOrLessEquals(before.height, epsilon: 1));
    expect(after.height, moreOrLessEquals(before.width, epsilon: 1));
  });

  testWidgets('removing an earlier item keeps the later selection',
      (tester) async {
    await pumpPlanner(tester, furniture: [
      sofa(),
      const FurniturePlacement(
        id: 'chair-1',
        name: 'Armchair',
        iconName: 'armchair',
        x: 220,
        y: 200,
        width: 180,
        height: 90,
      ),
    ]);

    Finder armchairTile() => find.descendant(
          of: find.byKey(const ValueKey('chair-1')),
          matching: find.text('Armchair'),
        );

    await tester.tap(armchairTile());
    await tester.pump();
    expect(selectionBar(), findsOneWidget);

    await tester.longPress(sofaTile());
    await tester.pump();

    expect(selectionBar(), findsOneWidget);
    expect(sofaTile(), findsNothing);
    expect(armchairTile(), findsOneWidget);
  });

  testWidgets('dragging furniture does not drag a nearby wall corner',
      (tester) async {
    await pumpPlanner(tester, furniture: [sofa(x: 40, y: 40)]);

    await tester.tap(find.text('Walls'));
    await tester.pump();

    final canvasRect = tester.getRect(canvas());
    final dynamic state = tester.state(find.byType(RoomScannerScreen));

    Future<void> tapRoomCm(Offset roomCm) async {
      final s = canvasRect.width / 400;
      await tester
          .tapAt(canvasRect.topLeft + Offset(roomCm.dx * s, roomCm.dy * s));
      await tester.pump();
    }

    await tapRoomCm(const Offset(30, 30));
    await tapRoomCm(const Offset(370, 30));
    await tapRoomCm(const Offset(200, 450));
    expect(state.debugWalls.length, 3);

    await tester.tap(find.text('Add Corners'));
    await tester.pump();

    final wallsBefore = List<Offset>.from(state.debugWalls as List<Offset>);

    // Press on the sofa's top-left corner, within grab range of the
    // wall corner at (30, 30) — the old code grabbed the corner here
    // and dragged it along with the tile. Re-measure the canvas: it
    // grows again once the wall-mode hint row disappears.
    final dragCanvas = tester.getRect(canvas());
    final s = dragCanvas.width / 400;
    final gesture = await tester.startGesture(
        dragCanvas.topLeft + const Offset(42, 42) * s);
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 40));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    for (var i = 0; i < 3; i++) {
      expect((state.debugWalls[i] - wallsBefore[i]).distance, lessThan(0.5),
          reason: 'wall corner $i must not follow the furniture drag');
    }
  });

  testWidgets('opening a saved design restores its wall outline',
      (tester) async {
    const savedWalls = [
      Offset(30, 30),
      Offset(370, 30),
      Offset(200, 450),
    ];
    await pumpPlanner(tester, walls: savedWalls);

    final dynamic state = tester.state(find.byType(RoomScannerScreen));
    expect(state.debugWalls, hasLength(3));
    for (var i = 0; i < savedWalls.length; i++) {
      expect(state.debugWalls[i], moreOrLessEqualsPoint(savedWalls[i]));
    }
    expect(find.text('Room: 400 × 500 cm  •  3-wall shape'), findsOneWidget);
  });

  testWidgets('saving a design includes the wall outline in the payload',
      (tester) async {
    final ds = _CapturingDatasource();
    final user = AppUser(
      uid: 'u1',
      email: 'u1@test.dev',
      name: 'Tester',
      role: UserRole.homeowner,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    await pumpPlanner(
      tester,
      furniture: [sofa()],
      walls: const [Offset(30, 30), Offset(370, 30), Offset(200, 450)],
      overrides: [
        currentUserProvider.overrideWithValue(user),
        roomDesignDatasourceProvider.overrideWithValue(ds),
      ],
    );

    await tester.tap(find.byTooltip('Save Design'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(ds.payloads, hasLength(1));
    final payload = ds.payloads.single;
    expect(payload['walls'], [
      [30, 30],
      [370, 30],
      [200, 450],
    ]);
    expect(payload['furniture'], hasLength(1));
    expect(payload['widthCm'], 400);
    expect(payload['userId'], 'u1');
  });

  const squareWalls = [
    Offset(50, 50),
    Offset(350, 50),
    Offset(350, 450),
    Offset(50, 450),
  ];

  List<FurniturePlacement> furnitureOf(WidgetTester tester) {
    final dynamic state = tester.state(find.byType(RoomScannerScreen));
    return (state.debugFurniture as List).cast<FurniturePlacement>();
  }

  testWidgets(
      'drop overlapping a wall outline settles just inside, not at center',
      (tester) async {
    // Sofa starts straddling the left wall (x=30 < wall at 50).
    await pumpPlanner(
      tester,
      furniture: [sofa(x: 30, y: 100)],
      walls: squareWalls,
    );

    final canvasRect = tester.getRect(canvas());
    final s = canvasRect.width / 400;
    // Nudge it so the commit path runs _resolveDrop.
    await dragAndHold(tester, sofaTile(), Offset(4 * s, 0));

    final placed = furnitureOf(tester).single;
    expect(placed.x, greaterThanOrEqualTo(50),
        reason: 'sofa must end up inside the left wall');
    expect(placed.x + placed.width, lessThanOrEqualTo(350.1),
        reason: 'sofa must end up inside the right wall');
    expect(placed.x, lessThan(90),
        reason: 'settle near the drop — the old code yanked it to the '
            'room center (x=110)');
    expect(placed.y, inInclusiveRange(80, 120),
        reason: 'no vertical drift on a horizontal settle');
  });

  testWidgets('a drop fully inside the outline stays exactly where released',
      (tester) async {
    await pumpPlanner(
      tester,
      furniture: [sofa(x: 80, y: 120)],
      walls: squareWalls,
    );

    final before = tester.getCenter(sofaTile());
    // 80px clears the 36px pan slop so the drag is actually accepted.
    final during = await dragAndHold(tester, sofaTile(), const Offset(80, 0));
    final after = tester.getCenter(sofaTile());

    expect(during.dx - before.dx, greaterThan(20),
        reason: 'the pan must have moved the tile');
    // A resolve snap would show up as the tile shifting on release.
    expect(after.dx, moreOrLessEquals(during.dx, epsilon: 1));
    expect(after.dy, moreOrLessEquals(during.dy, epsilon: 1));

    final placed = furnitureOf(tester).single;
    expect(placed.x, greaterThanOrEqualTo(50));
    expect(placed.x + placed.width, lessThanOrEqualTo(350.1));
    expect(placed.y, moreOrLessEquals(120, epsilon: 0.5));
  });

  testWidgets(
      'planner as a pushed route has the unified circled back button',
      (tester) async {
    await pumpPlanner(tester);
    // Main page (MaterialApp home, nothing to pop) — no back button.
    expect(find.byType(FloatingBackButton), findsNothing);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RoomScannerScreen(),
                  ),
                ),
                child: const Text('open planner'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open planner'));
    await tester.pumpAndSettle();

    expect(find.byType(RoomScannerScreen), findsOneWidget);
    expect(find.byType(FloatingBackButton), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('scan auto-place drops junk labels and packs a tidy grid',
      (tester) async {
    await pumpPlanner(tester);
    final dynamic state = tester.state(find.byType(RoomScannerScreen));

    final added = state.debugAutoPlace(
        ['sofa', 'floor', 'sofa', 'bed', 'zzz unknown label']) as int;

    // floor → surface junk, sofa → duplicate, zzz → no catalog match.
    expect(added, 2);
    final items = furnitureOf(tester);
    expect(items.map((f) => f.name), ['Sofa', 'Bed']);

    // Row-packed from the top-left: sofa on row 1, bed wraps to row 2.
    expect(items[0].x, 25);
    expect(items[0].y, 25);
    expect(items[1].x, 25);
    expect(items[1].y, 140); // 25 + sofa height 90 + gap 25
    expect(items[0].id, isNot(equals(items[1].id)));
  });

  testWidgets('scan guesses the room type from what it recognized',
      (tester) async {
    await pumpPlanner(tester);
    final dynamic state = tester.state(find.byType(RoomScannerScreen));

    expect(state.debugGuessRoomType(['Bed']), 'bedroom');
    expect(state.debugGuessRoomType(['Refrigerator']), 'kitchen');
    expect(state.debugGuessRoomType(['Dining Table']), 'dining_room');
    expect(state.debugGuessRoomType(['Desk']), 'home_office');
    expect(state.debugGuessRoomType(['Sofa']), isNull);
  });

  testWidgets('scan maps ML Kit aliases onto catalog items', (tester) async {
    await pumpPlanner(tester);
    final dynamic state = tester.state(find.byType(RoomScannerScreen));

    final added = state
        .debugAutoPlace(['Couch', 'Carpet', 'Bookcase', 'Television']) as int;

    expect(added, 4);
    expect(furnitureOf(tester).map((f) => f.name),
        ['Sofa', 'Rug', 'Bookshelf', 'TV Stand']);
  });

  testWidgets('long-press on the wall outline clears it and offers undo',
      (tester) async {
    await pumpPlanner(tester, walls: squareWalls);
    final dynamic state = tester.state(find.byType(RoomScannerScreen));
    expect(state.debugWalls, hasLength(4));

    final canvasRect = tester.getRect(canvas());
    final s = canvasRect.width / 400;
    // Press on the top edge of the square outline (room coords 200,50).
    final gesture = await tester.startGesture(
        canvasRect.topLeft + const Offset(200, 50) * s);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pump();

    expect(state.debugWalls, isEmpty);
    expect(find.text('Walls cleared'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(state.debugWalls, hasLength(4));
    expect(state.debugWalls.first, const Offset(50, 50));
  });

  testWidgets('Clear removes the wall outline when there is no furniture',
      (tester) async {
    await pumpPlanner(tester, walls: squareWalls);
    final dynamic state = tester.state(find.byType(RoomScannerScreen));

    final clearBtn = find.widgetWithText(OutlinedButton, 'Clear');
    expect(tester.widget<OutlinedButton>(clearBtn).onPressed, isNotNull,
        reason: 'walls alone make Clear meaningful');

    await tester.tap(clearBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(state.debugWalls, isEmpty);
    expect(furnitureOf(tester), isEmpty);
    expect(find.text('Plan cleared'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(state.debugWalls, hasLength(4));
  });

  testWidgets('a save timeout shows the mapped connection notice',
      (tester) async {
    final user = AppUser(
      uid: 'u1',
      email: 'u1@test.dev',
      name: 'Tester',
      role: UserRole.homeowner,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    await pumpPlanner(
      tester,
      furniture: [sofa()],
      walls: squareWalls,
      overrides: [
        currentUserProvider.overrideWithValue(user),
        roomDesignDatasourceProvider
            .overrideWithValue(_TimeoutDatasource()),
      ],
    );

    await tester.tap(find.byTooltip('Save Design'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('This is taking too long. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: find.byType(SnackBar), matching: find.byIcon(Icons.error)),
      findsOneWidget,
      reason: 'errors use the shared red error card',
    );
  });
}

Matcher moreOrLessEqualsPoint(Offset expected, [double epsilon = 0.5]) =>
    isA<Offset>()
        .having((o) => (o.dx - expected.dx).abs(), 'dx', lessThanOrEqualTo(epsilon))
        .having((o) => (o.dy - expected.dy).abs(), 'dy', lessThanOrEqualTo(epsilon));
