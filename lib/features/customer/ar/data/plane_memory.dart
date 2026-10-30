import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';

enum PlaneClass { floor, wall, elevatedSurface, smallSurface, unknown }

class _TrackedPlane {
  _TrackedPlane(this.id, ARPlaneInfo p, DateTime seen)
      : planeType = p.planeType,
        centerX = p.centerX,
        centerY = p.centerY,
        centerZ = p.centerZ,
        extentX = p.extentX,
        extentZ = p.extentZ,
        yaw = p.yaw,
        firstSeen = seen,
        lastSeen = seen;

  final int id;

  int planeType;

  double centerX;

  double centerY;

  double centerZ;

  double extentX;

  double extentZ;

  double yaw;

  final DateTime firstSeen;

  DateTime lastSeen;

  PlaneClass? cls;

  int pendingVotes = 0;

  PlaneClass? pendingClass;

  void absorb(ARPlaneInfo p, DateTime seen,
      {required double centerAlpha, required double extentAlpha}) {
    planeType = p.planeType;
    centerX += (p.centerX - centerX) * centerAlpha;
    centerY += (p.centerY - centerY) * centerAlpha;
    centerZ += (p.centerZ - centerZ) * centerAlpha;
    extentX += (p.extentX - extentX) * extentAlpha;
    extentZ += (p.extentZ - extentZ) * extentAlpha;
    // Yaw is circular: glide across the ±π seam instead of through zero.
    yaw += _wrapPi(p.yaw - yaw) * centerAlpha;
    lastSeen = seen;
  }

  ARPlaneInfo toPlaneInfo() => ARPlaneInfo(
        id: id,
        planeType: planeType,
        centerX: centerX,
        centerY: centerY,
        centerZ: centerZ,
        extentX: extentX,
        extentZ: extentZ,
        yaw: yaw,
      );
}

double _wrapPi(double angle) {
  var a = angle % (2 * math.pi);
  if (a > math.pi) a -= 2 * math.pi;
  if (a < -math.pi) a += 2 * math.pi;
  return a;
}

class _Box {
  const _Box(this.xMin, this.xMax, this.zMin, this.zMax);

  final double xMin;
  final double xMax;
  final double zMin;
  final double zMax;

  double get width => xMax - xMin;

  double get depth => zMax - zMin;

  bool contains(double x, double z) =>
      x >= xMin && x <= xMax && z >= zMin && z <= zMax;
}

/// Persistent per-plane state for the AR session.
///
/// Floor and wall detection run as SEPARATE streams: horizontal planes
/// (ARCore type 1) live in one, vertical planes (type 2) in the other, and
/// neither can influence the other's estimates — a wall can never pull the
/// floor height, floor fragments can never vouch a wall. Everything else
/// (ceilings, odd types) is ignored outright.
///
/// Each stream keeps a smoothed pose and classification history per plane
/// and re-evaluates the classification every frame, so a surface that later
/// turns out to be furniture (or a wall) is corrected instead of staying
/// wrong. Records are matched by stable id when the plugin provides one and
/// by nearest-neighbor otherwise, so smoothing/hysteresis accumulate even
/// across jittery center reports.
///
/// The floor stream also merges adjacent fragments into regions
/// ([floorCoverageExtentM], [knowsFloorAt]) — ARCore often reports a room's
/// floor as several small patches, and placement should trust the
/// accumulated floor, not each fragment alone.
class PlaneMemory {
  PlaneMemory({
    this.centerAlpha = 0.35,
    this.extentAlpha = 0.3,
    this.minFloorEstablishExtentM = 1.2,
    this.minFloorExtentM = 1.0,
    this.floorLevelToleranceM = 0.2,
    this.elevatedGapM = 0.3,
    this.minWallExtentM = 0.8,
    this.minWallLongExtentM = 1.5,
    this.smallSurfaceExtentM = 0.35,
    this.minPhoneAboveFloorM = 0.85,
    this.maxPhoneAboveFloorM = 2.4,
    this.loosePhoneAboveFloorM = 0.5,
    this.recordMaxAge = const Duration(seconds: 12),
    this.freshnessWindow = const Duration(seconds: 10),
    this.flipVotes = 2,
    this.matchRadiusM = 0.75,
    this.clusterGapM = 0.5,
  });

  final double centerAlpha;

  final double extentAlpha;

  // A plane must be at least this large BOTH ways before it can establish the
  // room's floor height — furniture tops saturate below this.
  final double minFloorEstablishExtentM;

  final double minFloorExtentM;

  final double floorLevelToleranceM;

  // Horizontal surfaces this far above the floor are furniture, not floor.
  final double elevatedGapM;

  final double minWallExtentM;

  final double minWallLongExtentM;

  final double smallSurfaceExtentM;

  // Camera-height prior: the floor sits this far below a handheld phone.
  final double minPhoneAboveFloorM;

  final double maxPhoneAboveFloorM;

  final double loosePhoneAboveFloorM;

  final Duration recordMaxAge;

  final Duration freshnessWindow;

  // Consecutive agreeing frames before a classification flips.
  final int flipVotes;

