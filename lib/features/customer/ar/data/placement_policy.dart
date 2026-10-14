// Pure, side-effect-free plane-hit selection for AR placement. Extracted
// from the AR viewer so it can be unit-tested without widgets or the
// plugin's platform channels.
//
// The bug this encodes: ARCore happily reports fridge tops, nightstands
// and chairs as horizontal planes, and a FIRST tap on a dining table both
// placed furniture on the table AND seeded the floor estimate at table
// height. The policy:
//  * floor placement requires a LARGE, FULLY-REPORTED horizontal plane
//    (both extent axes >= [minFloorExtentM]) AND a height within
//    [maxAboveLiveFloorM] of the LIVE floor seen in recent plane telemetry
//    (fridge tops ~0.6×0.7 m fail the extent gate; dining tables pass the
//    extent gate but sit ~0.5 m above the live floor and fail the height
//    gate);
//  * among valid candidates the LOWEST world-Y hit wins, ties broken by
//    larger extent;
//  * the live floor itself comes from continuous plane telemetry
//    ([liveFloorYFromPlanes]), not from the tap — so a first tap on a
//    table is rejected because the real floor was already seen;
//  * wall placement requires a LARGE vertical plane (both extents >=
//    [minWallExtentM]) whose surface normal is near-horizontal, and picks
//    the LARGEST such wall — fridge sides and wardrobes are rejected.

import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import 'furniture_model_library.dart';

/// Selection policy for tap-to-place plane hits.
class ArPlacementPolicy {
  const ArPlacementPolicy._();

  /// Minimum plane extent (meters) required on BOTH axes before a plane
  /// accepts a FLOOR placement. ARCore's newborn planes start tiny and
  /// refine; elevated furniture surfaces (fridge tops ~0.6×0.7 m,
  /// nightstands, chairs) never reach this on both axes, while real floors
  /// and large tables do.
  static const double minFloorExtentM = 0.7;

  /// Minimum plane extent (meters) required on BOTH axes for a WALL
  /// placement. Walls are big; fridge sides / wardrobe panels mostly fail
  /// this, so furniture no longer glues to them.
  static const double minWallExtentM = 0.8;

  /// Minimum plane extent (meters) along EITHER axis for [PlacementType.any]
  /// — the pre-existing gate, unchanged for that mode.
  static const double minPlaneExtentM = 0.3;

  /// A floor candidate must sit within this many meters of the LIVE floor
  /// (from plane telemetry) on either side. A dining table (~0.5 m up) or a
  /// counter is therefore rejected even though it clears the extent gate.
  static const double maxAboveLiveFloorM = 0.25;

  /// A wall's surface normal (the hit transform's Y-axis) must have |y| at
  /// most this — near-horizontal means a real upright wall, not a tilted
  /// tabletop ARCore momentarily labelled vertical.
  static const double maxWallNormalY = 0.25;

  /// Half the procedural wall panel's depth (the GLB is authored ±0.025 m
  /// about the anchor). The anchor is pushed OUT along the wall normal by
  /// this so the panel's back face sits flush instead of half-buried.
  static const double wallPanelHalfDepthM = 0.025;

  /// World-Y difference (meters) below which two candidates count as the
  /// same height; extent breaks the tie.
  static const double yTieEpsilonM = 0.05;

  /// Whether a hit result's plane is horizontal (floor/table). Prefers the
  /// plugin's [ARHitTestResult.planeType] (1 = horizontal, 2 = vertical);
  /// falls back to the plane normal (Y-axis of the hit rotation) when the
  /// platform didn't report a type.
  static bool isHorizontalPlane(ARHitTestResult hit) {
    final type = hit.planeType;
    if (type == 1) return true;
    if (type == 2) return false;
    // The world transform's column 1 (Y-axis) is the plane normal.
    // For horizontal planes, normal.y ≈ 1.0; for vertical, normal.y ≈ 0.0.
    final normalY = hit.worldTransform.getColumn(1).y.abs();
    return normalY > 0.7;
  }

