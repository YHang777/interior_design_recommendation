import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_plane_fit.dart';
import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

class ArPlacementPolicy {
  const ArPlacementPolicy._();

  // A plane must be at least this large BOTH ways to host floor placement.
  // Furniture tops (desks, nightstands, most dining tables) saturate below it.
  static const double minFloorExtentM = 1.0;

  // Room-floor establishment (PlaneMemory): even stricter, so a lone table
  // scanned before the floor can't become "the floor".
  static const double minFloorEstablishExtentM = 1.2;

  static const double minWallExtentM = 0.8;

  // The long side must reach this far, so chair backs and cabinet sides
  // (anything under ~1.5 m) never pass as walls.
  static const double minWallLongExtentM = 1.5;

  static const double minPlaneExtentM = 0.3;

  // Floor placement is only allowed this far above the live floor — a chair
  // seat (0.45 m) or table top (0.7 m) can never sneak through.
  static const double maxAboveLiveFloorM = 0.15;

  static const double maxWallNormalY = 0.25;

  static const double wallPanelHalfDepthM = 0.025;

  static const double yTieEpsilonM = 0.05;

  // Apple-style distance window: too-near hits are pose noise, hits past a
  // room's reach are misfires. Keeps placement and the reticle honest.
  static const double minPlacementDistanceM = 0.25;

  static const double maxPlacementDistanceM = 4.0;

  static bool distanceIsPlausible(ARHitTestResult hit) =>
      hit.distance >= minPlacementDistanceM &&
      hit.distance <= maxPlacementDistanceM;

  static bool isHorizontalPlane(ARHitTestResult hit) {
    final type = hit.planeType;
    if (type == 1) return true;
    if (type == 2) return false;
    final normalY = hit.worldTransform.getColumn(1).y.abs();
    return normalY > 0.7;
  }

  static double worldY(ARHitTestResult hit) =>
      hit.worldTransform.getTranslation().y;

  static double? maxExtent(ARHitTestResult hit) {
    final ex = hit.planeExtentX;
    final ez = hit.planeExtentZ;
    if (ex == null || ez == null) return null;
    return math.max(ex, ez);
  }

  static bool planeIsLargeEnough(ARHitTestResult hit) {
    final ex = hit.planeExtentX;
    final ez = hit.planeExtentZ;
    if (ex == null || ez == null) return true;
    return ex >= minFloorExtentM && ez >= minFloorExtentM;
  }

  static bool _floorHitQualifies(
    ARHitTestResult hit, {
    double? liveFloorY,
    double maxAbove = maxAboveLiveFloorM,
    bool Function(ARHitTestResult hit)? vouchedFloor,
  }) {
    final ex = hit.planeExtentX;
    final ez = hit.planeExtentZ;
    if (ex == null || ez == null) return false;
    final bigEnough = ex >= minFloorExtentM && ez >= minFloorExtentM;
    // A small ARCore fragment is still fine when the plane memory vouches
    // the spot as part of the accumulated real floor.
    if (!bigEnough && !(vouchedFloor?.call(hit) ?? false)) return false;
    if (!distanceIsPlausible(hit)) return false;
    final y = worldY(hit);
    if (!y.isFinite) return false;
    if (liveFloorY != null && (y - liveFloorY).abs() > maxAbove) {
      return false;
    }
    return true;
  }

  static bool _wallHitQualifies(
    ARHitTestResult hit, {
    bool Function(ARHitTestResult hit)? vouchedWall,
  }) {
    final ex = hit.planeExtentX;
    final ez = hit.planeExtentZ;
    if (ex == null || ez == null) return false;
    final bigEnough = ex >= minWallExtentM &&
        ez >= minWallExtentM &&
        math.max(ex, ez) >= minWallLongExtentM;
    if (!bigEnough && !(vouchedWall?.call(hit) ?? false)) return false;
    if (!distanceIsPlausible(hit)) return false;
    final normalY = hit.worldTransform.getColumn(1).y;
    if (normalY.abs() > maxWallNormalY) return false;
    return true;
  }

  static double? liveFloorYFromPlanes(List<ARPlaneInfo> planes) {
    double? min;
    for (final p in planes) {
      if (!p.isHorizontal) continue;
      if (p.extentX < minFloorEstablishExtentM ||
          p.extentZ < minFloorEstablishExtentM) {
        continue;
      }
      if (!p.centerY.isFinite) continue;
      if (min == null || p.centerY < min) min = p.centerY;
    }
    return min;
  }

  static ARHitTestResult? chooseFloorHit(
    List<ARHitTestResult> hits, {
    required double liveFloorY,
    double maxAboveLiveFloorM = ArPlacementPolicy.maxAboveLiveFloorM,
    bool Function(ARHitTestResult hit)? vouchedFloor,
  }) {
    ARHitTestResult? best;
    double bestExtent = -1;
    for (final h in hits) {
      if (h.type != ARHitTestResultType.plane) continue;
      if (!isHorizontalPlane(h)) continue;
      if (!_floorHitQualifies(h,
          liveFloorY: liveFloorY,
          maxAbove: maxAboveLiveFloorM,
          vouchedFloor: vouchedFloor)) {
        continue;
      }
      final ex = h.planeExtentX!;
      final ez = h.planeExtentZ!;
      final extent = math.max(ex, ez);
      final y = worldY(h);
      if (best == null) {
        best = h;
        bestExtent = extent;
        continue;
      }
      final dy = y - worldY(best);
      if (dy < -yTieEpsilonM) {
        best = h;
        bestExtent = extent;
      } else if (dy.abs() <= yTieEpsilonM && extent > bestExtent) {
        best = h;
        bestExtent = extent;
      }
    }
    return best;
  }

