import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'plane_overlay_math.dart';

// Manhattan snapping: indoor walls meet at right angles, but ARCore planes
// and cloud RANSAC fits scatter ±5–10° (device round 3: four fits of ONE
// wall at 168–178°), so merged walls tilted and corners never closed at
// 90°. The room's axis is learned from the first solid wall, refined
// briefly while agreeing walls arrive, then frozen so painted walls stay
// put (hard-stick). Walls within [tolRad] of the axis or its
// perpendicular are rotated about their own vertical centre line onto it;
// genuinely angled walls are left as measured.
class RoomAxis {
  RoomAxis({
    this.tolRad = 15 * math.pi / 180,
    this.seedMinAreaM2 = 1.5,
    this.refineSteps = 30,
    this.refineAlpha = 0.1,
  });

  final double tolRad;
  final double seedMinAreaM2;
  final int refineSteps;
  final double refineAlpha;

  double? _axis;
  int _refined = 0;

  double? get axis => _axis;

  void reset() {
    _axis = null;
    _refined = 0;
  }

  static double wrapQuarter(double a) {
    const q = math.pi / 2;
    var r = (a + q / 2) % q;
    if (r < 0) r += q;
    return r - q / 2;
  }

  void observe(List<PlaneQuad> walls) {
    if (walls.isEmpty) return;
    if (_axis == null) {
      PlaneQuad? best;
      var bestArea = 0.0;
      for (final w in walls) {
        final a = w.extentX * w.extentZ;
        if (a > bestArea) {
          bestArea = a;
          best = w;
        }
      }
      if (best == null || bestArea < seedMinAreaM2) return;
      _axis = wrapQuarter(best.yaw);
      return;
    }
    if (_refined >= refineSteps) return;
    var sum = 0.0;
    var weight = 0.0;
    for (final w in walls) {
      final r = wrapQuarter(w.yaw - _axis!);
      if (r.abs() > tolRad) continue;
      final a = w.extentX * w.extentZ;
      sum += r * a;
      weight += a;
    }
    if (weight <= 0) return;
    _axis = wrapQuarter(_axis! + refineAlpha * sum / weight);
    _refined++;
  }

  List<PlaneQuad> snap(List<PlaneQuad> walls) {
    final ax = _axis;
    if (ax == null) return walls;
    return [
      for (final w in walls)
        () {
          final r = wrapQuarter(w.yaw - ax);
          return r.abs() > tolRad ? w : rotateWallYaw(w, -r);
        }()
    ];
  }
}

// Turns a vertical quad about its own vertical centre line by [delta]
// (yaw convention: normal = (sin yaw, 0, cos yaw)). Heights are untouched.
PlaneQuad rotateWallYaw(PlaneQuad w, double delta) {
  if (delta == 0) return w;
  final c = math.cos(delta);
  final s = math.sin(delta);
  Vector3 rot(Vector3 p) {
    final dx = p.x - w.center.x;
    final dz = p.z - w.center.z;
    return Vector3(
      w.center.x + dx * c + dz * s,
      p.y,
      w.center.z - dx * s + dz * c,
    );
  }

  return PlaneQuad(
    center: w.center,
    yaw: w.yaw + delta,
    extentX: w.extentX,
    extentZ: w.extentZ,
    vertical: w.vertical,
    kind: w.kind,
    polygon: [for (final p in w.polygon) rot(p)],
  );
}