  /// The hit's world-space height (meters) — the plane's position.
  static double worldY(ARHitTestResult hit) =>
      hit.worldTransform.getTranslation().y;

  /// The plane's reported polygon extent along its larger axis, or null
  /// when the platform did not report it.
  static double? maxExtent(ARHitTestResult hit) {
    final ex = hit.planeExtentX;
    final ez = hit.planeExtentZ;
    if (ex == null || ez == null) return null;
    return math.max(ex, ez);
  }

  /// Legacy size gate for [PlacementType.any]: either axis >=
  /// [minPlaneExtentM]; unreported extents don't block (unchanged
  /// behaviour).
  static bool planeIsLargeEnough(ARHitTestResult hit) {
    final ex = hit.planeExtentX;
    final ez = hit.planeExtentZ;
    if (ex == null || ez == null) return true;
    return ex >= minPlaneExtentM || ez >= minPlaneExtentM;
  }

  /// The LIVE floor's world-Y from continuous plane telemetry: the lowest
  /// centerY among TRACKING horizontal planes whose BOTH extents clear
  /// [minFloorExtentM]. Returns null when no plane qualifies — e.g. only a
  /// table-top (~1.2×0.8 but elevated) or only fridge tops are in view —
  /// which tells the caller to refuse floor placement and prompt a floor
  /// scan instead of guessing a height.
  static double? liveFloorYFromPlanes(List<ARPlaneInfo> planes) {
    double? min;
    for (final p in planes) {
      if (!p.isHorizontal) continue;
      if (p.extentX < minFloorExtentM || p.extentZ < minFloorExtentM) continue;
      if (!p.centerY.isFinite) continue;
      if (min == null || p.centerY < min) min = p.centerY;
    }
    return min;
  }

  /// Picks the plane hit for a FLOOR placement, or null when nothing is
  /// trustworthy. [liveFloorY] is the floor height from recent plane
  /// telemetry (see [liveFloorYFromPlanes]); the caller must have already
  /// refused to place when no live floor exists. Candidates must be
  /// large reported horizontal planes within [maxAboveLiveFloorM] of the
  /// live floor. See the file header for the rules.
  static ARHitTestResult? chooseFloorHit(
    List<ARHitTestResult> hits, {
    required double liveFloorY,
    double maxAboveLiveFloorM = ArPlacementPolicy.maxAboveLiveFloorM,
  }) {
    ARHitTestResult? best;
    double bestExtent = -1;
    for (final h in hits) {
      if (h.type != ARHitTestResultType.plane) continue;
      if (!isHorizontalPlane(h)) continue;
      final ex = h.planeExtentX;
      final ez = h.planeExtentZ;
      // Unreported extent must FAIL for floor placement — a hit we can't
      // size might be a fridge top ARCore hasn't fully measured yet.
      if (ex == null || ez == null) continue;
      // BOTH axes must clear the gate: a 2.0×0.6 console or a 0.6×0.7
      // fridge top fails, a floor or 1.2×0.8 dining table passes the gate
      // but is then caught by the live-floor height check below.
      if (ex < minFloorExtentM || ez < minFloorExtentM) continue;
      final y = worldY(h);
      if (!y.isFinite) continue;
      // Must sit near the LIVE floor: a table ~0.5 m up is rejected even
      // though it clears the extent gate. This is what stops furniture
      // gluing onto tables on the very first tap.
      if ((y - liveFloorY).abs() > maxAboveLiveFloorM) continue;
      final extent = math.max(ex, ez);
      if (best == null) {
        best = h;
        bestExtent = extent;
        continue;
      }
      final dy = y - worldY(best);
      if (dy < -yTieEpsilonM) {
        // Clearly lower: the floor beats any elevated surface.
        best = h;
        bestExtent = extent;
      } else if (dy.abs() <= yTieEpsilonM && extent > bestExtent) {
        // Same height: the bigger plane is the more trustworthy one.
        best = h;
        bestExtent = extent;
      }
    }
    return best;
  }

