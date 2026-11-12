import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/scanner/data/room_fit.dart'
    show placementFits;
import 'package:interior_design_recommendation/features/customer/walkthrough/data/showroom_designs.dart';
import 'package:interior_design_recommendation/features/customer/walkthrough/presentation/walkthrough_controller.dart';

void main() {
  // Curation contract: showroom centers stay clear so a walk starts at the
  // exact room center, and every piece sits fully inside its wall ring.
  test('every showroom room spawns at its center and fits its furniture', () {
    for (final room in showroomRooms) {
      final d = room.design;
      final ctl = WalkthroughController(design: d);
      expect(
        ctl.walker.dx,
        closeTo(d.widthCm / 2, 1e-9),
        reason: '${room.name}: spawn x drifted from the room center',
      );
      expect(
        ctl.walker.dy,
        closeTo(d.heightCm / 2, 1e-9),
        reason: '${room.name}: spawn y drifted from the room center',
      );
      for (final f in d.furniture) {
        expect(
          placementFits(f, roomW: d.widthCm, roomH: d.heightCm, walls: d.walls),
          isTrue,
          reason: '${room.name}: ${f.name} pokes through a wall',
        );
      }
    }
  });
}
