/// One TRACKING plane from the native side's live plane telemetry
/// (session-channel event "onPlanesUpdate"): the plane's type, world-space
/// center and polygon extent. Cheap by design — center + extent only, no
/// polygon and no pose — so the platform can stream it many times per
/// second without meaningful cost.
class ARPlaneInfo {
  const ARPlaneInfo({
    required this.planeType,
    required this.centerX,
    required this.centerY,
    required this.centerZ,
    required this.extentX,
    required this.extentZ,
  });

  /// Orientation of the PLANE: 1 = horizontal (upward-facing), 2 = vertical,
  /// 0 = other (e.g. downward-facing ceiling). Same mapping the tap path
  /// uses for [ARHitTestResult.planeType].
  final int planeType;

  /// World-space center of the plane's polygon (meters).
  final double centerX;
  final double centerY;
  final double centerZ;

  /// Plane polygon extent along its local X / Z axes, in meters.
  final double extentX;
  final double extentZ;

  /// Whether this plane is a horizontal, upward-facing surface.
  bool get isHorizontal => planeType == 1;

  /// Instantiates an [ARPlaneInfo] from the platform's serialized map.
  static ARPlaneInfo fromJson(Map<String, dynamic> json) => ARPlaneInfo(
        planeType: (json['planeType'] as num?)?.toInt() ?? 0,
        centerX: (json['centerX'] as num?)?.toDouble() ?? 0,
        centerY: (json['centerY'] as num?)?.toDouble() ?? 0,
        centerZ: (json['centerZ'] as num?)?.toDouble() ?? 0,
        extentX: (json['extentX'] as num?)?.toDouble() ?? 0,
        extentZ: (json['extentZ'] as num?)?.toDouble() ?? 0,
      );

  /// Serializes back to the platform's map shape.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'planeType': planeType,
        'centerX': centerX,
        'centerY': centerY,
        'centerZ': centerZ,
        'extentX': extentX,
        'extentZ': extentZ,
      };
}