  /// Picks the plane hit for a WALL placement: a LARGE vertical plane
  /// (both extents >= [minWallExtentM], fully reported) whose surface
  /// normal is near-horizontal (|normal.y| <= [maxWallNormalY]). Among
  /// qualifying walls the LARGEST max-extent wins — a real wall is big;
  /// fridge sides and wardrobe panels are rejected by the extent gate.
  static ARHitTestResult? chooseWallHit(List<ARHitTestResult> hits) {
    ARHitTestResult? best;
    double bestExtent = -1;
    for (final h in hits) {
      if (h.type != ARHitTestResultType.plane) continue;
      if (isHorizontalPlane(h)) continue;
      final ex = h.planeExtentX;
      final ez = h.planeExtentZ;
      // Unreported extent must FAIL for walls too (telemetry era): a hit we
      // can't size might be a fridge side ARCore hasn't fully measured.
      if (ex == null || ez == null) continue;
      if (ex < minWallExtentM || ez < minWallExtentM) continue;
      // Real upright walls have a near-horizontal surface normal (the hit
      // transform's Y-axis points out of the wall, ~level). A steeply
      // tilted normal is a misdetection.
      final normalY = h.worldTransform.getColumn(1).y;
      if (normalY.abs() > maxWallNormalY) continue;
      final extent = math.max(ex, ez);
      if (best == null || extent > bestExtent) {
        best = h;
        bestExtent = extent;
      }
    }
    return best;
  }

  /// Picks the plane hit for [PlacementType.any] — first (closest) plane
  /// passing the legacy size gate, any orientation.
  static ARHitTestResult? chooseAnyHit(List<ARHitTestResult> hits) {
    for (final h in hits) {
      if (h.type != ARHitTestResultType.plane) continue;
      if (!planeIsLargeEnough(h)) continue;
      return h;
    }
    return null;
  }

  /// The yaw (radians about world +Y) that turns a model's +Z axis to point
  /// OUT of a wall along its surface [normal]. ARCore vertical planes carry
  /// the normal on the pose's local +Y (column 1), NOT +Z; the model's
  /// pattern face is authored at +Z, so we yaw until +Z matches the
  /// normal's horizontal projection.
  ///
  /// Reasoning the sign: for a wall the user faces, the normal points out
  /// of the wall toward the user, and we align model +Z (the visible face)
  /// to it — no extra π. The result keeps model +Y on world-up, so the
  /// panel stays upright.
  static double wallAnchorYaw(Vector3 normal) {
    final len = math.sqrt(normal.x * normal.x + normal.z * normal.z);
    if (len < 1e-6) return 0.0;
    return math.atan2(normal.x / len, normal.z / len);
  }

  /// The anchor transform that glues a WALL panel to a vertical plane hit:
  /// the hit position, yawed so the model's +Z (pattern face) points out of
  /// the wall along the plane normal, and pushed OUT along that normal by
  /// half the panel depth ([wallPanelHalfDepthM]) so the back face sits
  /// flush instead of half-buried. Model +Y stays world-up (the panel is
  /// upright). The pure math is [wallAnchorYaw].
  static Matrix4 wallAnchorTransform(
    ARHitTestResult hit, {
    double halfDepthM = wallPanelHalfDepthM,
  }) {
    // Vertical plane: the surface NORMAL is the pose's local +Y (column 1).
    final col1 = hit.worldTransform.getColumn(1);
    final nxz = math.sqrt(col1.x * col1.x + col1.z * col1.z);
    final ux = nxz < 1e-6 ? 0.0 : col1.x / nxz; // horizontal unit normal
    final uz = nxz < 1e-6 ? 1.0 : col1.z / nxz;
    final yaw = wallAnchorYaw(Vector3(col1.x, col1.y, col1.z));
    final p = hit.worldTransform.getTranslation();
    return Matrix4.identity()
      ..setTranslation(Vector3(
        p.x + ux * halfDepthM,
        p.y,
        p.z + uz * halfDepthM,
      ))
      ..rotateY(yaw);
  }
}
