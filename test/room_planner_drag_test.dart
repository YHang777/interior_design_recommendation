import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/datasources/supabase_room_design_datasource.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/room_fit.dart';
import 'package:interior_design_recommendation/features/customer/scanner/presentation/scene3d_view.dart';
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

  Finder selectionBar() => find.byKey(const ValueKey('planner-selection-bar'));

  dynamic stateOf(WidgetTester tester) =>
      tester.state(find.byType(RoomScannerScreen));

  List<FurniturePlacement> furnitureOf(WidgetTester tester) =>
      (stateOf(tester).debugFurniture as List).cast<FurniturePlacement>();

  List<Offset> wallsOf(WidgetTester tester) =>
      (stateOf(tester).debugWalls as List).cast<Offset>();

  Offset sceneTopLeft(WidgetTester tester) =>
      tester.getTopLeft(find.byType(Scene3DView));

  // One-finger scene drag through the real canvas recognizer: press the
  // piece's projected box center and move to the screen point of the target
  // floor delta. The grab offset cancels, so the piece lands at exactly
  // start + deltaCm before the commit settle.
  // Select first so the selection bar's layout is settled before the drag —
  // and re-measure the press point afterwards: the bar's appearance resizes
  // the scene, and every projection must use that one settled viewport.
  Future<List<FurniturePlacement>> dragPieceBy(
    WidgetTester tester,
    FurniturePlacement f,
    Offset deltaCm, {
    bool cancel = false,
  }) async {
    final dynamic state = stateOf(tester);
    final origin = sceneTopLeft(tester);
    await tester.tapAt(origin + (state.debugPieceToScreen(f) as Offset));
    await tester.pump();
    final start = (state.debugPieceToScreen(f) as Offset?)!;
    final floorStart = (state.debugFloorAt(start) as Offset?)!;
    final end = (state.debugFloorToScreen(
            Offset(floorStart.dx + deltaCm.dx, floorStart.dy + deltaCm.dy))
        as Offset?)!;
    final gesture = await tester.startGesture(origin + start);
    // A plan-space delta projects to only a few screen px (the axes partly
    // cancel), so clear the 18 px drag slop in screen space first — the
    // final position still comes from the last move alone.
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.moveTo(origin + end);
    await tester.pump();
    final mid = furnitureOf(tester);
    if (cancel) {
      await gesture.cancel();
    } else {
      await gesture.up();
    }
    await tester.pump();
    return mid;
  }

  Future<void> tapFloor(WidgetTester tester, Offset planCm) async {
    final dynamic state = stateOf(tester);
    final screen =
        (state.debugFloorToScreen(planCm) as Offset?)!;
    await tester.tapAt(sceneTopLeft(tester) + screen);
    await tester.pump();
  }

  Future<void> longPressFloor(WidgetTester tester, Offset planCm) async {
    final dynamic state = stateOf(tester);
    final screen =
        (state.debugFloorToScreen(planCm) as Offset?)!;
    final gesture = await tester.startGesture(sceneTopLeft(tester) + screen);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();
  }

  testWidgets('furniture is placed in the 3D scene and tapped to select',
      (tester) async {
    await pumpPlanner(tester, furniture: [sofa()]);

    await tester.tapAt(sceneTopLeft(tester) +
        (stateOf(tester).debugPieceToScreen(sofa()) as Offset));
    await tester.pump();

    expect(selectionBar(), findsOneWidget);
    expect(
        find.descendant(
            of: selectionBar(), matching: find.textContaining('Sofa')),
        findsOneWidget);
    expect(
        find.descendant(of: selectionBar(), matching: find.byType(Image)),
        findsOneWidget,
        reason: 'the selection bar shows the product photo');
  });

  testWidgets('tap on empty floor deselects the piece', (tester) async {
    await pumpPlanner(tester, furniture: [sofa()]);

    await tester.tapAt(sceneTopLeft(tester) +
        (stateOf(tester).debugPieceToScreen(sofa()) as Offset));
    await tester.pump();
    expect(selectionBar(), findsOneWidget);

    await tapFloor(tester, const Offset(20, 20));
    expect(selectionBar(), findsNothing);
  });

  testWidgets('drag moves the piece and commits it exactly on release',
      (tester) async {
    await pumpPlanner(tester, furniture: [sofa(x: 40, y: 40)]);

    final mid = await dragPieceBy(tester, sofa(), const Offset(30, 20));

    expect(mid.single.x, moreOrLessEquals(70, epsilon: 0.01));
    expect(mid.single.y, moreOrLessEquals(60, epsilon: 0.01));

    final after = furnitureOf(tester).single;
    expect(after.x, moreOrLessEquals(70, epsilon: 0.01),
        reason: 'a valid drop must not snap on release');
    expect(after.y, moreOrLessEquals(60, epsilon: 0.01));
  });

  testWidgets('drag is clamped to the room rectangle', (tester) async {
    await pumpPlanner(tester, furniture: [sofa(x: 200, y: 400)]);

    await dragPieceBy(tester, sofa(x: 200, y: 400), const Offset(100, 50));

    final placed = furnitureOf(tester).single;
    expect(placed.x, moreOrLessEquals(220, epsilon: 0.01));
    expect(placed.y, moreOrLessEquals(410, epsilon: 0.01));
    expect(placed.x + footprintW(placed), moreOrLessEquals(400, epsilon: 0.01));
    expect(placed.y + footprintH(placed), moreOrLessEquals(500, epsilon: 0.01));
  });

  testWidgets('a piece at the room edge sits flush inside the bounds',
      (tester) async {
    await pumpPlanner(tester, furniture: [sofa(x: 220, y: 410)]);

    final placed = furnitureOf(tester).single;
    expect(placed.x, 220, reason: 'a flush piece is kept, never re-settled');
    expect(placed.y, 410);
    expect(
        placementFits(placed, roomW: 400, roomH: 500, walls: const []),
        isTrue);
    expect(placed.x + footprintW(placed), moreOrLessEquals(400, epsilon: 0.01));
    expect(placed.y + footprintH(placed), moreOrLessEquals(500, epsilon: 0.01));
    expect(clampAllPlacements([placed], roomW: 400, roomH: 500, walls: const []),
        [placed]);
  });

  testWidgets('a cancelled drag still commits where the piece was left',
      (tester) async {
    await pumpPlanner(tester, furniture: [sofa(x: 40, y: 40)]);

    final mid =
        await dragPieceBy(tester, sofa(), const Offset(60, 40), cancel: true);

    expect(mid.single.x, moreOrLessEquals(100, epsilon: 0.01));
    final after = furnitureOf(tester).single;
    expect(after.x, moreOrLessEquals(100, epsilon: 0.01),
        reason: 'a cancelled drag commits, it does not snap back');
    expect(after.y, moreOrLessEquals(80, epsilon: 0.01));
  });

  testWidgets('long-press removes the piece', (tester) async {
    await pumpPlanner(tester, furniture: [sofa()]);
    final dynamic state = stateOf(tester);
    final screen = (state.debugPieceToScreen(sofa()) as Offset);

    final gesture = await tester.startGesture(sceneTopLeft(tester) + screen);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();

    expect(furnitureOf(tester), isEmpty);
  });

  testWidgets('removing a piece can be undone from the snackbar',
      (tester) async {
    await pumpPlanner(tester, furniture: [sofa()]);
    final dynamic state = stateOf(tester);
    final screen = (state.debugPieceToScreen(sofa()) as Offset);

    final gesture = await tester.startGesture(sceneTopLeft(tester) + screen);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();
    expect(furnitureOf(tester), isEmpty);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(furnitureOf(tester), hasLength(1));
  });

  testWidgets('the selection bar offers Size, Rotate and Remove',
      (tester) async {
    await pumpPlanner(tester, furniture: [sofa()]);
    await tester.tapAt(sceneTopLeft(tester) +
        (stateOf(tester).debugPieceToScreen(sofa()) as Offset));
    await tester.pump();

    expect(selectionBar(), findsOneWidget);
    expect(
        find.descendant(of: selectionBar(), matching: find.text('Size')),
        findsOneWidget);
    expect(
        find.descendant(of: selectionBar(), matching: find.text('Rotate')),
        findsOneWidget);
    expect(
        find.descendant(
            of: selectionBar(), matching: find.byTooltip('Remove')),
        findsOneWidget);
  });

  testWidgets('rotate swaps the footprint, settles it and shows the badge',
      (tester) async {
    // Rotated footprint overhangs the bottom wall — rotate must settle.
    await pumpPlanner(
      tester,
      furniture: [sofa(x: 100, y: 300)],
      walls: const [
        Offset(50, 50),
        Offset(350, 50),
        Offset(350, 450),
        Offset(50, 450),
      ],
    );
    expect(find.byKey(const ValueKey('rotation-badge')), findsNothing);

    await tester.tapAt(sceneTopLeft(tester) +
        (stateOf(tester).debugPieceToScreen(furnitureOf(tester).single)
            as Offset));
    await tester.pump();
    await tester.tap(find.text('Rotate'));
    await tester.pump();

    final placed = furnitureOf(tester).single;
    expect(placed.rotation, 90);
    expect(footprintW(placed), 90, reason: 'the footprint swaps on its side');
    expect(footprintH(placed), 180);
    expect(placed.x, moreOrLessEquals(100, epsilon: 0.5));
    expect(placed.y, moreOrLessEquals(270, epsilon: 0.5),
        reason: 'settles just inside the bottom wall, not at the center');
    expect(
        placementFits(placed,
            roomW: 400, roomH: 500, walls: wallsOf(tester)),
        isTrue);
    expect(find.byKey(const ValueKey('rotation-badge')), findsOneWidget);
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
    final dynamic state = stateOf(tester);
    final items = furnitureOf(tester);
    final armchair = items.firstWhere((f) => f.id == 'chair-1');

    await tester.tapAt(sceneTopLeft(tester) +
        (state.debugPieceToScreen(armchair) as Offset));
    await tester.pump();
    expect(selectionBar(), findsOneWidget);

    final theSofa = items.firstWhere((f) => f.id == 'sofa-1');
    final gesture = await tester.startGesture(
        sceneTopLeft(tester) + (state.debugPieceToScreen(theSofa) as Offset));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pump();

    expect(selectionBar(), findsOneWidget);
    expect(
        find.descendant(
            of: selectionBar(), matching: find.textContaining('Armchair')),
        findsOneWidget);
    expect(furnitureOf(tester).map((f) => f.id), ['chair-1']);
  });

  testWidgets('furniture drags never touch wall corners', (tester) async {
    const savedWalls = [
      Offset(30, 30),
      Offset(370, 30),
      Offset(200, 450),
    ];
    await pumpPlanner(tester, furniture: [sofa()], walls: savedWalls);

    // Mode separation: corners only exist behind wall mode.
    expect(find.byKey(const ValueKey('wall-handle-0')), findsNothing);

    final wallsBefore = wallsOf(tester);
    final theSofa = furnitureOf(tester).single;
    final mid = await dragPieceBy(tester, theSofa, const Offset(30, 15));

    expect(mid.single.x, moreOrLessEquals(theSofa.x + 30, epsilon: 0.01),
        reason: 'the drag itself must have moved the piece');

    final wallsAfter = wallsOf(tester);
    expect(wallsAfter, hasLength(3));
    for (var i = 0; i < 3; i++) {
      expect((wallsAfter[i] - wallsBefore[i]).distance, lessThan(0.01),
          reason: 'wall corner $i must not follow the furniture drag');
    }
  });

  List<List<Offset>> interiorOf(WidgetTester tester) =>
      (stateOf(tester).debugInteriorWalls as List)
          .map((c) => (c as List).cast<Offset>())
          .toList();

  testWidgets('wall-mode taps build an interior wall; the room stays',
      (tester) async {
    await pumpPlanner(tester);

    await tester.tap(find.text('Walls'));
    await tester.pump();

    await tapFloor(tester, const Offset(30, 30));
    await tapFloor(tester, const Offset(35, 35));
    expect(interiorOf(tester).single, hasLength(1),
        reason: 'a corner within 12 cm of the last one is rejected');

    await tapFloor(tester, const Offset(370, 30));
    await tapFloor(tester, const Offset(200, 250));

    final chain = interiorOf(tester).single;
    expect(chain, hasLength(3));
    expect(chain[0], moreOrLessEqualsPoint(const Offset(30, 30)));
    expect(chain[1], moreOrLessEqualsPoint(const Offset(370, 30)));
    expect(chain[2], moreOrLessEqualsPoint(const Offset(200, 250)));
    expect(wallsOf(tester), isEmpty,
        reason: 'three corners must NOT replace the room with a triangle');
  });

  testWidgets('Finish wall starts a separate wall on the next tap',
      (tester) async {
    await pumpPlanner(tester);
    await tester.tap(find.text('Walls'));
    await tester.pump();

    await tapFloor(tester, const Offset(100, 100));
    await tapFloor(tester, const Offset(300, 100));
    await tester.tap(find.byKey(const ValueKey('planner-finish-wall')));
    await tester.pump();
    await tapFloor(tester, const Offset(100, 300));
    await tapFloor(tester, const Offset(100, 450));

    final chains = interiorOf(tester);
    expect(chains, hasLength(2));
    expect(chains[0], hasLength(2));
    expect(chains[1], hasLength(2));
  });

  testWidgets('wall handles move corners to new floor points', (tester) async {
    await pumpPlanner(tester, walls: const [
      Offset(50, 50),
      Offset(350, 50),
      Offset(350, 450),
      Offset(50, 450),
    ]);
    await tester.tap(find.text('Walls'));
    await tester.pump();

    final handle = find.byKey(const ValueKey('wall-handle-0'));
    expect(handle, findsOneWidget);
    final dynamic state = stateOf(tester);
    final target = sceneTopLeft(tester) +
        (state.debugFloorToScreen(const Offset(120, 110)) as Offset);
    final startPt = tester.getCenter(handle);

    final gesture = await tester.startGesture(startPt);
    final step = (target - startPt) / 3;
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(step);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    final walls = wallsOf(tester);
    expect(walls[0], moreOrLessEqualsPoint(const Offset(120, 110)));
    expect(walls[1], moreOrLessEqualsPoint(const Offset(350, 50)));
    expect(walls[2], moreOrLessEqualsPoint(const Offset(350, 450)));
    expect(walls[3], moreOrLessEqualsPoint(const Offset(50, 450)));
  });

  testWidgets('wall-mode long-press clears interior walls, keeps the outline, '
      'and undo restores them', (tester) async {
    await pumpPlanner(tester, walls: const [
      Offset(50, 50),
      Offset(350, 50),
      Offset(350, 450),
      Offset(50, 450),
    ]);
    await tester.tap(find.text('Walls'));
    await tester.pump();
    await tapFloor(tester, const Offset(100, 200));
    await tapFloor(tester, const Offset(300, 200));
    expect(interiorOf(tester).single, hasLength(2));

    await longPressFloor(tester, const Offset(200, 350));

    expect(interiorOf(tester), isEmpty);
    expect(wallsOf(tester), hasLength(4), reason: 'the room outline stays');
    expect(find.text('Interior walls cleared'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(interiorOf(tester).single, hasLength(2));
  });

  testWidgets('opening a saved design restores its wall outline',
      (tester) async {
    const savedWalls = [
      Offset(30, 30),
      Offset(370, 30),
      Offset(200, 450),
    ];
    await pumpPlanner(tester, walls: savedWalls);

    final walls = wallsOf(tester);
    expect(walls, hasLength(3));
    for (var i = 0; i < savedWalls.length; i++) {
      expect(walls[i], moreOrLessEqualsPoint(savedWalls[i]));
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

  testWidgets('a drop fully inside the outline stays exactly where released',
      (tester) async {
    await pumpPlanner(
      tester,
      furniture: [sofa(x: 80, y: 120)],
      walls: const [
        Offset(50, 50),
        Offset(350, 50),
        Offset(350, 450),
        Offset(50, 450),
      ],
    );

    final mid = await dragPieceBy(tester, furnitureOf(tester).single,
        const Offset(30, 0));

    expect(mid.single.x, moreOrLessEquals(110, epsilon: 0.01));
    final placed = furnitureOf(tester).single;
    expect(placed.x, moreOrLessEquals(110, epsilon: 0.01),
        reason: 'a valid drop must not snap on release');
    expect(placed.y, moreOrLessEquals(120, epsilon: 0.01));
  });

  testWidgets('a drop straddling a wall settles just inside, not at the center',
      (tester) async {
    // Dragged left through the wall line — the drop point itself is invalid.
    await pumpPlanner(
      tester,
      furniture: [sofa(x: 80, y: 100)],
      walls: const [
        Offset(50, 50),
        Offset(350, 50),
        Offset(350, 450),
        Offset(50, 450),
      ],
    );

    final mid = await dragPieceBy(
        tester, furnitureOf(tester).single, const Offset(-50, 5));

    // The drag itself must have reached the straddling point — otherwise the
    // settle assertions below would hold even for a drag that never moved.
    expect(mid.single.x, moreOrLessEquals(30, epsilon: 0.01),
        reason: 'the drag itself must have moved the piece to the wall');
    final placed = furnitureOf(tester).single;
    expect(placed.x, greaterThanOrEqualTo(50),
        reason: 'sofa must end up inside the left wall');
    expect(placed.x + placed.width, lessThanOrEqualTo(350.1),
        reason: 'sofa must end up inside the right wall');
    expect(placed.x, lessThan(90),
        reason: 'settle near the drop — never yanked to the room center');
    expect(placed.y, inInclusiveRange(80, 120),
        reason: 'no vertical drift on a horizontal settle');
  });

  testWidgets('planner as a pushed route has the unified circled back button',
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
    final dynamic state = stateOf(tester);

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
    final dynamic state = stateOf(tester);

    expect(state.debugGuessRoomType(['Bed']), 'bedroom');
    expect(state.debugGuessRoomType(['Refrigerator']), 'kitchen');
    expect(state.debugGuessRoomType(['Dining Table']), 'dining_room');
    expect(state.debugGuessRoomType(['Desk']), 'home_office');
    expect(state.debugGuessRoomType(['Sofa']), isNull);
  });

  testWidgets('scan maps ML Kit aliases onto catalog items', (tester) async {
    await pumpPlanner(tester);
    final dynamic state = stateOf(tester);

    final added = state
        .debugAutoPlace(['Couch', 'Carpet', 'Bookcase', 'Television']) as int;

    expect(added, 4);
    expect(furnitureOf(tester).map((f) => f.name),
        ['Sofa', 'Rug', 'Bookshelf', 'TV Stand']);
  });

  testWidgets('Clear removes the wall outline when there is no furniture',
      (tester) async {
    await pumpPlanner(tester, walls: const [
      Offset(50, 50),
      Offset(350, 50),
      Offset(350, 450),
      Offset(50, 450),
    ]);
    final dynamic state = stateOf(tester);

    final clearBtn = find.widgetWithText(OutlinedButton, 'Clear');
    expect(tester.widget<OutlinedButton>(clearBtn).onPressed, isNotNull,
        reason: 'walls alone make Clear meaningful');

    await tester.tap(clearBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pumpAndSettle();

    expect(wallsOf(tester), isEmpty);
    expect(furnitureOf(tester), isEmpty);
    expect(find.text('Plan cleared'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect((state.debugWalls as List), hasLength(4));
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
      walls: const [
        Offset(50, 50),
        Offset(350, 50),
        Offset(350, 450),
        Offset(50, 450),
      ],
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

  testWidgets('size dialog applies a precise width', (tester) async {
    await pumpPlanner(tester, furniture: [sofa()]);
    await tester.tapAt(sceneTopLeft(tester) +
        (stateOf(tester).debugPieceToScreen(sofa()) as Offset));
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Size'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final widthField = find
        .descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField))
        .first;
    await tester.enterText(widthField, '210');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(furnitureOf(tester).single.width, 210);
  });

  testWidgets('size dialog resizes the piece height', (tester) async {
    await pumpPlanner(tester, furniture: [sofa()]);
    await tester.tapAt(sceneTopLeft(tester) +
        (stateOf(tester).debugPieceToScreen(sofa()) as Offset));
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Size'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final heightField = find
        .descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField))
        .last;
    await tester.enterText(heightField, '120');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(furnitureOf(tester).single.height, 120);
  });

  testWidgets('the camera reset button never moves the plan', (tester) async {
    await pumpPlanner(tester, furniture: [sofa()]);
    final before = furnitureOf(tester).single;

    await tester.tap(find.byKey(const ValueKey('planner-camera-reset')));
    await tester.pump();

    final after = furnitureOf(tester).single;
    expect(after.x, before.x);
    expect(after.y, before.y);
    expect(after.rotation, before.rotation);
  });
}

Matcher moreOrLessEqualsPoint(Offset expected, [double epsilon = 0.5]) =>
    isA<Offset>()
        .having((o) => (o.dx - expected.dx).abs(), 'dx', lessThanOrEqualTo(epsilon))
        .having((o) => (o.dy - expected.dy).abs(), 'dy', lessThanOrEqualTo(epsilon));
