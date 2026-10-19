import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/utils/json_converters.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:vector_math/vector_math_64.dart';

class ARHitTestResult {
  ARHitTestResult(
    this.type,
    this.distance,
    this.worldTransform, {
    this.planeType,
    this.planeExtentX,
    this.planeExtentZ,
  });

  final ARHitTestResultType type;

  final double distance;

  final Matrix4 worldTransform;

  final int? planeType;

  final double? planeExtentX;

  final double? planeExtentZ;

  static ARHitTestResult fromJson(Map<String, dynamic> json) =>
      _$ARHitTestResultFromJson(json);

  Map<String, dynamic> toJson() => _$ARHitTestResultToJson(this);
}

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

class ARHitTestResultTypeConverter
    implements JsonConverter<ARHitTestResultType, int> {
  const ARHitTestResultTypeConverter();

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
