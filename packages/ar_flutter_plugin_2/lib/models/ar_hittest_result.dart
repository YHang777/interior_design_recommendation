// The code in this file is adapted from Oleksandr Leuschenko' ARKit Flutter Plugin (https://github.com/olexale/arkit_flutter_plugin)

import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/utils/json_converters.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:vector_math/vector_math_64.dart';

/// A result (type, distance from the camera, world transformation) of an intersection found during a hit-test.
class ARHitTestResult {
  ARHitTestResult(
    this.type,
    this.distance,
    this.worldTransform, {
    this.planeType,
    this.planeExtentX,
    this.planeExtentZ,
  });

  /// The type of the hit-test result.
  final ARHitTestResultType type;

  /// The distance from the camera to the intersection in meters.
  final double distance;

  /// The transformation matrix that defines the intersection’s rotation, translation and scale
  /// relative to the world. For plane hits the rotation is the REAL plane
  /// orientation (its normal is the transformed Z/Y axis), not identity.
  final Matrix4 worldTransform;

  /// Orientation of the hit PLANE, when the platform reports it:
  /// 1 = horizontal (upward-facing), 2 = vertical, 0 = downward-facing
  /// (ceiling). Null for feature points and on platforms that predate this
  /// field — callers fall back to [worldTransform]'s normal.
  final int? planeType;

  /// Plane polygon extent along its local X axis, in meters. Null when the
  /// platform does not report it.
  final double? planeExtentX;

  /// Plane polygon extent along its local Z axis, in meters. Null when the
  /// platform does not report it.
  final double? planeExtentZ;

  /// Instantiates am [ARHitTestResult] from a serialized ARHitTestResult
  static ARHitTestResult fromJson(Map<String, dynamic> json) =>
      _$ARHitTestResultFromJson(json);

  /// Serializes the [ARHitTestResult]
  Map<String, dynamic> toJson() => _$ARHitTestResultToJson(this);
}

/// Instantiates am [ARHitTestResult] from a serialized ARHitTestResult
ARHitTestResult _$ARHitTestResultFromJson(Map<String, dynamic> json) {
  final planeExtent = json['planeExtent'];
  return ARHitTestResult(
    const ARHitTestResultTypeConverter().fromJson(json['type'] as int),
    (json['distance'] as num).toDouble(),
    const MatrixConverter().fromJson(json['worldTransform'] as List),
    planeType: (json['planeType'] as num?)?.toInt(),
    planeExtentX: (planeExtent is Map ? planeExtent['x'] as num? : null)
        ?.toDouble(),
    planeExtentZ: (planeExtent is Map ? planeExtent['z'] as num? : null)
        ?.toDouble(),
  );
}

/// Serializes the [ARHitTestResult]
Map<String, dynamic> _$ARHitTestResultToJson(ARHitTestResult instance) {
  final val = <String, dynamic>{};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull(
      'type', const ARHitTestResultTypeConverter().toJson(instance.type));
  val['distance'] = instance.distance;
  writeNotNull('worldTransform',
      const MatrixConverter().toJson(instance.worldTransform));
  writeNotNull('planeType', instance.planeType);
  if (instance.planeExtentX != null || instance.planeExtentZ != null) {
    writeNotNull('planeExtent', <String, dynamic>{
      'x': instance.planeExtentX,
      'z': instance.planeExtentZ,
    });
  }
  return val;
}

/// Helper class to convert the type of an [ARHitTestResult] from its integer representation to the [ARHitTestResultType] and vice versa
class ARHitTestResultTypeConverter
    implements JsonConverter<ARHitTestResultType, int> {
  const ARHitTestResultTypeConverter();

  /// Converts the type of an [ARHitTestResult] from its integer representation to the [ARHitTestResultType]
  @override
  ARHitTestResultType fromJson(int json) {
    switch (json) {
      case 1:
        return ARHitTestResultType.plane;
      case 2:
        return ARHitTestResultType.point;
      default:
        return ARHitTestResultType.undefined;
    }
  }

  /// Converts the type of an [ARHitTestResult] from its [ARHitTestResultType] to an integer representation
  @override
  int toJson(ARHitTestResultType object) {
    switch (object) {
      case ARHitTestResultType.plane:
        return 1;
      case ARHitTestResultType.point:
        return 2;
      default:
        return 0;
    }
  }
}
