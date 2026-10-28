import 'package:vector_math/vector_math_64.dart';

/// A plane fitted to ARCore's raw point cloud with RANSAC (see the plugin's
/// `refinePlane`). More placement-accurate than ARCore's plane polygon.
class ArPlaneFit {
  const ArPlaneFit({
    required this.center,
    required this.normal,
    required this.inlierCount,
    required this.pointCount,
    required this.rmsError,
    required this.confidence,
  });

  /// Point on the fitted plane nearest the seed (world coords).
  final Vector3 center;

  /// Unit normal of the fitted plane (world coords).
  final Vector3 normal;

  /// Number of point-cloud points that agreed with the plane.
  final int inlierCount;

  /// Total point-cloud points considered around the seed.
  final int pointCount;

  /// RMS distance of inliers to the plane, meters. Lower is tighter.
  final double rmsError;

  /// 0..1 — how planar/trustworthy the fit is. Callers can refuse low values.
  final double confidence;

  bool get isTrustworthy => confidence >= 0.35;

  static ArPlaneFit? fromMap(Map<String, dynamic> map) {
    final cx = map['centerX'] as num?;
    final cy = map['centerY'] as num?;
    final cz = map['centerZ'] as num?;
    final nx = map['normalX'] as num?;
    final ny = map['normalY'] as num?;
    final nz = map['normalZ'] as num?;
    if (cx == null || cy == null || cz == null) return null;
    if (nx == null || ny == null || nz == null) return null;
    return ArPlaneFit(
      center: Vector3(cx.toDouble(), cy.toDouble(), cz.toDouble()),
      normal: Vector3(nx.toDouble(), ny.toDouble(), nz.toDouble()),
      inlierCount: (map['inlierCount'] as num?)?.toInt() ?? 0,
      pointCount: (map['pointCount'] as num?)?.toInt() ?? 0,
      rmsError: (map['rmsError'] as num?)?.toDouble() ?? 0,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
    );
  }
}
