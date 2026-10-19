import 'package:ar_flutter_plugin_2/datatypes/anchor_types.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:ar_flutter_plugin_2/utils/json_converters.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:flutter/widgets.dart';

abstract class ARAnchor {
  ARAnchor({
    required this.type,
    required this.transformation,
    String? name,
  }) : name = name ?? UniqueKey().toString();

  final AnchorType type;

  final String name;

  factory ARAnchor.fromJson(Map<String, dynamic> arguments) {
    final type = arguments['type'];
    switch (type) {
      case 0:
        return ARPlaneAnchor.fromJson(arguments);
    }
    return ARUnkownAnchor.fromJson(arguments);
  }

  final Matrix4 transformation;

  Map<String, dynamic> toJson();
}

class ARPlaneAnchor extends ARAnchor {
  ARPlaneAnchor({
    required Matrix4 transformation,
    String? name,
    List<String>? childNodes,
    String? cloudanchorid,
    int? ttl,
  })  : childNodes = childNodes ?? [],
        cloudanchorid = cloudanchorid ?? null,
        ttl = ttl ?? 1,
        super(
            type: AnchorType.plane, transformation: transformation, name: name);

  List<String> childNodes;

  String? cloudanchorid;

  int? ttl;

  static ARPlaneAnchor fromJson(Map<String, dynamic> json) =>
      aRPlaneAnchorFromJson(json);

  @override
  Map<String, dynamic> toJson() => aRPlaneAnchorToJson(this);
}

ARPlaneAnchor aRPlaneAnchorFromJson(Map<String, dynamic> json) {
  return ARPlaneAnchor(
    transformation:
        const MatrixConverter().fromJson(json['transformation'] as List),
    name: json['name'] as String,
    childNodes: json['childNodes']
        ?.map((child) => child.toString())
        ?.toList()
        ?.cast<String>(),
    cloudanchorid: json['cloudanchorid'] as String?,
    ttl: json['ttl'] as int?,
  );
}

Map<String, dynamic> aRPlaneAnchorToJson(ARPlaneAnchor instance) {
  return <String, dynamic>{
    'type': instance.type.index,
    'transformation': MatrixConverter().toJson(instance.transformation),
    'name': instance.name,
    'childNodes': instance.childNodes,
    'cloudanchorid': instance.cloudanchorid,
    'ttl': instance.ttl,
  };
}

class ARUnkownAnchor extends ARAnchor {
  ARUnkownAnchor(
      {required AnchorType type, required Matrix4 transformation, String? name})
      : super(type: type, transformation: transformation, name: name);

  static ARUnkownAnchor fromJson(Map<String, dynamic> json) =>
      aRUnkownAnchorFromJson(json);

  @override
  Map<String, dynamic> toJson() => aRUnkownAnchorToJson(this);
}

ARUnkownAnchor aRUnkownAnchorFromJson(Map<String, dynamic> json) {
  return ARUnkownAnchor(
    type: json['type'],
    transformation:
        const MatrixConverter().fromJson(json['transformation'] as List),
    name: json['name'] as String,
  );
}

Map<String, dynamic> aRUnkownAnchorToJson(ARUnkownAnchor instance) {
  return <String, dynamic>{
    'type': instance.type.index,
    'transformation': MatrixConverter().toJson(instance.transformation),
    'name': instance.name,
  };
}
