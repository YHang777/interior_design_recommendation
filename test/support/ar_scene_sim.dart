import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/cloud_zone_builder.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/plane_memory.dart';
import 'package:interior_design_recommendation/features/customer/ar/data/plane_overlay_math.dart';
import 'package:vector_math/vector_math_64.dart';

// ── Mock AR world ──
// A deterministic stand-in for ARCore on a phone: ground-truth surfaces,
// a camera walk, and per-frame telemetry with the defects seen on device —
// planes that grow as they are observed, fitted floor heights sitting a few
// cm high, wall runs that stop short of (or poke past) corners, yaw wobble,
// depth points with noise, and no camera pose for the first frames.

class SimSurface {
  SimSurface.floor({
    required this.id,
    required double y,
    required double cx,
    required double cz,
    required double ex,
    required double ez,
  })  : vertical = false,
        center = Vector3(cx, y, cz),
        width = ex,
        depthOrHeight = ez,
        yaw = 0;

  SimSurface.wall({
    required this.id,
    required double cx,
    required double cz,
    required double bottomY,
    required double height,
    required this.width,
    required this.yaw,
  })  : vertical = true,
        center = Vector3(cx, bottomY + height / 2, cz),
        depthOrHeight = height;

  final int id;

  final bool vertical;

  final Vector3 center;

  final double width;

  final double depthOrHeight;

  final double yaw;

  Vector3 get along => Vector3(math.cos(yaw), 0, -math.sin(yaw));

  Vector3 nearestPoint(Vector3 p) {
    if (!vertical) {
      return Vector3(
        p.x.clamp(center.x - width / 2, center.x + width / 2),
        center.y,
        p.z.clamp(center.z - depthOrHeight / 2, center.z + depthOrHeight / 2),
      );
    }
    final u = along;
    final t = (p - center).dot(u).clamp(-width / 2, width / 2);
    final y = p.y.clamp(
        center.y - depthOrHeight / 2, center.y + depthOrHeight / 2);
    final q = center + u * t;
    return Vector3(q.x, y, q.z);
  }

  (Vector3, Vector3) get wallEnds =>
      (center - along * (width / 2), center + along * (width / 2));
}

class SimFrame {
  SimFrame({
    required this.camera,
    required this.floorY,
    required this.trusted,
    required this.zones,
    required this.walls,
    required this.planes,
  });

  final Vector3 camera;

  final double? floorY;

  final bool trusted;

  final Map<int, OverlayZoneKind> zones;

  final List<PlaneQuad> walls;

  final List<ARPlaneInfo> planes;
}

class ArSceneSim {
  ArSceneSim({
    required this.surfaces,
    this.seed = 7,
    this.viewRangeM = 6.0,
    this.poseMissingFrames = 3,
    this.floorFitBiasM = 0.03,
    this.wallEndErrorM = (-0.25, 0.6),
  }) : _rng = math.Random(seed) {
    for (final s in surfaces.where((s) => s.vertical)) {
      _endError[s.id] = (_uniform(wallEndErrorM), _uniform(wallEndErrorM));
    }
  }

  final List<SimSurface> surfaces;

  final int seed;

  final double viewRangeM;

  // Frames at the start with planes but no camera pose — the window in
  // which a lower storey could lock floorY on device.
  final int poseMissingFrames;

  final double floorFitBiasM;

  // Per wall end: positive = run stops short of the true end, negative =
  // pokes past it. Fixed per wall for the whole walk, like ARCore.
  final (double, double) wallEndErrorM;

  final math.Random _rng;

  final memory = PlaneMemory();

  final _seen = <int, int>{};

  final _endError = <int, (double, double)>{};

  int _frame = 0;

  double _uniform((double, double) r) => r.$1 + _rng.nextDouble() * (r.$2 - r.$1);

  double _noise(double amp) => (_rng.nextDouble() * 2 - 1) * amp;

  bool _visible(SimSurface s, Vector3 cam) =>
      (s.nearestPoint(cam) - cam).length <= viewRangeM;

  ARPlaneInfo _observe(SimSurface s) {
    final n = _seen.update(s.id, (v) => v + 1, ifAbsent: () => 1);
    final grow = math.min(1.0, 0.35 + 0.08 * n);
    if (!s.vertical) {
      return ARPlaneInfo(
        id: s.id,
        planeType: 1,
        centerX: s.center.x + _noise(0.01),
        centerY: s.center.y + floorFitBiasM + _noise(0.012),
        centerZ: s.center.z + _noise(0.01),
        extentX: s.width * grow,
        extentZ: s.depthOrHeight * grow,
      );
    }
    final (shortA, shortB) = _endError[s.id]!;
    final full = s.width - shortA - shortB;
    final w = math.max(0.5, full * grow);
    final u = s.along;
    final c = s.center + u * ((shortA - shortB) / 2);
    return ARPlaneInfo(
      id: s.id,
      planeType: 2,
      centerX: c.x + _noise(0.01),
      centerY: s.center.y + _noise(0.01),
      centerZ: c.z + _noise(0.01),
      extentX: w,
      extentZ: s.depthOrHeight * math.min(1.0, grow + 0.2),
      yaw: s.yaw + _noise(0.02),
    );
  }

