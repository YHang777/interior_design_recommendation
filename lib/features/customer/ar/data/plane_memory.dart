import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';

import 'placement_policy.dart';

enum PlaneClass { floor, wall, elevatedSurface, smallSurface, unknown }

// Re-fit detection: ARCore revising a floor's surface height or pulling an
// over-extended outline back is a new observation, not drift to smooth over.
const _reopenHeightM = 0.15;
const _reopenShrinkM = 0.4;

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

  // Last time the payload carried this plane at all. A plane in the payload
  // is TRACKING by construction (native cache only re-emits live planes),
  // so presence — not observation freshness — is what keeps a record alive.
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

  // Re-fit: adopt the raw observation and clear classification history so
  // the next frames vote from scratch instead of inheriting the previous
  // (wrong) state.
  void reopen(ARPlaneInfo p, DateTime seen) {
    planeType = p.planeType;
    centerX = p.centerX;
    centerY = p.centerY;
    centerZ = p.centerZ;
    extentX = p.extentX;
    extentZ = p.extentZ;
    yaw = p.yaw;
    cls = null;
    pendingVotes = 0;
    pendingClass = null;
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
  // room's floor height — furniture tops saturate below this. Lowered once by
  // relaxGates() after a long unproductive scan.
  double minFloorEstablishExtentM;

  double minFloorExtentM;

  bool gatesRelaxed = false;

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

  // Called once by the AR screen after ArPlacementPolicy.relaxGatesAfter of
  // scanning without a placeable floor — small-but-real floors can then
  // establish and classify. Only ever LOWERS the gates (min with the current
  // value), and once relaxed the loose camera band can no longer lock the
  // floor (see _updateFloorY), so a bed or low bench cannot become floorY.
  void relaxGates() {
    if (gatesRelaxed) return;
    gatesRelaxed = true;
    minFloorEstablishExtentM = math.min(
      minFloorEstablishExtentM,
      ArPlacementPolicy.minFloorEstablishExtentRelaxedM,
    );
    minFloorExtentM = math.min(
      minFloorExtentM,
      ArPlacementPolicy.minFloorExtentRelaxedM,
    );
  }

  // ─── The two detection streams, kept strictly apart ────────────────────────

  final Map<Object, _TrackedPlane> _floor = {};

  final Map<Object, _TrackedPlane> _wall = {};

  double? _floorY;

  double? _cameraY;

  // Set once any probe correction has landed. From then on the plane path
  // may never raise floorY: the corrected height holds for the whole
  // session (this object lives as long as the AR page). Upward drift toward
  // furniture tops is what destroyed corrected planes.
  bool _probeCorrected = false;

  // Render-trust state — gates PAINTING only, never placement. A loose or
  // camera-unknown establishment can land on a table top, and painting green
  // at that height is the floating detection plane; only a strict band
  // establishment (camera known) or a live point-cloud probe proves the
  // height is really the floor.
  bool _floorYStrictEstablished = false;

  double? _probeProvenY;

  // Agreeing readings noteFloorYCandidate needs before it may move floorY —
  // background confirmation so a lone noisy streak can't slam the floor.
  static const _refocusChecks = 10;

  // Streak gate on noteFloorYCandidate: a single low depth median must not
  // move floorY.
  double? _probeStreakY;

  int _probeStreak = 0;

  DateTime? _lastIngest;

  int _nextSyntheticKey = 1;

  double? get floorY => _floorY;

  bool get floorEstablished => _floorY != null;

  // Whether floorY may anchor green rendering (overlayZoneOf floorYTrusted,
  // synthetic floor). A probe-proven height always decides; floorY can no
  // longer drift up after a correction, but a later correction more than
  // 0.25 m from probeY still drops trust.
  bool get floorYRenderTrusted {
    final fy = _floorY;
    if (fy == null) return false;
    final provenY = _probeProvenY;
    if (provenY != null) return (fy - provenY).abs() <= 0.25;
    return _floorYStrictEstablished;
  }

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
    _updateFloorY();
    _reclassify();
  }

  // Point-cloud probe correction: raw depth points keep arriving while
  // plane telemetry goes quiet, so a low-percentile Y can drag a floorY
  // that locked onto a furniture top or floating phantom down to the real
  // floor — then _reclassify flips the wrong plane within a couple of
  // votes and the geometric overlay repaints (overlayZoneOf reads floorY
  // directly). Downward only with a deadband (a low percentile reads
  // slightly low on noise), inside the same camera band the plane path
  // trusts, and it never ESTABLISHES floorY — planes do that. Runs as a
  // background evidence accumulator: _refocusChecks agreeing readings
  // confirm the detected plane is wrong, then one 0.85 jump lands.
  void noteFloorYCandidate(double y, {DateTime? now}) {
    if (!y.isFinite || _floorY == null) {
      _probeStreak = 0;
      _probeStreakY = null;
      return;
    }
    if (_cameraY != null) {
      final below = _cameraY! - y;
      if (below < loosePhoneAboveFloorM || below > maxPhoneAboveFloorM) {
        _probeStreak = 0;
        _probeStreakY = null;
        return;
      }
    }
    final fy = _floorY!;
    const deadbandM = 0.05;
    if (y >= fy - deadbandM) {
      _probeStreak = 0;
      _probeStreakY = null;
      return;
    }
    // _refocusChecks agreeing readings confirm the plane is wrong; a lone
    // noisy depth median used to slam floorY under the true floor and flip
    // the painted plane to a mask ("refocus killed my corrected plane").
    // FloorY stays put during the streak — a genuine correction lands as
    // one 0.85 jump; at the true floor the readings fall back inside the
    // deadband and the streak resets.
    final streakY = _probeStreakY;
    if (streakY == null || (y - streakY).abs() > 0.05) {
      _probeStreakY = y;
      _probeStreak = 1;
      return;
    }
    _probeStreak++;
    if (_probeStreak < _refocusChecks) return;
    _floorY = fy + (y - fy) * 0.85;
    _probeCorrected = true;
    _probeProvenY = y;
    _reclassify();
    _probeStreak = 0;
    _probeStreakY = null;
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
    // Presence-based liveness: anything in this payload was refreshed above
    // and can never be pruned here, so a prune means the plane has been
    // absent from the payload for recordMaxAge.
    _floor.removeWhere((_, r) => t.difference(r.lastSeen) > recordMaxAge);
    _wall.removeWhere((_, r) => t.difference(r.lastSeen) > recordMaxAge);
    _updateFloorY();
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
        _absorbOrReopen(byId, p, t);
        return;
      }
    } else {
      final near = _nearestRecord(stream, p);
      if (near != null) {
        _absorbOrReopen(near, p, t);
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

  // A floor whose surface height was revised, or an outline ARCore pulled
  // back after over-extending, is a re-fit — gliding toward it would keep
  // the previous wrong classification alive for seconds. Snap and re-open
  // instead so refocused frames reclassify from scratch. Floors only: a
  // growing wall's midpoint moves, and ARCore re-refines wall extents near
  // the classify gates — snapping there would bypass the flip hysteresis
  // the wall stream relies on. Plain growth never re-opens either.
  void _absorbOrReopen(_TrackedPlane r, ARPlaneInfo p, DateTime t) {
    if (r.planeType == 1) {
      final heightJump = (p.centerY - r.centerY).abs() > _reopenHeightM;
      final shrinkX = r.extentX - p.extentX > _reopenShrinkM;
      final shrinkZ = r.extentZ - p.extentZ > _reopenShrinkM;
      if (heightJump || shrinkX || shrinkZ) {
        r.reopen(p, t);
        return;
      }
    }
    r.absorb(p, t, centerAlpha: centerAlpha, extentAlpha: extentAlpha);
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

  void _updateFloorY() {
    // Camera-band buckets only at this stage: the size gate is applied to
    // merged clusters, not per record — a room's floor reported as several
    // sub-gate fragments must still beat one large furniture top.
    final strict = <_TrackedPlane>[];
    final loose = <_TrackedPlane>[];
    for (final r in _floor.values) {
      final below = _cameraY == null ? null : _cameraY! - r.centerY;
      if (below == null) {
        strict.add(r);
      } else if (below >= minPhoneAboveFloorM && below <= maxPhoneAboveFloorM) {
        strict.add(r);
      } else if (below >= loosePhoneAboveFloorM &&
          below <= maxPhoneAboveFloorM) {
        loose.add(r);
      }
    }
    final strictBest = _lowestEstablishable(strict);
    final looseBest = _lowestEstablishable(loose);
    // Once relaxed (long scan), the loose 0.5 m window can no longer lock
    // the floor — a bed top sitting 0.55 m below the phone must not become
    // floorY and then refuse the real floor via the height gate.
    final target = strictBest ?? (gatesRelaxed ? null : looseBest);
    if (target == null) return;
    // Only a strict-band target with a known camera height proves the paint
    // height; loose/camera-unknown assignments demote the flag instead.
    final fromStrict = strictBest != null && _cameraY != null;
    final current = _floorY;
    if (current == null) {
      _floorY = target;
      _floorYStrictEstablished = fromStrict;
      return;
    }
    // After a probe correction the plane path may never raise floorY — the
    // corrected height holds until the page closes (upward drift toward
    // furniture tops destroyed corrected planes). Downward corrections and
    // initial establishment still apply.
    if (target > current && _probeCorrected) return;
    // Correct a wrong (too-high) estimate faster than drift upward: the
    // floor is the LOWEST confirmed surface, so a lower one is a correction.
    final alpha = target < current ? 0.85 : 0.35;
    _floorY = current + (target - current) * alpha;
    _floorYStrictEstablished = fromStrict;
  }

  // Lowest surface height among clusters that clear the establish gate on
  // their own OR after merging with coplanar neighbors — a fragmented real
  // floor passes as one swept region while an isolated furniture top of the
  // same total area still fails. Returns null when no cluster qualifies.
  double? _lowestEstablishable(List<_TrackedPlane> recs) {
    if (recs.isEmpty) return null;
    final groups = <List<_TrackedPlane>>[];
    for (final r in recs) {
      var placed = false;
      for (final g in groups) {
        if (g.any((o) => _coplanarNear(o, r))) {
          g.add(r);
          placed = true;
          break;
        }
      }
      if (!placed) groups.add([r]);
    }
    // Single-linkage merge: two groups join when ANY cross pair is both
    // coplanar (same surface height) and near in XZ — the greedy pass above
    // can leave a chain split across groups.
    var merged = true;
    while (merged) {
      merged = false;
      outer:
      for (var i = 0; i < groups.length; i++) {
        for (var j = i + 1; j < groups.length; j++) {
          if (_groupsCoplanarNear(groups[i], groups[j])) {
            groups[i].addAll(groups[j]);
            groups.removeAt(j);
            merged = true;
            break outer;
          }
        }
      }
    }
    double? best;
    for (final g in groups) {
      var xMin = double.infinity, xMax = -double.infinity;
      var zMin = double.infinity, zMax = -double.infinity;
      var low = double.infinity;
      for (final r in g) {
        xMin = math.min(xMin, r.centerX - r.extentX / 2);
        xMax = math.max(xMax, r.centerX + r.extentX / 2);
        zMin = math.min(zMin, r.centerZ - r.extentZ / 2);
        zMax = math.max(zMax, r.centerZ + r.extentZ / 2);
        if (r.centerY < low) low = r.centerY;
      }
      final shortSide = math.min(xMax - xMin, zMax - zMin);
      if (shortSide < minFloorEstablishExtentM) continue;
      if (best == null || low < best) best = low;
    }
    return best;
  }

  bool _coplanarNear(_TrackedPlane a, _TrackedPlane b) {
    if ((a.centerY - b.centerY).abs() > floorLevelToleranceM) return false;
    return _near(_boxOf(a), _boxOf(b));
  }

  _Box _boxOf(_TrackedPlane r) => _Box(
        r.centerX - r.extentX / 2,
        r.centerX + r.extentX / 2,
        r.centerZ - r.extentZ / 2,
        r.centerZ + r.extentZ / 2,
      );

  bool _groupsCoplanarNear(List<_TrackedPlane> a, List<_TrackedPlane> b) {
    for (final x in a) {
      for (final y in b) {
        if (_coplanarNear(x, y)) return true;
      }
    }
    return false;
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
