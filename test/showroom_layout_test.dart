import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/glb_bounds.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/room_finishes.dart';
import 'package:interior_design_recommendation/features/customer/scanner/data/room_fit.dart';
import 'package:interior_design_recommendation/features/customer/walkthrough/data/showroom_designs.dart';
import 'package:interior_design_recommendation/features/customer/walkthrough/presentation/walkthrough_controller.dart';
import 'package:interior_design_recommendation/models/room_design.dart';

const _ceilingCm = 270.0;

void main() {
  test('every showroom room spawns on clear floor near its centre', () {
    for (final room in showroomRooms) {
      final d = room.design;
      final ctl = WalkthroughController(design: d);
      final centre = Offset(d.widthCm / 2, d.heightCm / 2);
      expect((ctl.walker - centre).distance, lessThanOrEqualTo(150),
          reason: '${room.name}: spawn wandered too far from the centre');
      for (final f in d.furniture) {
        if (f.isRaised || (f.heightCm ?? 80) < 30 || f.iconName == 'rug') {
          continue;
        }
        expect(distToRect(ctl.walker, furnitureRect(f)),
            greaterThanOrEqualTo(WalkthroughController.walkerRadiusCm - 0.01),
            reason: '${room.name}: walker starts inside ${f.name}');
      }
    }
  });

  test('every showroom piece sits inside its room', () {
    for (final room in showroomRooms) {
      final d = room.design;
      for (final f in d.furniture) {
        expect(
          placementFits(f, roomW: d.widthCm, roomH: d.heightCm, walls: d.walls),
          isTrue,
          reason: '${room.name}: ${f.name} pokes through a wall',
        );
      }
    }
  });

  test('every showroom room has its own floor and wall finish', () {
    final looks = <String>{};
    for (final room in showroomRooms) {
      final d = room.design;
      expect(d.floorFinishType, isNotNull, reason: '${room.name}: no floor');
      expect(d.wallFinishType, isNotNull, reason: '${room.name}: no walls');
      final sel = finishSelectionFrom(d);
      expect(sel.floorType.name, d.floorFinishType,
          reason: '${room.name}: unknown floor finish name');
      expect(sel.wallType.name, d.wallFinishType,
          reason: '${room.name}: unknown wall finish name');
      looks.add('${d.floorFinishType}/${d.floorFinishColor}/'
          '${d.wallFinishType}/${d.wallFinishColor}');
    }
    expect(looks, hasLength(showroomRooms.length),
        reason: 'each room should look different');
  });

  test('raised pieces stay under the ceiling; wall art touches a wall', () {
    for (final room in showroomRooms) {
      final d = room.design;
      for (final f in d.furniture) {
        if (!f.isRaised) continue;
        expect(f.heightCm, isNotNull, reason: '${room.name}: ${f.name}');
        expect(f.elevationCm! + f.heightCm!, lessThanOrEqualTo(_ceilingCm + 0.5),
            reason: '${room.name}: ${f.name} goes through the ceiling');
        final thin = math.min(f.width, f.height) < 6;
        if (!thin) continue;
        final r = furnitureRect(f);
        final onWall = d.walls.length >= 3 &&
            List.generate(d.walls.length, (i) {
              final a = d.walls[i];
              final b = d.walls[(i + 1) % d.walls.length];
              return [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]
                  .any((c) => distToSegment(c, a, b) < 1.0);
            }).any((x) => x);
        expect(onWall, isTrue, reason: '${room.name}: ${f.name} floats off the wall');
      }
    }
  });

  test('every showroom model and photo exists, and decor models match '
      'their stated size', () {
    for (final room in showroomRooms) {
      for (final f in room.design.furniture) {
        final img = f.imageAsset;
        if (img != null) {
          expect(File(img).existsSync(), isTrue, reason: '${f.name}: $img');
        }
        final m = f.modelUrl;
        if (m == null) continue;
        expect(File(m).existsSync(), isTrue, reason: '${f.name}: $m');
        if (f.heightCm == null) continue;
        final b = GlbBounds.sceneFromGlbBytes(File(m).readAsBytesSync());
        // Stated size must match the mesh (either footprint orientation) —
        // the scene stretches each axis to it.
        double close(double a, double b) => math.max(a, b) / math.min(a, b);
        final hr = close(b.heightM * 100, f.heightCm!);
        expect(hr, lessThan(1.15), reason: '${room.name}: ${f.name} height');
        final w = b.widthM * 100, dp = b.depthM * 100;
        final same = math.max(close(w, f.width), close(dp, f.height));
        final swapped = math.max(close(w, f.height), close(dp, f.width));
        expect(math.min(same, swapped), lessThan(1.15),
            reason: '${room.name}: ${f.name} footprint');
      }
    }
  });

  test('showroom designs round-trip through JSON with decor intact', () {
    for (final room in showroomRooms) {
      final back = RoomDesign.fromJson(room.design.toJson());
      expect(back.furniture.length, room.design.furniture.length);
      for (var i = 0; i < back.furniture.length; i++) {
        final a = room.design.furniture[i], b = back.furniture[i];
        expect(b.elevationCm, a.elevationCm);
        expect(b.modelUrl, a.modelUrl);
        expect(b.heightCm, a.heightCm);
      }
      expect(back.floorFinishType, room.design.floorFinishType);
      expect(back.wallFinishColor, room.design.wallFinishColor);
    }
  });
}
