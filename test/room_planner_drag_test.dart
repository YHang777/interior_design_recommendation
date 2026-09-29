import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/scanner/presentation/screens/room_scanner_screen.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

/// Regression tests for room-planner furniture dragging.
///
/// The drag path used to call setState on every pointer-move, which rebuilt
/// the whole planner and ran wall-clamping per frame. These tests pin the
/// contract the fix relies on: a drag moves the tile with the finger, the
/// placement is committed once on release (and stays put), and selection /
/// removal still work.
void main() {
  Future<void> pumpPlanner(
    WidgetTester tester, {
    List<FurniturePlacement> furniture = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: RoomScannerScreen(
            existingDesign: RoomDesign(
              id: 'd1',
              name: 'Test Room',
              roomType: 'living_room',
              widthCm: 400,
              heightCm: 500,
              furniture: furniture,
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

  /// The placed tile on the canvas — not the "Sofa" chip in the Add catalog.
  /// Scoped by the placement id the plan editor keys each tile with.
  Finder sofaTile() => find.descendant(
        of: find.byKey(const ValueKey('sofa-1')),
        matching: find.text('Sofa'),
      );

  /// The plan canvas itself — the only Listener wired to pointer-move.
  Finder canvas() => find.byWidgetPredicate(
        (w) => w is Listener && w.onPointerMove != null,
      );

  /// Drags [finder] by [delta] and returns the tile's centre while the
  /// pointer is still down (i.e. before the placement is committed).
  Future<Offset> dragAndHold(
    WidgetTester tester,
    Finder finder,
    Offset delta,
  ) async {
    final gesture = await tester.startGesture(tester.getCenter(finder));
    // Two moves: the first crosses the pan slop so the recognizer accepts,
    // the second carries the bulk of the drag. (Exact pixel deltas are
    // gesture-slop dependent, so callers assert direction/persistence.)
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

    // It followed the finger down-and-right (magnitude is slop-dependent,
    // so only direction and "it actually travelled" are asserted).
    expect(during.dx - before.dx, greaterThan(80));
    expect(during.dy - before.dy, greaterThan(60));

    // The commit is applied exactly once on release and is not undone by a
    // later rebuild — the tile stays where it was dropped.
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
    // Sofa is 180×90 in a 400×500 room → max top-left (220, 410), i.e. the
    // bottom-right corner of the room. The canvas border must not push it
    // outside the drawing area.
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
    // System interruption (notification shade, incoming call) — no pan-end.
    await gesture.cancel();
    await tester.pump();

    // The model must agree with what the user sees: a cancelled drag is
    // committed, not silently reverted on the next rebuild.
    final after = tester.getCenter(sofaTile());
    expect(after.dx, moreOrLessEquals(during.dx, epsilon: 1));
    expect(after.dy, moreOrLessEquals(during.dy, epsilon: 1));
    expect(after.dx, greaterThan(before.dx + 40));
  });

  testWidgets('long-press removes a tile', (tester) async {
    await pumpPlanner(tester, furniture: [sofa()]);
    expect(sofaTile(), findsOneWidget);

    await tester.longPress(sofaTile());
    await tester.pump();
    expect(sofaTile(), findsNothing);
  });

  testWidgets('tap selects a tile and shows the selection bar', (tester) async {
    await pumpPlanner(tester, furniture: [sofa()]);
    await tester.tap(sofaTile());
    await tester.pump();
    expect(find.text('Tap to select · Drag to move · Long-press to remove'),
        findsOneWidget);
  });

  testWidgets('removing an earlier item keeps the later selection',
      (tester) async {
    const selectionHint =
        'Tap to select · Drag to move · Long-press to remove';
    // The second item is sofa-sized so its label renders (>55px), matching
    // the tap pattern used everywhere else here.
    await pumpPlanner(tester, furniture: [
      sofa(), // index 0
      const FurniturePlacement(
        id: 'chair-1',
        name: 'Armchair',
        iconName: 'armchair',
        x: 220,
        y: 200,
        width: 180,
        height: 90,
      ), // index 1
    ]);

    Finder armchairTile() => find.descendant(
          of: find.byKey(const ValueKey('chair-1')),
          matching: find.text('Armchair'),
        );

    // Select the second item, then remove the first.
    await tester.tap(armchairTile());
    await tester.pump();
    expect(find.text(selectionHint), findsOneWidget);

    await tester.longPress(sofaTile());
    await tester.pump();

    // The selection bar must still be showing — a stale index would either
    // drop it or point it at the wrong item. `selectionHint` appears only in
    // that bar, so its presence is the assertion.
    expect(find.text(selectionHint), findsOneWidget);
    expect(sofaTile(), findsNothing);
    expect(armchairTile(), findsOneWidget);
  });
}