  List<double> _depthPoints(Vector3 cam) {
    final pts = <double>[];
    for (final s in surfaces) {
      if (s.vertical || !_visible(s, cam)) continue;
      for (var i = 0; i < 60; i++) {
        final x = s.center.x + _noise(s.width / 2);
        final z = s.center.z + _noise(s.depthOrHeight / 2);
        if ((Vector3(x, s.center.y, z) - cam).length > 5.0) continue;
        pts.addAll([x, s.center.y + _noise(0.02), z]);
      }
    }
    return pts;
  }

  // One AR screen tick: pose → memory → probe → overlay zones → wall paint,
  // in the same order and with the same helpers as _rebuildPlaneOverlay.
  SimFrame step(Vector3 cam) {
    final hasPose = _frame++ >= poseMissingFrames;
    final planes = [
      for (final s in surfaces)
        if (_visible(s, cam)) _observe(s),
    ];
    if (hasPose) memory.noteCameraY(cam.y);
    memory.ingest(planes);
    final fy0 = memory.floorY;
    if (hasPose && fy0 != null) {
      final probe = floorProbeCandidate(points: _depthPoints(cam), refY: fy0);
      if (probe != null) memory.noteFloorYCandidate(probe);
    }
    final floorY = memory.floorY;
    final trusted = memory.floorYRenderTrusted;
    final cameraY = hasPose ? cam.y : null;
    final lowest = overlayLowestPlaneY(
      planes: planes,
      liveIds: {for (final p in planes) p.id},
      floorY: floorY,
      cameraY: cameraY,
    );
    final corroborated = memory.floorYCorroborated();
    final refY = (trusted && floorY != null)
        ? trustedOverlayRefY(
            floorY: floorY,
            lowestPlaneY: lowest,
            corroborateFloorY: corroborated)
        : null;
    final zones = <int, OverlayZoneKind>{};
    final wallQuads = <PlaneQuad>[];
    double? minFloorPaintY;
    for (final p in planes) {
      final z = overlayZoneOf(
        planeType: p.planeType,
        centerY: p.centerY,
        floorY: floorY,
        cameraY: cameraY,
        lowestPlaneY: lowest,
        floorYTrusted: trusted,
        corroborateFloorY: corroborated,
        floorYCameraBacked: memory.floorYCameraBacked,
        extentX: p.extentX,
        extentZ: p.extentZ,
      );
      zones[p.id] = z;
      if (z == OverlayZoneKind.floor) {
        final y = refY ?? p.centerY;
        if (minFloorPaintY == null || y < minFloorPaintY) minFloorPaintY = y;
      }
      if (z == OverlayZoneKind.wall) {
        wallQuads.add(PlaneQuad(
          center: Vector3(p.centerX, p.centerY, p.centerZ),
          yaw: p.yaw,
          extentX: p.extentX,
          extentZ: p.extentZ,
          vertical: true,
          kind: PlaneQuadKind.wall,
        ));
      }
    }
    final baseY = refY ?? minFloorPaintY ?? floorY;
    final walls = baseY == null
        ? wallQuads
        : joinWallCorners(mergeWallQuads(capWallQuads(
            [for (final w in wallQuads) withWallBaseAt(w, refY: baseY)], 20)));
    return SimFrame(
      camera: cam,
      floorY: floorY,
      trusted: trusted,
      zones: zones,
      walls: walls,
      planes: planes,
    );
  }

  List<SimFrame> walk(List<Vector3> path) => [for (final c in path) step(c)];
}

// Camera walk: a slow sway back and forth along [from]→[to], [frames] ticks.
List<Vector3> swayPath(Vector3 from, Vector3 to, int frames) => [
      for (var i = 0; i < frames; i++)
        () {
          final t = 0.5 - 0.5 * math.cos(i / frames * 4 * math.pi);
          return from + (to - from) * t;
        }(),
    ];

// The painted quad lying on [truth]'s line (parallel mod π, within 0.15 m).
PlaneQuad? paintedWallFor(List<PlaneQuad> walls, SimSurface truth) {
  for (final q in walls) {
    final raw = wrapYaw(q.yaw - truth.yaw).abs();
    final d = raw <= math.pi / 2 ? raw : math.pi - raw;
    if (d > 0.1) continue;
    final n = Vector3(math.sin(truth.yaw), 0, math.cos(truth.yaw));
    final off = (Vector3(q.center.x, truth.center.y, q.center.z) - truth.center)
        .dot(n)
        .abs();
    if (off <= 0.15) return q;
  }
  return null;
}

// XZ distance from [corner] to the nearer end of [q].
double endErrorAt(PlaneQuad q, Vector3 corner) {
  final u = Vector3(math.cos(q.yaw), 0, -math.sin(q.yaw));
  double d(Vector3 e) =>
      math.sqrt(math.pow(e.x - corner.x, 2) + math.pow(e.z - corner.z, 2));
  return math.min(d(q.center - u * (q.extentX / 2)),
      d(q.center + u * (q.extentX / 2)));
}
