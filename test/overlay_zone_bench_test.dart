import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/plane_overlay_math.dart';

List<Offset> _blob(math.Random r, double cx, double cy, double rad, int n) => [
      for (var i = 0; i < n; i++)
        () {
          final a = i / n * 2 * math.pi;
          final rr = rad * (0.8 + 0.4 * r.nextDouble());
          return Offset(cx + rr * math.cos(a), cy + rr * math.sin(a));
        }()
    ];

void main() {
  // Busy device scene (round 1): 14 floor fragments, 10 walls, 12 masks,
  // ARCore outlines up to 64 vertices, all overlapping on a 1080×2400 view.
  test('overlay zone build cost on a busy scene', () {
    final r = math.Random(1);
    final floors = [
      for (var i = 0; i < 14; i++)
        _blob(r, 300 + r.nextDouble() * 500, 1400 + r.nextDouble() * 800,
            300 + r.nextDouble() * 300, 64)
    ];
    final walls = [
      for (var i = 0; i < 10; i++)
        _blob(r, 200 + r.nextDouble() * 700, 500 + r.nextDouble() * 600,
            250, 24)
    ];
    final masks = [
      for (var i = 0; i < 12; i++)
        _blob(r, 200 + r.nextDouble() * 700, 900 + r.nextDouble() * 1200,
            120, 24)
    ];
    for (var i = 0; i < 3; i++) {
      buildOverlayZones(floors: floors, walls: walls, masks: masks);
    }
    const runs = 20;
    final sw = Stopwatch()..start();
    late OverlayZones z;
    for (var i = 0; i < runs; i++) {
      z = buildOverlayZones(floors: floors, walls: walls, masks: masks);
    }
    final perMs = sw.elapsedMicroseconds / runs / 1000;
    // ignore: avoid_print
    print('buildOverlayZones busy scene: ${perMs.toStringAsFixed(2)} ms');
    expect(z.floor, isNotNull);
    expect(z.wall, isNotNull);
  });
}
