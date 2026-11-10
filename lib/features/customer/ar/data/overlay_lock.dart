import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:vector_math/vector_math_64.dart';

import 'plane_overlay_math.dart';

// Per-id overlay geometry that has agreed across rebuilds and then
// frozen: while locked, live ARCore refits and pose jitter cannot drag
// the painted plane off its detected position. Unlocked it tracks the
// latest observation; a deviating observation re-baselines and restarts
// the streak.
class OverlayLock {
  int agree = 0;
  bool locked = false;
  double centerX = 0;
  double centerY = 0;
  double centerZ = 0;
  double yaw = 0;
  double extentX = 0;
  double extentZ = 0;
  List<Vector3> polygon = const [];

  // Baseline stores raw telemetry; the lock moment passes the paint-time
  // smoothY/ring so the frozen values match what was on screen.
  void adopt(ARPlaneInfo p, {double? centerY, List<Vector3>? polygon}) {
    centerX = p.centerX;
    this.centerY = centerY ?? p.centerY;
    centerZ = p.centerZ;
    yaw = p.yaw;
    extentX = p.extentX;
    extentZ = p.extentZ;
    this.polygon = polygon ?? polygonFromFlat(p.polygon);
  }

  // One agreeing observation: every scalar within 5 cm / 0.05 rad of the
  // ANCHORED baseline and the outline ring matching vertex-for-vertex.
  // Agreeing frames never re-baseline, so pairwise drift cannot walk the
  // baseline ~0.05 m per frame into a wrong freeze. Yaw wraps so a ±π
  // seam crossing reads as agreement, not a reset.
  bool agrees(ARPlaneInfo p) {
    if ((p.centerX - centerX).abs() > 0.05 ||
        (p.centerZ - centerZ).abs() > 0.05 ||
        (p.centerY - centerY).abs() > 0.05 ||
        wrapYaw(p.yaw - yaw).abs() > 0.05 ||
        (p.extentX - extentX).abs() > 0.05 ||
        (p.extentZ - extentZ).abs() > 0.05) {
      return false;
    }
    final ring = polygonFromFlat(p.polygon);
    if (ring.length != polygon.length) return false;
    for (var i = 0; i < ring.length; i++) {
      if ((ring[i] - polygon[i]).length > 0.05) return false;
    }
    return true;
  }

  // Unlock tolerances mirror PlaneMemory's re-fit gates: 0.15 m on center
  // or any vertex, 0.15 rad on yaw — evaluated before the ring checks so
  // empty-polygon synthetics can unlock on rotation — 0.4 m extent change
  // in EITHER direction, or a topology change whose centroid also moved:
  // all proof the plane is a different surface, not pose noise.
  bool deviates(ARPlaneInfo p) {
    final dx = p.centerX - centerX;
    final dz = p.centerZ - centerZ;
    if (dx * dx + dz * dz > 0.15 * 0.15) return true;
    if ((p.centerY - centerY).abs() > 0.15) return true;
    if (wrapYaw(p.yaw - yaw).abs() > 0.15) return true;
    if ((extentX - p.extentX).abs() > 0.4 ||
        (extentZ - p.extentZ).abs() > 0.4) {
      return true;
    }
    final ring = polygonFromFlat(p.polygon);
    if (ring.length == polygon.length) {
      for (var i = 0; i < ring.length; i++) {
        if ((ring[i] - polygon[i]).length > 0.15) return true;
      }
      return false;
    }
    if (ring.isEmpty || polygon.isEmpty) return false;
    return (_ringCentroid(ring) - _ringCentroid(polygon)).length > 0.15;
  }

  // Grows the stability streak for one painted observation; four fresh
  // consecutive agreements freeze the id on the paint-time geometry.
  // fresh=false (byte-identical cached telemetry for >1 s) is never lock
  // evidence — a panned-in segment must earn four fresh frames. Returns
  // true exactly when this call locks.
  bool advance(ARPlaneInfo p,
      {required List<Vector3> ring, required double smoothY}) {
    if (p.id == 0 || locked || !p.fresh) return false;
    if (agree == 0 || !agrees(p)) {
      adopt(p);
      agree = 1;
    } else {
      agree++;
    }
    if (agree >= 4) {
      locked = true;
      adopt(p, centerY: smoothY, polygon: ring);
      return true;
    }
    return false;
  }

  Vector3 _ringCentroid(List<Vector3> ring) {
    var x = 0.0, y = 0.0, z = 0.0;
    for (final v in ring) {
      x += v.x;
      y += v.y;
      z += v.z;
    }
    final n = ring.length.toDouble();
    return Vector3(x / n, y / n, z / n);
  }
}
