import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_plane_fit.dart';
import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import 'furniture_model_library.dart';

class ArPlacementPolicy {
  const ArPlacementPolicy._();

  static const double minFloorExtentM = 0.7;

  static const double minWallExtentM = 0.8;

  static const double minPlaneExtentM = 0.3;

  static const double maxAboveLiveFloorM = 0.25;

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
    return ex >= minPlaneExtentM || ez >= minPlaneExtentM;
  }

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
      if (ex == null || ez == null) continue;
      if (ex < minFloorExtentM || ez < minFloorExtentM) continue;
      if (!distanceIsPlausible(h)) continue;
      final y = worldY(h);
      if (!y.isFinite) continue;
      if ((y - liveFloorY).abs() > maxAboveLiveFloorM) continue;
      final extent = math.max(ex, ez);
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

  static ARHitTestResult? chooseWallHit(List<ARHitTestResult> hits) {
    ARHitTestResult? best;
    double bestExtent = -1;
    for (final h in hits) {
      if (h.type != ARHitTestResultType.plane) continue;
      if (isHorizontalPlane(h)) continue;
      final ex = h.planeExtentX;
      final ez = h.planeExtentZ;
      if (ex == null || ez == null) continue;
      if (ex < minWallExtentM || ez < minWallExtentM) continue;
      if (!distanceIsPlausible(h)) continue;
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

  static ARHitTestResult? chooseAnyHit(List<ARHitTestResult> hits) {
    for (final h in hits) {
      if (h.type != ARHitTestResultType.plane) continue;
      if (!planeIsLargeEnough(h)) continue;
      if (!distanceIsPlausible(h)) continue;
      return h;
    }
    return null;
  }

  static double wallAnchorYaw(Vector3 normal) {
    final len = math.sqrt(normal.x * normal.x + normal.z * normal.z);
    if (len < 1e-6) return 0.0;
    return math.atan2(normal.x / len, normal.z / len);
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

  /// Builds an anchor transform from a RANSAC-refined plane fit, which is
  /// more accurate than ARCore's jittery plane polygon. Floor fits are placed
  /// at the fitted center with identity rotation (model is authored Y-up);
  /// wall fits are offset halfDepth along the normal and yawed so model +Z
  /// faces out from the wall.
  static Matrix4 refinedAnchorTransform(
    ArPlaneFit fit, {
    required bool isFloor,
    double halfDepthM = wallPanelHalfDepthM,
  }) {
    final n = fit.normal;
    if (isFloor) {
      return Matrix4.identity()..setTranslation(fit.center);
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
