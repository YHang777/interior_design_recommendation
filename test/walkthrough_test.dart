import 'dart:math';

import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/auth/data/models/app_user.dart';
import 'package:interior_design_recommendation/features/auth/presentation/providers/auth_providers.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/data/datasources/supabase_room_design_datasource.dart';
import 'package:interior_design_recommendation/features/customer/homeowner/presentation/providers/design_providers.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/camera_rig.dart';
import 'package:interior_design_recommendation/features/customer/scanner/presentation/scene3d_view.dart';
import 'package:interior_design_recommendation/features/customer/walkthrough/presentation/walkthrough_controller.dart';
import 'package:interior_design_recommendation/features/customer/walkthrough/presentation/walkthrough_painter.dart';
import 'package:interior_design_recommendation/features/customer/walkthrough/presentation/walkthrough_scene.dart';
import 'package:interior_design_recommendation/features/customer/walkthrough/presentation/walkthrough_screen.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

class _CapturingDatasource extends SupabaseRoomDesignDatasource {
  final List<Map<String, dynamic>> payloads = [];
  final List<String> ops = [];

  @override
  Future<void> createDesign({
    required String designId,
    required Map<String, dynamic> data,
  }) async {
    ops.add('create');
    payloads.add({'id': designId, ...data});
  }

  @override
  Future<void> updateDesign(
    String designId,
    Map<String, dynamic> data,
  ) async {
    ops.add('update');
    payloads.add({'id': designId, ...data});
  }
}

const squareWalls = [
  Offset(50, 50),
  Offset(350, 50),
  Offset(350, 450),
  Offset(50, 450),
];

RoomDesign design({
  String id = 'd1',
  String name = 'Test Walk',
  List<Offset> walls = const [],
  String? floorFinishType,
  int? floorFinishColor,
  String? wallFinishType,
  int? wallFinishColor,
}) =>
    RoomDesign(
      id: id,
      name: name,
      roomType: 'living_room',
      widthCm: 400,
      heightCm: 500,
      walls: walls,
      floorFinishType: floorFinishType,
      floorFinishColor: floorFinishColor,
      wallFinishType: wallFinishType,
      wallFinishColor: wallFinishColor,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      userId: 'u1',
    );

FurniturePlacement sofa() => const FurniturePlacement(
      id: 'sofa-1',
      name: 'Sofa',
      iconName: 'sofa',
      x: 0,
      y: 0,
      width: 180,
      height: 90,
    );