  // Id-less planes are matched to a record this close before a new record is
  // opened — keeps smoothing alive when the plugin reports no stable ids.
  final double matchRadiusM;

  // Floor fragments this close (gap between their rectangles) merge into one
  // region for coverage and vouching.
  final double clusterGapM;

  // ─── The two detection streams, kept strictly apart ────────────────────────

  final Map<Object, _TrackedPlane> _floor = {};

  final Map<Object, _TrackedPlane> _wall = {};

  double? _floorY;

  double? _cameraY;

  DateTime? _lastIngest;

  int _nextSyntheticKey = 1;

  double? get floorY => _floorY;

  bool get floorEstablished => _floorY != null;

  bool get isFresh {
    final at = _lastIngest;
    return at != null && DateTime.now().difference(at) <= freshnessWindow;
  }

  List<ARPlaneInfo> get floorPlanes =>
      _floor.values.map((r) => r.toPlaneInfo()).toList();

  List<ARPlaneInfo> get wallPlanes =>
      _wall.values.map((r) => r.toPlaneInfo()).toList();

  void noteCameraY(double y, {DateTime? now}) {
    if (!y.isFinite) return;
    _cameraY = y;
    _updateFloorY(now ?? DateTime.now());
    _reclassify();
  }

  void ingest(List<ARPlaneInfo> planes, {DateTime? now}) {
    final t = now ?? DateTime.now();
    _lastIngest = t;
    for (final p in planes) {
      if (!p.centerY.isFinite || !p.centerX.isFinite || !p.centerZ.isFinite) {
        continue;
      }
      final stream = p.planeType == 1
          ? _floor
          : p.planeType == 2
              ? _wall
              : null;
      if (stream == null) continue;
      _absorbInto(stream, p, t);
    }
    _floor.removeWhere((_, r) => t.difference(r.lastSeen) > recordMaxAge);
    _wall.removeWhere((_, r) => t.difference(r.lastSeen) > recordMaxAge);
    _updateFloorY(t);
    _reclassify();
  }

  PlaneClass? classOf(int id) {
    for (final r in _floor.values) {
      if (r.id == id) return r.cls;
    }
    for (final r in _wall.values) {
      if (r.id == id) return r.cls;
    }
    return null;
  }

  // Classification of the plane this point sits on, per stream — floor
  // queries only ever see the floor stream, wall queries only the wall
  // stream. Null when the streams know nothing there.
  PlaneClass? classNear(double x, double y, double z, {required int planeType}) {
    final stream = planeType == 1 ? _floor : planeType == 2 ? _wall : null;
    if (stream == null) return null;
    _TrackedPlane? best;
    var bestDist = double.infinity;
    for (final r in stream.values) {
      final dx = r.centerX - x;
      final dy = planeType == 1 ? 0.0 : r.centerY - y;
      final dz = r.centerZ - z;
      final dist = math.sqrt(dx * dx + dy * dy + dz * dz);
      final reach = math.max(matchRadiusM, math.max(r.extentX, r.extentZ) / 2);
      if (dist > reach) continue;
      if (dist < bestDist) {
        best = r;
        bestDist = dist;
      }
    }
    return best?.cls;
  }

  // Smallest side of the largest merged floor region — several small ARCore
  // patches next to each other count as one swept area.
  double floorCoverageExtentM() {
    var best = 0.0;
    for (final box in _floorClusters()) {
      final c = math.min(box.width, box.depth);
      if (c > best) best = c;
    }
    return best;
  }

  // True when (x, z) lies inside a merged floor region — the memory vouches
  // this spot as genuine floor even if the local plane fragment is small.
  bool knowsFloorAt(double x, double z) {
    for (final box in _floorClusters()) {
      if (box.contains(x, z)) return true;
    }
    return false;
  }

  List<ARPlaneInfo> smoothedPlanes(
      {Duration maxAge = const Duration(seconds: 4)}) {
    final now = _lastIngest ?? DateTime.now();
    return [..._floor.values, ..._wall.values]
        .where((r) => now.difference(r.lastSeen) <= maxAge)
        .map((r) => r.toPlaneInfo())
        .toList();
  }

  void _absorbInto(Map<Object, _TrackedPlane> stream, ARPlaneInfo p, DateTime t) {
    if (p.id != 0) {
      final byId = stream[p.id];
      if (byId != null) {
        byId.absorb(p, t,
            centerAlpha: centerAlpha, extentAlpha: extentAlpha);
        return;
      }
    } else {
      final near = _nearestRecord(stream, p);
      if (near != null) {
        near.absorb(p, t,
            centerAlpha: centerAlpha, extentAlpha: extentAlpha);
        return;
      }
    }
    // Id-less planes get a unique negative id so every record stays
    // addressable (classOf, overlay coloring) instead of colliding on 0.
    if (p.id != 0) {
      stream[p.id] = _TrackedPlane(p.id, p, t);
    } else {
      final synthetic = -_nextSyntheticKey++;
      stream[synthetic] = _TrackedPlane(synthetic, p, t);
    }
  }

