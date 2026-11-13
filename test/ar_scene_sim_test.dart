import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/plane_overlay_math.dart';
import 'package:vector_math/vector_math_64.dart';

import 'support/ar_scene_sim.dart';

const seeds = [1, 2, 3, 4, 5, 6, 7, 8];

// Level-2 balcony: slab 1.4 m under the phone, glass railing along z = 1.6,
// building facade at z = 0, level-1 courtyard one storey down.
List<SimSurface> balconyScene({double dropM = 3.0}) => [
      SimSurface.floor(id: 1, y: -1.4, cx: 0, cz: 0.8, ex: 3.0, ez: 1.6),
      SimSurface.floor(
          id: 2, y: -1.4 - dropM, cx: 0, cz: 5.6, ex: 10, ez: 8),
      SimSurface.wall(
          id: 10, cx: 0, cz: 1.6, bottomY: -1.4, height: 1.05,
          width: 3.0, yaw: math.pi),
      SimSurface.wall(
          id: 11, cx: 0, cz: 0, bottomY: -1.4, height: 2.6,
          width: 3.0, yaw: 0),
    ];

// 4 × 5 m room, floor 1.45 m under the phone, walls 2.6 m tall.
List<SimSurface> roomScene() => [
      SimSurface.floor(id: 1, y: -1.45, cx: 0, cz: 0, ex: 4, ez: 5),
      SimSurface.wall(
          id: 10, cx: 0, cz: -2.5, bottomY: -1.45, height: 2.6,
          width: 4, yaw: 0),
      SimSurface.wall(
          id: 11, cx: 0, cz: 2.5, bottomY: -1.45, height: 2.6,
          width: 4, yaw: math.pi),
      SimSurface.wall(
          id: 12, cx: -2, cz: 0, bottomY: -1.45, height: 2.6,
          width: 5, yaw: math.pi / 2),
      SimSurface.wall(
          id: 13, cx: 2, cz: 0, bottomY: -1.45, height: 2.6,
          width: 5, yaw: -math.pi / 2),
    ];

void main() {
  group('mock AR walk — balcony over level 1', () {
    for (final seed in seeds) {
      test('seed $seed: floor stays on the balcony, courtyard never paints',
          () {
        final sim = ArSceneSim(surfaces: balconyScene(), seed: seed);
        final frames = sim.walk(
            swayPath(Vector3(-1, 0, 0.3), Vector3(1, 0, 1.0), 120));
        for (var i = 0; i < frames.length; i++) {
          final f = frames[i];
          expect(f.zones[2], isNot(OverlayZoneKind.floor),
              reason: 'frame $i painted the courtyard as floor');
          if (i < sim.poseMissingFrames) continue;
          // From the first pose: either still scanning (null) or the
          // balcony — never the courtyard, not even for one frame.
          if (f.floorY != null) {
            expect(f.floorY, closeTo(-1.4, 0.06),
                reason: 'frame $i floorY=${f.floorY}');
          }
          if (i < 10) continue;
          expect(f.floorY, isNotNull, reason: 'frame $i still no floor');
          expect(f.trusted, isTrue, reason: 'frame $i');
          expect(f.zones[1], OverlayZoneKind.floor,
              reason: 'frame $i balcony zone=${f.zones[1]}');
        }
      });
    }

    test('railing paints as a wall that stands on the balcony slab', () {
      final sim = ArSceneSim(surfaces: balconyScene(), seed: 3);
      final last = sim
          .walk(swayPath(Vector3(-1, 0, 0.3), Vector3(1, 0, 1.0), 60))
          .last;
      final railing = paintedWallFor(last.walls, balconyScene()[2]);
      expect(railing, isNotNull);
      final bottom = railing!.center.y - railing.extentZ / 2;
      expect(bottom, closeTo(-1.4, 0.06),
          reason: 'the railing must not reach down to the courtyard');
    });

    test('a two-storey drop behaves the same', () {
      final sim = ArSceneSim(surfaces: balconyScene(dropM: 6.0), seed: 4);
      final frames = sim.walk(
          swayPath(Vector3(-1, 0, 0.3), Vector3(1, 0, 1.0), 80));
      expect(frames.last.floorY, closeTo(-1.4, 0.06));
      expect(frames.any((f) => f.zones[2] == OverlayZoneKind.floor), isFalse);
    });

    test('known gap: a terrace 0.9 m below is still taken as the floor', () {
      final sim = ArSceneSim(surfaces: balconyScene(dropM: 0.9), seed: 2);
      final frames = sim.walk(
          swayPath(Vector3(-1, 0, 0.3), Vector3(1, 0, 1.0), 80));
      expect(frames.last.floorY, closeTo(-1.4, 0.06));
    }, skip: 'height alone cannot tell a 0.9 m drop from a bed top — '
        'needs a camera-trajectory signal');
  });

  group('mock AR walk — room corners', () {
    for (final seed in seeds) {
      test('seed $seed: every painted corner closes within 8 cm', () {
        final scene = roomScene();
        final sim = ArSceneSim(surfaces: scene, seed: seed);
        final last = sim
            .walk(swayPath(Vector3(-1, 0, 1), Vector3(1, 0, -1), 80))
            .last;
        final walls = scene.where((s) => s.vertical).toList();
        final corners = [
          (Vector3(-2, 0, -2.5), walls[0], walls[2]),
          (Vector3(2, 0, -2.5), walls[0], walls[3]),
          (Vector3(-2, 0, 2.5), walls[1], walls[2]),
          (Vector3(2, 0, 2.5), walls[1], walls[3]),
        ];
        for (final (corner, w1, w2) in corners) {
          for (final w in [w1, w2]) {
            final q = paintedWallFor(last.walls, w);
            expect(q, isNotNull, reason: 'wall ${w.id} not painted');
            expect(endErrorAt(q!, corner), lessThan(0.08),
                reason: 'wall ${w.id} end misses corner $corner');
          }
        }
      });
    }

    test('painted wall bases sit on the floor', () {
      final sim = ArSceneSim(surfaces: roomScene(), seed: 5);
      final last =
          sim.walk(swayPath(Vector3(-1, 0, 1), Vector3(1, 0, -1), 60)).last;
      for (final q in last.walls) {
        expect(q.center.y - q.extentZ / 2, closeTo(-1.45, 0.06));
      }
    });
  });
}
