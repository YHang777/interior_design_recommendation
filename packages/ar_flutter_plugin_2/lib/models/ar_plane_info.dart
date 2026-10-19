class ARPlaneInfo {
  const ARPlaneInfo({
    required this.planeType,
    required this.centerX,
    required this.centerY,
    required this.centerZ,
    required this.extentX,
    required this.extentZ,
  });

  final int planeType;

  final double centerX;
  final double centerY;
  final double centerZ;

  final double extentX;
  final double extentZ;

  bool get isHorizontal => planeType == 1;

  static ARPlaneInfo fromJson(Map<String, dynamic> json) => ARPlaneInfo(
        planeType: (json['planeType'] as num?)?.toInt() ?? 0,
        centerX: (json['centerX'] as num?)?.toDouble() ?? 0,
        centerY: (json['centerY'] as num?)?.toDouble() ?? 0,
        centerZ: (json['centerZ'] as num?)?.toDouble() ?? 0,
        extentX: (json['extentX'] as num?)?.toDouble() ?? 0,
        extentZ: (json['extentZ'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'planeType': planeType,
        'centerX': centerX,
        'centerY': centerY,
        'centerZ': centerZ,
        'extentX': extentX,
        'extentZ': extentZ,
      };
}