  _TrackedPlane? _nearestRecord(
      Map<Object, _TrackedPlane> stream, ARPlaneInfo p) {
    _TrackedPlane? best;
    var bestDist = double.infinity;
    for (final r in stream.values) {
      final dx = r.centerX - p.centerX;
      final dy = r.centerY - p.centerY;
      final dz = r.centerZ - p.centerZ;
      final dist = math.sqrt(dx * dx + dy * dy + dz * dz);
      if (dist > matchRadiusM) continue;
      if (dist < bestDist) {
        best = r;
        bestDist = dist;
      }
    }
    return best;
  }

  List<_Box> _floorClusters() {
    final rects = <_Box>[];
    for (final r in _floor.values) {
      if (r.cls != PlaneClass.floor) continue;
      rects.add(_Box(
        r.centerX - r.extentX / 2,
        r.centerX + r.extentX / 2,
        r.centerZ - r.extentZ / 2,
        r.centerZ + r.extentZ / 2,
      ));
    }
    final clusters = <List<_Box>>[];
    for (final rect in rects) {
      final group = <_Box>[rect];
      var i = 0;
      while (i < clusters.length) {
        final cluster = clusters[i];
        final touches = cluster.any((b) => _near(b, rect));
        if (touches) {
          group.addAll(cluster);
          clusters.removeAt(i);
        } else {
          i++;
        }
      }
      clusters.add(group);
    }
    return clusters.map((group) {
      var xMin = double.infinity, xMax = -double.infinity;
      var zMin = double.infinity, zMax = -double.infinity;
      for (final b in group) {
        xMin = math.min(xMin, b.xMin);
        xMax = math.max(xMax, b.xMax);
        zMin = math.min(zMin, b.zMin);
        zMax = math.max(zMax, b.zMax);
      }
      return _Box(xMin, xMax, zMin, zMax);
    }).toList();
  }

  bool _near(_Box a, _Box b) {
    final gapX = math.max(0.0, math.max(a.xMin - b.xMax, b.xMin - a.xMax));
    final gapZ = math.max(0.0, math.max(a.zMin - b.zMax, b.zMin - a.zMax));
    return gapX <= clusterGapM && gapZ <= clusterGapM;
  }

  void _updateFloorY(DateTime t) {
    double? strictBest;
    double? looseBest;
    for (final r in _floor.values) {
      final shortSide = math.min(r.extentX, r.extentZ);
      if (shortSide < minFloorEstablishExtentM) continue;
      final below = _cameraY == null ? null : _cameraY! - r.centerY;
      if (below != null) {
        if (below >= minPhoneAboveFloorM && below <= maxPhoneAboveFloorM) {
          if (strictBest == null || r.centerY < strictBest) {
            strictBest = r.centerY;
          }
        } else if (below >= loosePhoneAboveFloorM && below <= maxPhoneAboveFloorM) {
          if (looseBest == null || r.centerY < looseBest) {
            looseBest = r.centerY;
          }
        } else {
          continue;
        }
      }
      if (below == null) {
        if (strictBest == null || r.centerY < strictBest) {
          strictBest = r.centerY;
        }
      }
    }
    final target = strictBest ?? looseBest;
    if (target == null) return;
    final current = _floorY;
    if (current == null) {
      _floorY = target;
      return;
    }
    // Correct a wrong (too-high) estimate faster than drift upward: the
    // floor is the LOWEST confirmed surface, so a lower one is a correction.
    final alpha = target < current ? 0.85 : 0.35;
    _floorY = current + (target - current) * alpha;
  }

  void _reclassify() {
    for (final r in [..._floor.values, ..._wall.values]) {
      final proposal = _propose(r);
      if (r.cls == null) {
        r.cls = proposal;
        r.pendingClass = null;
        r.pendingVotes = 0;
        continue;
      }
      if (proposal == r.cls) {
        r.pendingClass = null;
        r.pendingVotes = 0;
        continue;
      }
      if (r.pendingClass == proposal) {
        r.pendingVotes += 1;
      } else {
        r.pendingClass = proposal;
        r.pendingVotes = 1;
      }
      if (r.pendingVotes >= flipVotes) {
        r.cls = proposal;
        r.pendingClass = null;
        r.pendingVotes = 0;
      }
    }
  }

  PlaneClass _propose(_TrackedPlane r) {
    if (r.planeType == 1) {
      final shortSide = math.min(r.extentX, r.extentZ);
      if (shortSide < smallSurfaceExtentM) return PlaneClass.smallSurface;
      final fy = _floorY;
      if (fy != null && r.centerY > fy + elevatedGapM) {
        return PlaneClass.elevatedSurface;
      }
      if (shortSide >= minFloorExtentM &&
          (fy == null || (r.centerY - fy).abs() <= floorLevelToleranceM)) {
        return PlaneClass.floor;
      }
      return PlaneClass.unknown;
    }
    if (r.planeType == 2) {
      final shortSide = math.min(r.extentX, r.extentZ);
      final longSide = math.max(r.extentX, r.extentZ);
      if (shortSide >= minWallExtentM && longSide >= minWallLongExtentM) {
        return PlaneClass.wall;
      }
      return PlaneClass.smallSurface;
    }
    return PlaneClass.unknown;
  }
}
