import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import '../../../../models/room_design.dart';
import 'camera_rig.dart' show ScenePose;
import 'room_fit.dart' show footprintH, footprintW;

// ── planner screen ↔ world math ──
// Plan cm (x, y) map to world (x/100, 0, y/100). The native camera is a
// standard vertical-FOV perspective (Scene3DPlatformView.setLensProjection),
// so these projections match the rendered scene exactly — selection, dragging
// and overlay handles all run here, no native round-trip needed.

class WorldRay {
  const WorldRay({
    required this.ox,
    required this.oy,
    required this.oz,
    required this.dx,
    required this.dy,
    required this.dz,
  });

  final double ox;
  final double oy;
  final double oz;
  final double dx;
  final double dy;
  final double dz;

  double at(double t, int axis) =>
      axis == 0 ? ox + dx * t : axis == 1 ? oy + dy * t : oz + dz * t;
}

({double rx, double ry, double rz, double ux, double uy, double uz, double fx,
    double fy, double fz, double tanHalf, double aspect})
    _basis(ScenePose pose, Size viewport) {
  var fx = pose.targetX - pose.eyeX;
  var fy = pose.targetY - pose.eyeY;
  var fz = pose.targetZ - pose.eyeZ;
  final fl = math.sqrt(fx * fx + fy * fy + fz * fz);
  if (fl < 1e-9) {
    fx = 0;
    fy = 0;
    fz = -1;
  } else {
    fx /= fl;
    fy /= fl;
    fz /= fl;
  }
  // right = forward × worldUp; up = right × forward.
  var rx = -fz;
  const ry = 0.0;
  var rz = fx;
  final rl = math.sqrt(rx * rx + rz * rz);
  if (rl < 1e-9) {
    rx = 1;
    rz = 0;
  } else {
    rx /= rl;
    rz /= rl;
  }
  final ux = ry * fz - rz * fy;
  final uy = rz * fx - rx * fz;
  final uz = rx * fy - ry * fx;
  final aspect = viewport.height == 0 ? 1.0 : viewport.width / viewport.height;
  final tanHalf = math.tan(pose.fovDeg * math.pi / 360.0);
  return (
    rx: rx,
    ry: ry,
    rz: rz,
    ux: ux,
    uy: uy,
    uz: uz,
    fx: fx,
    fy: fy,
    fz: fz,
    tanHalf: tanHalf,
    aspect: aspect,
  );
}

WorldRay rayThroughScreenPoint(ScenePose pose, Size viewport, Offset screen) {
  final b = _basis(pose, viewport);
  final ndcX = viewport.width == 0 ? 0.0 : (screen.dx / viewport.width) * 2 - 1;
  final ndcY =
      viewport.height == 0 ? 0.0 : 1 - (screen.dy / viewport.height) * 2;
  final sx = ndcX * b.tanHalf * b.aspect;
  final sy = ndcY * b.tanHalf;
  var dx = b.fx + b.rx * sx + b.ux * sy;
  var dy = b.fy + b.ry * sx + b.uy * sy;
  var dz = b.fz + b.rz * sx + b.uz * sy;
  final dl = math.sqrt(dx * dx + dy * dy + dz * dz);
  dx /= dl;
  dy /= dl;
  dz /= dl;
  return WorldRay(
      ox: pose.eyeX,
      oy: pose.eyeY,
      oz: pose.eyeZ,
      dx: dx,
      dy: dy,
      dz: dz);
}

Offset? projectWorldPoint(
    ScenePose pose, Size viewport, double xM, double yM, double zM) {
  final b = _basis(pose, viewport);
  final px = xM - pose.eyeX;
  final py = yM - pose.eyeY;
  final pz = zM - pose.eyeZ;
  final vz = px * b.fx + py * b.fy + pz * b.fz;
  if (vz <= 0.05) return null;
  final vx = px * b.rx + py * b.ry + pz * b.rz;
  final vy = px * b.ux + py * b.uy + pz * b.uz;
  final ndcX = vx / (vz * b.tanHalf * b.aspect);
  final ndcY = vy / (vz * b.tanHalf);
  return Offset((ndcX + 1) / 2 * viewport.width, (1 - ndcY) / 2 * viewport.height);
}

