import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/scanner/data/room_fit.dart'
    show distToRect, furnitureRect;
import 'package:interior_design_recommendation/features/customer/walkthrough/presentation/walkthrough_controller.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

void main() {
  RoomDesign design({
    List<FurniturePlacement> furniture = const [],
    List<Offset> walls = const [],
  }) =>
      RoomDesign(
        id: 'd1',
        name: 'Walk',
        roomType: 'living_room',
        widthCm: 400,
        heightCm: 500,
        furniture: furniture,
        walls: walls,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        userId: 'u1',
      );

  FurniturePlacement sofa({double x = 0, double y = 0, String id = 'sofa-1'}) =>
      FurniturePlacement(
        id: id,
        name: 'Sofa',
        iconName: 'sofa',
        x: x,
        y: y,
        width: 180,
        height: 90,
      );

  test('one press is one 30 cm step (empty-room baseline)', () {
    final ctl = WalkthroughController(design: design());
    expect(ctl.walker, const Offset(200, 250));
    ctl.move(const Offset(1, 0));
    expect(ctl.walker, const Offset(230, 250));
    expect(ctl.heading, 0);
  });

  test('a sofa blocks the walk and a diagonal press slides along it', () {
    final ctl = WalkthroughController(
      design: design(furniture: [sofa(x: 160, y: 100)]),
    );
    expect(ctl.walker, const Offset(200, 250));

    ctl.move(const Offset(0, -1));
    expect(ctl.walker, const Offset(200, 220), reason: 'walks up to the piece');

    ctl.move(const Offset(0, -1));
    expect(ctl.walker, const Offset(200, 220), reason: 'blocked by the sofa');

    ctl.move(const Offset(0.70710678, -0.70710678));
    expect(ctl.walker.dx, closeTo(221.2132, 0.01), reason: 'slides sideways');
    expect(ctl.walker.dy, closeTo(220, 1e-9));
  });

  test('furniture placed at the walker never traps it', () {
    final ctl = WalkthroughController(design: design());
    final placed = ctl.place(sofa(id: 'sofa-new'));
    expect(placed.x, 110, reason: 'footprint centered on the spawn');
    expect(furnitureRect(placed).contains(ctl.walker), isTrue);

    ctl.move(const Offset(1, 0));
    expect(ctl.walker, const Offset(230, 250), reason: 'always free to step out');
  });

  test('spawn avoids furniture instead of materializing inside it', () {
    final ctl = WalkthroughController(
      design: design(furniture: [sofa(x: 110, y: 205)]),
    );
    expect(ctl.walker, isNot(const Offset(200, 250)));
    expect(
      distToRect(ctl.walker, furnitureRect(ctl.furniture.single)),
      greaterThanOrEqualTo(WalkthroughController.walkerRadiusCm),
    );
  });

  test('rugs are walked over, not around', () {
    final rug = FurniturePlacement(
      id: 'rug-1',
      name: 'Rug',
      iconName: 'rug',
      x: 160,
      y: 205,
      width: 160,
      height: 120,
    );
    final ctl = WalkthroughController(design: design(furniture: [rug]));
    expect(ctl.walker, const Offset(200, 250), reason: 'spawn on the rug is fine');

    ctl.move(const Offset(0, -1));
    expect(ctl.walker, const Offset(200, 220), reason: 'no collision with a rug');
  });
}