  static ARHitTestResult? chooseWallHit(
    List<ARHitTestResult> hits, {
    bool Function(ARHitTestResult hit)? vouchedWall,
  }) {
    ARHitTestResult? best;
    double bestExtent = -1;
    for (final h in hits) {
      if (h.type != ARHitTestResultType.plane) continue;
      if (isHorizontalPlane(h)) continue;
      if (!_wallHitQualifies(h, vouchedWall: vouchedWall)) continue;
      final extent = maxExtent(h)!;
      if (best == null || extent > bestExtent) {
        best = h;
        bestExtent = extent;
      }
    }
    return best;
  }

  /// Floor-or-wall placement. With [liveFloorY] known, floor hits face the
  /// same height gate as [chooseFloorHit], so furniture tops are refused here
  /// too. Qualifying hits compete by distance.
  static ARHitTestResult? chooseAnyHit(
    List<ARHitTestResult> hits, {
    double? liveFloorY,
    bool Function(ARHitTestResult hit)? vouchedFloor,
    bool Function(ARHitTestResult hit)? vouchedWall,
  }) {
    ARHitTestResult? best;
    double bestDistance = double.infinity;
    for (final h in hits) {
      if (h.type != ARHitTestResultType.plane) continue;
      if (!distanceIsPlausible(h)) continue;
      final horizontal = isHorizontalPlane(h);
      final ok = horizontal
          ? _floorHitQualifies(h,
              liveFloorY: liveFloorY, vouchedFloor: vouchedFloor)
          : _wallHitQualifies(h, vouchedWall: vouchedWall);
      if (!ok) continue;
      if (h.distance < bestDistance) {
        best = h;
        bestDistance = h.distance;
      }
    }
    return best;
  }

  static double wallAnchorYaw(Vector3 normal) {
    final len = math.sqrt(normal.x * normal.x + normal.z * normal.z);
    if (len < 1e-6) return 0.0;
    return math.atan2(normal.x / len, normal.z / len);
  }

  /// Yaw that turns the model's +Z to face the camera — placed furniture
  /// looks at the user instead of a fixed world direction.
  static double faceCameraYaw(Vector3 point, Vector3 cameraPosition) {
    final dx = cameraPosition.x - point.x;
    final dz = cameraPosition.z - point.z;
    if (dx.abs() < 1e-6 && dz.abs() < 1e-6) return 0.0;
    return math.atan2(dx, dz);
  }

  /// Floor anchor at the hit point: model stands world-up (Y-up authored
  /// GLBs) and faces the camera.
  static Matrix4 floorAnchorTransform(
    ARHitTestResult hit, {
    Vector3? cameraPosition,
  }) {
    final p = hit.worldTransform.getTranslation();
    final yaw = cameraPosition == null
        ? 0.0
        : faceCameraYaw(Vector3(p.x, p.y, p.z), cameraPosition);
    return Matrix4.identity()
      ..setTranslation(Vector3(p.x, p.y, p.z))
      ..rotateY(yaw);
  }

  static Matrix4 wallAnchorTransform(
    ARHitTestResult hit, {
    double halfDepthM = wallPanelHalfDepthM,
  }) {
    final col1 = hit.worldTransform.getColumn(1);
    final nxz = math.sqrt(col1.x * col1.x + col1.z * col1.z);
    final ux = nxz < 1e-6 ? 0.0 : col1.x / nxz;
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

  /// Minimum RANSAC-fit confidence before we trust a refined plane over
  /// ARCore's own hit pose. Below this we fall back to the raw hit.
  static const double minRefinedConfidence = 0.35;

  /// Y of [p] projected onto the fitted plane — keeps placement exactly where
  /// the user tapped while sitting on the refined surface instead of drifting
  /// to the inlier cloud's centroid.
  static double projectYOntoFit(ArPlaneFit fit, Vector3 p) {
    final n = fit.normal;
    if (n.y.abs() < 1e-3) return fit.center.y;
    return fit.center.y -
        (n.x * (p.x - fit.center.x) + n.z * (p.z - fit.center.z)) / n.y;
  }

  /// Builds an anchor transform from a RANSAC-refined plane fit, which is
  /// more accurate than ARCore's jittery plane polygon. Floor fits anchor at
  /// [anchorAt] (the tap) projected onto the fitted plane, world-up and
  /// facing the camera; wall fits are offset halfDepth along the normal and
  /// yawed so model +Z faces out from the wall.
  static Matrix4 refinedAnchorTransform(
    ArPlaneFit fit, {
    required bool isFloor,
    double halfDepthM = wallPanelHalfDepthM,
    Vector3? anchorAt,
    Vector3? cameraPosition,
  }) {
    final n = fit.normal;
    if (isFloor) {
      final base = anchorAt ?? fit.center;
      final pos = Vector3(base.x, projectYOntoFit(fit, base), base.z);
      final yaw = cameraPosition == null
          ? 0.0
          : faceCameraYaw(pos, cameraPosition);
      return Matrix4.identity()
        ..setTranslation(pos)
        ..rotateY(yaw);
    }
    final nxz = math.sqrt(n.x * n.x + n.z * n.z);
    final ux = nxz < 1e-6 ? 0.0 : n.x / nxz;
    final uz = nxz < 1e-6 ? 1.0 : n.z / nxz;
    final yaw = wallAnchorYaw(Vector3(n.x, n.y, n.z));
    return Matrix4.identity()
      ..setTranslation(Vector3(
        fit.center.x + ux * halfDepthM,
        fit.center.y,
        fit.center.z + uz * halfDepthM,
      ))
      ..rotateY(yaw);
  }
}
