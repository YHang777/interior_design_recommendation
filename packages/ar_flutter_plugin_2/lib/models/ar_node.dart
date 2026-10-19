import 'package:ar_flutter_plugin_2/utils/json_converters.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:json_annotation/json_annotation.dart';
import 'dart:math' as math;
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';

class ARNode {
  ARNode({
    required this.type,
    required this.uri,
    String? name,
    Vector3? position,
    Vector3? scale,
    Vector4? rotation,
    Vector3? eulerAngles,
    Matrix4? transformation,
    Map<String, dynamic>? data,
  })  : name = name ?? UniqueKey().toString(),
        transformNotifier = ValueNotifier(createTransformMatrix(
            transformation, position, scale, rotation, eulerAngles)),
        data = data ?? null;

  NodeType type;

  String uri;

  Matrix4 get transform => transformNotifier.value;

  set transform(Matrix4 matrix) {
    transformNotifier.value = matrix;
  }

  Vector3 get position => transform.getTranslation();

  set position(Vector3 value) {
    final old = Matrix4.fromFloat64List(transform.storage);
    final newT = old.clone();
    newT.setTranslation(value);
    transform = newT;
  }

  Vector3 get scale => transform.matrixScale;

  set scale(Vector3 value) {
    transform =
        Matrix4.compose(position, Quaternion.fromRotation(rotation), value);
  }

  Matrix3 get rotation => transform.getRotation();

  set rotation(Matrix3 value) {
    transform =
        Matrix4.compose(position, Quaternion.fromRotation(value), scale);
  }

  set rotationFromQuaternion(Quaternion value) {
    transform = Matrix4.compose(position, value, scale);
  }

  Vector3 get eulerAngles => transform.matrixEulerAngles;

  set eulerAngles(Vector3 value) {
    final old = Matrix4.fromFloat64List(transform.storage);
    final newT = old.clone();
    newT.matrixEulerAngles = value;
    transform = newT;
  }

  final ValueNotifier<Matrix4> transformNotifier;

  final String name;

  Map<String, dynamic>? data;

  static const _matrixValueNotifierConverter = MatrixValueNotifierConverter();

  Map<String, dynamic> toMap() => <String, dynamic>{
        'type': type.index,
        'uri': uri,
        'transformation':
            _matrixValueNotifierConverter.toJson(transformNotifier),
        'name': name,
        'data': data,
      }..removeWhere((String k, dynamic v) => v == null);

  static ARNode fromMap(Map<String, dynamic> map) {
    return ARNode(
        type: NodeType.values[map["type"]],
        uri: map["uri"] as String,
        name: map["name"] as String,
        transformation: MatrixConverter().fromJson(map["transformation"]),
        data: Map<String, dynamic>.from(map["data"]));
  }
}

Matrix4 createTransformMatrix(Matrix4? origin, Vector3? position,
    Vector3? scale, Vector4? rotation, Vector3? eulerAngles) {
  final transform = origin ?? Matrix4.identity();

  if (position != null) {
    transform.setTranslation(position);
  }
  if (rotation != null) {
    transform.rotate(
        Vector3(rotation[0], rotation[1], rotation[2]), rotation[3]);
  }
  if (eulerAngles != null) {
    transform.matrixEulerAngles = eulerAngles;
  }
  if (scale != null) {
    transform.scale(scale);
  } else {
    transform.scale(1.0);
  }
  return transform;
}

extension Matrix4Extenstion on Matrix4 {
  Vector3 get matrixScale {
    final scale = Vector3.zero();
    decompose(Vector3.zero(), Quaternion(0, 0, 0, 0), scale);
    return scale;
  }

  Vector3 get matrixEulerAngles {
    final q = Quaternion(0, 0, 0, 0);
    decompose(Vector3.zero(), q, Vector3.zero());

    final t = q.x;
    q.x = q.y;
    q.y = t;

    final angles = Vector3.zero();

    final sinrCosp = 2 * (q.w * q.x + q.y * q.z);
    final cosrCosp = 1 - 2 * (q.x * q.x + q.y * q.y);
    angles[0] = math.atan2(sinrCosp, cosrCosp);

    final sinp = 2 * (q.w * q.y - q.z * q.x);
    if (sinp.abs() >= 1) {
      angles[1] =
          _copySign(math.pi / 2, sinp);
    } else {
      angles[1] = math.asin(sinp);
    }
    final sinyCosp = 2 * (q.w * q.z + q.x * q.y);
    final cosyCosp = 1 - 2 * (q.y * q.y + q.z * q.z);
    angles[2] = math.atan2(sinyCosp, cosyCosp);

    return angles;
  }

  set matrixEulerAngles(Vector3 angles) {
    final translation = Vector3.zero();
    final scale = Vector3.zero();
    decompose(translation, Quaternion(0, 0, 0, 0), scale);
    final r = Quaternion.euler(angles[0], angles[1], angles[2]);
    setFromTranslationRotationScale(translation, r, scale);
  }
}

double _copySign(double magnitude, double sign) {

  if (sign == 0.0 || sign.isNaN || magnitude.sign == sign.sign) {
    return magnitude;
  }
  return -magnitude;
}

class MatrixValueNotifierConverter
    implements JsonConverter<ValueNotifier<Matrix4>, List<dynamic>> {
  const MatrixValueNotifierConverter();

  @override
  ValueNotifier<Matrix4> fromJson(List<dynamic> json) {
    return ValueNotifier(Matrix4.fromList(json.cast<double>()));
  }

  @override
  List<dynamic> toJson(ValueNotifier<Matrix4> matrix) {
    final list = List<double>.filled(16, 0.0);
    matrix.value.copyIntoArray(list);
    return list;
  }
}