// Screen polygon of a world-space polygon, clipped against the near plane so
// overlays that hang behind the first-person camera (a ghost at your feet)
// still draw their visible part. Empty when fully behind.
List<Offset> projectWorldPolyNear(ScenePose pose, Size viewport,
    List<({double x, double y, double z})> poly) {
  if (poly.isEmpty) return const [];
  final b = _basis(pose, viewport);
  final cam = <({double x, double y, double z})>[];
  for (final p in poly) {
    final px = p.x - pose.eyeX;
    final py = p.y - pose.eyeY;
    final pz = p.z - pose.eyeZ;
    cam.add((
      x: px * b.rx + py * b.ry + pz * b.rz,
      y: px * b.ux + py * b.uy + pz * b.uz,
      z: px * b.fx + py * b.fy + pz * b.fz,
    ));
  }
  const near = 0.05;
  final clipped = <({double x, double y, double z})>[];
  for (var i = 0; i < cam.length; i++) {
    final a = cam[i];
    final c = cam[(i + 1) % cam.length];
    final aIn = a.z >= near;
    final cIn = c.z >= near;
    if (aIn) clipped.add(a);
    if (aIn != cIn) {
      final t = (near - a.z) / (c.z - a.z);
      clipped.add((
        x: a.x + (c.x - a.x) * t,
        y: a.y + (c.y - a.y) * t,
        z: near,
      ));
    }
  }
  return [
    for (final p in clipped)
      Offset((p.x / (p.z * b.tanHalf * b.aspect) + 1) / 2 * viewport.width,
          (1 - p.y / (p.z * b.tanHalf)) / 2 * viewport.height),
  ];
}

// Floor hit in plan cm, or null when the ray misses y = 0.
Offset? floorPointAt(ScenePose pose, Size viewport, Offset screen) {
  final ray = rayThroughScreenPoint(pose, viewport, screen);
  if (ray.dy >= -1e-6) return null;
  final t = -ray.oy / ray.dy;
  if (t <= 0) return null;
  return Offset(ray.at(t, 0) * 100, ray.at(t, 2) * 100);
}

double? rayBoxHit(
  WorldRay ray, {
  required double centerXCm,
  required double centerZCm,
  required double topYM,
  required double halfWidthM,
  required double halfDepthM,
  required double yawRad,
  double bottomYM = 0,
}) {
  final c = math.cos(-yawRad);
  final s = math.sin(-yawRad);
  final ox = ray.ox - centerXCm / 100;
  final oz = ray.oz - centerZCm / 100;
  final lox = ox * c - oz * s;
  final loz = ox * s + oz * c;
  final ldx = ray.dx * c - ray.dz * s;
  final ldz = ray.dx * s + ray.dz * c;

  var tMin = 0.0;
  var tMax = double.infinity;
  bool slabs(double p, double d, double lo, double hi) {
    if (d.abs() < 1e-9) return p >= lo && p <= hi;
    var t0 = (lo - p) / d;
    var t1 = (hi - p) / d;
    if (t0 > t1) {
      final tmp = t0;
      t0 = t1;
      t1 = tmp;
    }
    tMin = math.max(tMin, t0);
    tMax = math.min(tMax, t1);
    return tMin <= tMax;
  }

  if (!slabs(lox, ldx, -halfWidthM, halfWidthM)) return null;
  if (!slabs(ray.oy, ray.dy, bottomYM, topYM)) return null;
  if (!slabs(loz, ldz, -halfDepthM, halfDepthM)) return null;
  return tMin;
}

// Id of the placement under the screen point — nearest box along the ray.
String? pickPlacementId(
  ScenePose pose,
  Size viewport,
  Offset screen,
  List<FurniturePlacement> items, {
  required double Function(FurniturePlacement) heightMOf,
}) {
  final ray = rayThroughScreenPoint(pose, viewport, screen);
  String? bestId;
  var bestT = double.infinity;
  for (final f in items) {
    final t = rayBoxHit(
      ray,
      centerXCm: f.x + footprintW(f) / 2,
      centerZCm: f.y + footprintH(f) / 2,
      bottomYM: (f.elevationCm ?? 0) / 100,
      topYM: (f.elevationCm ?? 0) / 100 + heightMOf(f),
      halfWidthM: f.width / 200,
      halfDepthM: f.height / 200,
      yawRad: -f.rotation * math.pi / 180.0,
    );
    if (t != null && t < bestT) {
      bestT = t;
      bestId = f.id;
    }
  }
  return bestId;
}