AppUser user() => AppUser(
      uid: 'u1',
      email: 'u1@test.dev',
      name: 'Tester',
      role: UserRole.homeowner,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('WalkthroughController', () {
    test('spawns at the room center', () {
      final c = WalkthroughController(design: design());
      expect(c.walker, const Offset(200, 250));
    });

    test('one step moves 30 cm and the heading faces the move', () {
      final c = WalkthroughController(design: design());
      c.move(const Offset(1, 0));
      expect(c.walker, const Offset(230, 250));
      expect(c.heading, 0);
      c.move(const Offset(0, -1));
      expect(c.walker, const Offset(230, 220));
      expect(c.heading, -pi / 2);
    });

    test('cannot walk out of the room rectangle', () {
      final c = WalkthroughController(design: design());
      for (var i = 0; i < 20; i++) {
        c.move(const Offset(1, 0));
      }
      // Last whole 30 cm step from the 200 cm center that keeps the walker
      // radius clear of the 400 cm wall.
      const r = WalkthroughController.walkerRadiusCm;
      final lastStep =
          200 + ((400 - r - 200) / WalkthroughController.stepCm).floor() *
              WalkthroughController.stepCm;
      expect(c.walker.dx, lastStep);
      expect(c.walker.dx,
          lessThanOrEqualTo(400 - WalkthroughController.walkerRadiusCm));
    });

    test('a wall outline stops the walker a radius away from it', () {
      final c = WalkthroughController(design: design(walls: squareWalls));
      for (var i = 0; i < 20; i++) {
        c.move(const Offset(-1, 0));
      }
      // The next step would land on the x=50 wall itself.
      expect(c.walker.dx, 80);
      expect(c.walker.dy, 250);
    });

    test('a fully blocked press still turns in place', () {
      final c = WalkthroughController(design: design(walls: squareWalls));
      for (var i = 0; i < 20; i++) {
        c.move(const Offset(-1, 0));
      }
      final at = c.walker;
      c.move(const Offset(-1, 0));
      expect(c.walker, at);
      expect(c.heading, pi);
    });

    test('placing a sofa at the spawn centers its footprint', () {
      final c = WalkthroughController(design: design());
      final placed = c.place(sofa());
      expect(placed.x, 110);
      expect(placed.y, 205);
      expect(c.furniture, hasLength(1));
    });

    test('a ghost that would sit in a wall settles flush against it', () {
      final c = WalkthroughController(design: design(walls: squareWalls));
      for (var i = 0; i < 20; i++) {
        c.move(const Offset(-1, 0));
      }
      // Centered on the walker the sofa would start at x = -10.
      final g = c.resolveGhost(sofa());
      expect(g.x, 50);
      expect(g.y, 205);
    });

    test('walk steps along the current heading', () {
      final c = WalkthroughController(design: design());
      c.walk(1);
      expect(c.walker, const Offset(230, 250));
      c.turn(pi / 12);
      c.walk(1);
      expect(c.walker.dx, moreOrLessEquals(230 + 30 * cos(pi / 12)));
      expect(c.walker.dy, moreOrLessEquals(250 + 30 * sin(pi / 12)));
    });

    test('turn rotates in place without moving', () {
      final c = WalkthroughController(design: design());
      c.turn(-pi / 12);
      expect(c.heading, -pi / 12);
      expect(c.walker, const Offset(200, 250));
      c.turn(pi / 12);
      expect(c.heading, 0);
    });

    test('zoom clamps to 0.6 – 3.0', () {
      final c = WalkthroughController(design: design());
      c.setZoom(10);
      expect(c.zoom, 3);
      c.setZoom(0.1);
      expect(c.zoom, 0.6);
    });
  });

  group('WalkthroughScreen', () {
    Future<void> pumpWalk(
      WidgetTester tester, {
      String id = 'd1',
      String name = 'Test Walk',
      List<Offset> walls = const [],
      List<Override> overrides = const [],
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            home: WalkthroughScreen(
              design: design(id: id, name: name, walls: walls),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> pumpShowroom(
      WidgetTester tester, {
      List<Override> overrides = const [],
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: const MaterialApp(home: WalkthroughScreen()),
        ),
      );
      await tester.pump();
    }

    List<Override> standardOverrides({_CapturingDatasource? ds}) => [
          currentUserProvider.overrideWithValue(user()),
          roomDesignDatasourceProvider.overrideWithValue(
              ds ?? _CapturingDatasource()),
        ];

    dynamic walkState(WidgetTester tester) =>
        tester.state(find.byType(WalkthroughScreen));

    dynamic sceneState(WidgetTester tester) =>
        tester.state(find.byType(WalkthroughScene));

    testWidgets('arrow up walks forward in the facing direction',
        (tester) async {
      await pumpWalk(tester, overrides: standardOverrides());

      final before = walkState(tester).debugWalker as Offset;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      final after = walkState(tester).debugWalker as Offset;

      expect(after.dx, before.dx + 30);
      expect(after.dy, before.dy);
    });

    testWidgets('the live plan keeps the scanned finishes through the walk',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: standardOverrides(),
          child: MaterialApp(
            home: WalkthroughScreen(
              design: design(
                walls: squareWalls,
                floorFinishType: 'woodPlanks',
                floorFinishColor: 0xFF6B4A32,
                wallFinishType: 'brick',
                wallFinishColor: 0xFFA8442F,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      final d = walkState(tester).debugDesign as RoomDesign;
      expect(d.floorFinishType, 'woodPlanks');
      expect(d.floorFinishColor, 0xFF6B4A32);
      expect(d.wallFinishType, 'brick');
      expect(d.wallFinishColor, 0xFFA8442F);
    });

    testWidgets('arrow right turns in place', (tester) async {
      await pumpWalk(tester, overrides: standardOverrides());

      final before = walkState(tester).debugWalker as Offset;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(walkState(tester).debugWalker as Offset, before);
      expect(walkState(tester).debugHeading as double,
          moreOrLessEquals(WalkthroughController.turnStepRad));
    });

    testWidgets('the pad walks forward and turns', (tester) async {
      await pumpWalk(tester, overrides: standardOverrides());

      final before = walkState(tester).debugWalker as Offset;
      await tester.tap(find.byTooltip('Walk forward'));
      await tester.pump();
      final afterWalk = walkState(tester).debugWalker as Offset;
      expect(afterWalk.dx, before.dx + 30);
      expect(afterWalk.dy, before.dy);

      await tester.tap(find.byTooltip('Turn right'));
      await tester.pump();
      expect(walkState(tester).debugWalker as Offset, afterWalk);
      expect(walkState(tester).debugHeading as double,
          moreOrLessEquals(WalkthroughController.turnStepRad));
    });

    testWidgets('the walk renders the native 3D scene', (tester) async {
      await pumpWalk(tester, overrides: standardOverrides());
      expect(find.byType(WalkthroughScene), findsOneWidget);
      expect(find.byType(Scene3DView), findsOneWidget);
      expect(
          find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is WalkthroughPainter),
          findsNothing);
    });

    testWidgets('the 3D camera rides the walker', (tester) async {
      await pumpWalk(tester, overrides: standardOverrides());

      final before = sceneState(tester).debugLastCamera as ScenePose;
      expect(before.eyeX, moreOrLessEquals(2.0, epsilon: 0.01));
      expect(before.eyeY, moreOrLessEquals(1.5, epsilon: 0.01));
      expect(before.eyeZ, moreOrLessEquals(2.5, epsilon: 0.01));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      final after = sceneState(tester).debugLastCamera as ScenePose;
      expect(after.eyeX, moreOrLessEquals(2.3, epsilon: 0.01),
          reason: 'one 30 cm step along the initial east heading');
      expect(after.eyeZ, moreOrLessEquals(2.5, epsilon: 0.01));
    });

    testWidgets('dragging the 3D view turns and tilts the camera',
        (tester) async {
      await pumpWalk(tester, overrides: standardOverrides());

      await tester.drag(find.byType(Scene3DView), const Offset(-80, 20));
      await tester.pump();

      expect(walkState(tester).debugHeading as double, greaterThan(0),
          reason: 'grab-the-world: dragging left looks right');
      final pose = sceneState(tester).debugLastCamera as ScenePose;
      // The view opens pitched slightly down; the downward drag levelled it.
      expect(pose.targetY - pose.eyeY, greaterThan(-0.07));
    });

    testWidgets('zoom buttons narrow the lens, never move the eye',
        (tester) async {
      await pumpWalk(tester, overrides: standardOverrides());

      final before = sceneState(tester).debugLastCamera as ScenePose;
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();

      final after = sceneState(tester).debugLastCamera as ScenePose;
      expect(after.fovDeg, lessThan(before.fovDeg));
      expect(after.eyeX, before.eyeX);
      expect(after.eyeY, before.eyeY);
      expect(after.eyeZ, before.eyeZ);
    });

    testWidgets('pinching zooms the lens like the zoom buttons', (tester) async {
      await pumpWalk(tester, overrides: standardOverrides());

      final center = tester.getCenter(find.byType(Scene3DView));
      final a = await tester.startGesture(center + const Offset(-30, 0));
      final b = await tester.startGesture(center + const Offset(30, 0));
      await tester.pump();
      await a.moveTo(center + const Offset(-60, 0));
      await b.moveTo(center + const Offset(60, 0));
      await tester.pump();
      await a.up();
      await b.up();
      await tester.pump();

      final pose = sceneState(tester).debugLastCamera as ScenePose;
      expect(pose.fovDeg, lessThan(70),
          reason: 'spreading the fingers zooms in');
    });

    testWidgets('the placement ghost tracks the walker', (tester) async {
      await pumpWalk(tester, overrides: standardOverrides());

      await tester.tap(find.byTooltip('Add furniture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sofa'));
      await tester.pumpAndSettle();

      final first = sceneState(tester).debugLastGhost as FurniturePlacement?;
      expect(first, isNotNull);
      expect(first!.x, moreOrLessEquals(110, epsilon: 0.01),
          reason: '180 cm sofa centered on the 200 cm walker');
      expect(first.y, moreOrLessEquals(205, epsilon: 0.01));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      final walked = sceneState(tester).debugLastGhost as FurniturePlacement?;
      expect(walked!.x, moreOrLessEquals(140, epsilon: 0.01),
          reason: 'the preview follows the walker');
    });

    testWidgets('the painter fallback still turns on drag', (tester) async {
      // iOS has no SceneView — the painter renders and keeps its own look
      // drag, so the flows stay identical across platforms.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await pumpWalk(tester, overrides: standardOverrides());
        expect(
            find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is WalkthroughPainter),
            findsOneWidget);

        await tester.drag(
          find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is WalkthroughPainter),
          const Offset(-80, 0),
        );
        await tester.pump();

        expect(walkState(tester).debugHeading as double, greaterThan(0));
      } finally {
        // Foundation debug vars must be restored before the test ends.
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('pick a piece, then place it at the walker', (tester) async {
      await pumpWalk(tester, overrides: standardOverrides());

      await tester.tap(find.byTooltip('Add furniture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sofa'));
      await tester.pumpAndSettle();

      expect(walkState(tester).debugPlacing as bool, isTrue);

      await tester.tap(find.text('Place'));
      await tester.pump();

      final furniture = walkState(tester).debugFurniture as List;
      expect(furniture, hasLength(1));
      final placed = furniture.single as FurniturePlacement;
      expect(placed.name, 'Sofa');
      expect(placed.x, 110);
      expect(placed.y, 205);

      // Stays in placing mode so several pieces can go down in one run.
      expect(walkState(tester).debugPlacing as bool, isTrue);

      await tester.tap(find.byTooltip('Cancel placement'));
      await tester.pump();
      expect(walkState(tester).debugPlacing as bool, isFalse);
    });

    testWidgets('saving an unsaved plan creates a design with walls and furniture',
        (tester) async {
      final ds = _CapturingDatasource();
      await pumpWalk(
        tester,
        id: '',
        name: 'Walk Me',
        walls: squareWalls,
        overrides: standardOverrides(ds: ds),
      );

      await tester.tap(find.byTooltip('Add furniture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sofa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Place'));
      await tester.pump();

      await tester.tap(find.byTooltip('Save Design'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(ds.ops, ['create']);
      expect(ds.payloads, hasLength(1));
      final payload = ds.payloads.single;
      expect(payload['id'], startsWith('design-'));
      expect(payload['name'], 'Walk Me');
      expect(payload['walls'], [
        [50, 50],
        [350, 50],
        [350, 450],
        [50, 450],
      ]);
      expect(payload['furniture'], hasLength(1));
      expect(payload['widthCm'], 400);
      expect(payload['heightCm'], 500);
      expect(payload['userId'], 'u1');
    });

    testWidgets('saving over an existing design updates it', (tester) async {
      final ds = _CapturingDatasource();
      await pumpWalk(
        tester,
        id: 'd9',
        name: 'Existing Plan',
        overrides: standardOverrides(ds: ds),
      );

      await tester.tap(find.byTooltip('Save Design'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(ds.ops, ['update']);
      expect(ds.payloads.single['id'], 'd9');
      expect(ds.payloads.single['name'], 'Existing Plan');
    });

    testWidgets('saving without a signed-in user shows an error',
        (tester) async {
      await pumpWalk(
        tester,
        overrides: [
          currentUserProvider.overrideWithValue(null),
          roomDesignDatasourceProvider
              .overrideWithValue(_CapturingDatasource()),
        ],
      );

      await tester.tap(find.byTooltip('Save Design'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Please sign in to save designs'), findsOneWidget);
    });

    testWidgets('debugDesign snapshots the live plan', (tester) async {
      await pumpWalk(
        tester,
        walls: squareWalls,
        overrides: standardOverrides(),
      );

      await tester.tap(find.byTooltip('Add furniture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sofa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Place'));
      await tester.pump();

      final snapshot = walkState(tester).debugDesign as RoomDesign;
      expect(snapshot.walls, squareWalls);
      expect(snapshot.widthCm, 400);
      expect(snapshot.heightCm, 500);
      expect(snapshot.furniture, hasLength(1));
      expect(snapshot.name, 'Test Walk');
      expect(snapshot.id, 'd1');
    });

    testWidgets('going back hands the live plan to whoever pushed us',
        (tester) async {
      RoomDesign? popped;
      await tester.pumpWidget(
        ProviderScope(
          overrides: standardOverrides(),
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  popped = await Navigator.push<RoomDesign>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WalkthroughScreen(
                        design: design(walls: squareWalls),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add furniture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sofa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Place'));
      await tester.pump();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(popped, isNotNull);
      expect(popped!.walls, squareWalls);
      expect(popped!.widthCm, 400);
      expect(popped!.heightCm, 500);
      expect(popped!.furniture, hasLength(1));
      expect(popped!.furniture.single.name, 'Sofa');
    });

    testWidgets('no design opens the showroom gallery', (tester) async {
      await pumpShowroom(tester, overrides: standardOverrides());

      expect(walkState(tester).debugInGallery as bool, isTrue);
      expect(find.text('Modern Living Room'), findsOneWidget);
      expect(find.text('Walk this room'), findsOneWidget);
      expect(find.byTooltip('Add furniture'), findsNothing);
      expect(find.byTooltip('Rooms'), findsNothing);
    });

    testWidgets('arrow keys flip between showroom rooms', (tester) async {
      await pumpShowroom(tester, overrides: standardOverrides());

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(walkState(tester).debugGalleryIndex, 1);
      expect(find.text('Cozy Bedroom'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(walkState(tester).debugGalleryIndex, 0);
      expect(find.text('Modern Living Room'), findsOneWidget);
    });

    testWidgets('tapping a room walks it at the room center', (tester) async {
      await pumpShowroom(tester, overrides: standardOverrides());

      await tester.tap(find.text('Walk this room'));
      await tester.pumpAndSettle();

      expect(walkState(tester).debugInGallery as bool, isFalse);
      expect(walkState(tester).debugShowroomId, 'showroom-living');
      expect(walkState(tester).debugWalker as Offset, const Offset(250, 200));
    });

    testWidgets('a showroom walk rides the 3D camera at its spawn',
        (tester) async {
      await pumpShowroom(tester, overrides: standardOverrides());

      await tester.tap(find.text('Walk this room'));
      await tester.pumpAndSettle();

      final pose = sceneState(tester).debugLastCamera as ScenePose;
      expect(pose.eyeX, moreOrLessEquals(2.5, epsilon: 0.01));
      expect(pose.eyeY, moreOrLessEquals(1.5, epsilon: 0.01));
      expect(pose.eyeZ, moreOrLessEquals(2.0, epsilon: 0.01));
    });

    testWidgets('back from a showroom walk returns to the gallery first',
        (tester) async {
      var popCount = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: standardOverrides(),
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  await Navigator.push<RoomDesign>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const WalkthroughScreen()),
                  );
                  popCount++;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Walk this room'));
      await tester.pumpAndSettle();
      expect(walkState(tester).debugInGallery as bool, isFalse);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(popCount, 0);
      expect(walkState(tester).debugInGallery as bool, isTrue);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(popCount, 1);
    });

    testWidgets('leaving my design for the showroom keeps the plan in hand',
        (tester) async {
      RoomDesign? popped;
      await tester.pumpWidget(
        ProviderScope(
          overrides: standardOverrides(),
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  popped = await Navigator.push<RoomDesign>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          WalkthroughScreen(design: design(walls: squareWalls)),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add furniture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sofa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Place'));
      await tester.pumpAndSettle();
      // The snackbar only dismisses if its entrance settled before fake
      // time jumps past the duration; otherwise it lingers and swallows taps.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Rooms'));
      await tester.pumpAndSettle();
      expect(walkState(tester).debugInGallery as bool, isTrue);
      expect(find.text('Back to my design'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(popped, isNotNull);
      expect(popped!.walls, squareWalls);
      expect(popped!.furniture, hasLength(1));
      expect(popped!.furniture.single.name, 'Sofa');
    });

    testWidgets('Back to my design resumes the live plan', (tester) async {
      await pumpWalk(
        tester,
        walls: squareWalls,
        overrides: standardOverrides(),
      );

      await tester.tap(find.byTooltip('Add furniture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sofa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Place'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Rooms'));
      await tester.pumpAndSettle();
      expect(walkState(tester).debugInGallery as bool, isTrue);

      await tester.tap(find.text('Back to my design'));
      await tester.pumpAndSettle();

      expect(walkState(tester).debugInGallery as bool, isFalse);
      expect(walkState(tester).debugShowroomId, isNull);
      expect(walkState(tester).debugFurniture, hasLength(1));
      expect((walkState(tester).debugDesign as RoomDesign).walls, squareWalls);
    });
  });
}
