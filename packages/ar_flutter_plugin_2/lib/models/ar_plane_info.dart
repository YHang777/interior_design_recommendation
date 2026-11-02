class ARPlaneInfo {
  const ARPlaneInfo({
    required this.planeType,
    required this.centerX,
    required this.centerY,
    required this.centerZ,
    required this.extentX,
    required this.extentZ,
    this.id = 0,
    this.yaw = 0,
    this.polygon = const [],
  });

  // Stable per-session id minted by the plugin (0 when not reported).
  final int id;

  final int planeType;

  final double centerX;

  final double centerY;

  final double centerZ;

  // extentX spans the [yaw] direction; extentZ spans the in-plane
  // perpendicular (world up, when [planeType] is 2).
  final double extentX;

  final double extentZ;

  // Horizontal orientation of the plane in radians: the local +Z yaw for
  // horizontal planes (+Z → (sin yaw, 0, cos yaw)), the outward-normal yaw
  // for vertical ones.
  final double yaw;

  // ARCore's real outline as world-space xyz triplets (flat, multiples of
  // 3). Empty when the plugin doesn't report one — callers then fall back
  // to the center/extents rectangle.
  final List<double> polygon;

  bool get isHorizontal => planeType == 1;

  static ARPlaneInfo fromJson(Map<String, dynamic> json) => ARPlaneInfo(
        id: (json['id'] as num?)?.toInt() ?? 0,
        planeType: (json['planeType'] as num?)?.toInt() ?? 0,
        centerX: (json['centerX'] as num?)?.toDouble() ?? 0,
        centerY: (json['centerY'] as num?)?.toDouble() ?? 0,
        centerZ: (json['centerZ'] as num?)?.toDouble() ?? 0,
        extentX: (json['extentX'] as num?)?.toDouble() ?? 0,
        extentZ: (json['extentZ'] as num?)?.toDouble() ?? 0,
        yaw: (json['yaw'] as num?)?.toDouble() ?? 0,
        polygon: (json['polygon'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'planeType': planeType,
        'centerX': centerX,
        'centerY': centerY,
        'centerZ': centerZ,
        'extentX': extentX,
        'extentZ': extentZ,
        'yaw': yaw,
        'polygon': polygon,
      };
}
