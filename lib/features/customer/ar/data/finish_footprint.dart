import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

enum FinishKind { floor, wall }

// World-space rectangle of a placed floor tile or wall panel. Used to refuse
// placements that would stack on top of an already placed finish — stacked
// patches z-fight and read as "multiple tiles together" in AR.
class FinishFootprint {
  FinishFootprint.floor({
    required Vector3 center,
    required double yaw,
    required double sizeM,
  }) : this._(FinishKind.floor, center, yaw, sizeM, sizeM);

  FinishFootprint.wall({
    required Vector3 center,
    required double yaw,
    required double widthM,
    required double heightM,
  }) : this._(FinishKind.wall, center, yaw, widthM, heightM);

  FinishFootprint._(this.kind, Vector3 center, this.yaw, this.widthM,
      this.heightM)
      : center = Vector3.copy(center);

  // Yaw convention matches placement_policy anchors: local +Z points at
  // (sin yaw, 0, cos yaw) — toward the camera for floors, out of the wall
  // for wall panels.
  factory FinishFootprint.fromTransform(
    FinishKind kind,
    Matrix4 transform, {
    required double widthM,
    required double heightM,
  }) {
    final z = transform.getColumn(2);
    return FinishFootprint._(
      kind,
      transform.getTranslation(),
      math.atan2(z.x, z.z),
      widthM,
      heightM,
    );
  }

  final FinishKind kind;

  final Vector3 center;

  final double yaw;

  // Floor patches: both sides lie in XZ (width along local X, height along
  // local Z). Wall panels: width runs along the wall, height is vertical.
  final double widthM;

  final double heightM;

  FinishFootprint withYaw(double newYaw) =>
      FinishFootprint._(kind, center, newYaw, widthM, heightM);

  FinishFootprint withCenter(Vector3 newCenter) =>
      FinishFootprint._(kind, newCenter, yaw, widthM, heightM);

  bool overlaps(FinishFootprint other, {double toleranceM = 0.03}) {
    if (other.kind != kind) return false;
    final delta = other.center - center;
    if (kind == FinishKind.floor) {
      if (delta.y.abs() >= 0.5) return false;
      return _obbOverlap(delta, other, toleranceM, vertical: false);
    }
    final n1 = _normal();
    if (n1.dot(other._normal()) < 0.7) return false;
    if (delta.dot(n1).abs() >= 0.3) return false;
    return _obbOverlap(delta, other, toleranceM, vertical: true);
  }

  Vector3 _normal() => Vector3(math.sin(yaw), 0, math.cos(yaw));

  Vector3 _tangent() => Vector3(math.cos(yaw), 0, -math.sin(yaw));

  // Separating-axis test for the two rectangles. [vertical] panels live in
  // the (tangent, Y) plane; floor patches in the (local X, local Z) plane.
  bool _obbOverlap(Vector3 delta, FinishFootprint other, double toleranceM,
      {required bool vertical}) {
    final u1 = vertical ? _tangent() : _axisX();
    final v1 = vertical ? Vector3(0, 1, 0) : _axisZ();
    final u2 = vertical ? other._tangent() : other._axisX();
    final v2 = vertical ? Vector3(0, 1, 0) : other._axisZ();
    final hu1 = widthM / 2;
    final hv1 = heightM / 2;
    final hu2 = other.widthM / 2;
    final hv2 = other.heightM / 2;
    for (final axis in [u1, v1, u2, v2]) {
      final dist = delta.dot(axis).abs();
      final e1 = hu1 * u1.dot(axis).abs() + hv1 * v1.dot(axis).abs();
      final e2 = hu2 * u2.dot(axis).abs() + hv2 * v2.dot(axis).abs();
      if (dist >= e1 + e2 - toleranceM) return false;
    }
    return true;
  }

  Vector3 _axisX() => Vector3(math.cos(yaw), 0, -math.sin(yaw));

  Vector3 _axisZ() => Vector3(math.sin(yaw), 0, math.cos(yaw));
}
