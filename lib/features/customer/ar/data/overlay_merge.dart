import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';

// Live telemetry first, then held geometry the payload dropped, then our
// synthetic cloud walls. A held copy's fresh flag froze at its last
// emission — out of the payload means not updating — so it is presented
// as fresh=false: byte-identical cached reads are not observations and
// must not advance the lock streak (B2c). Synthetics keep their flag;
// they are derived from the current cloud and the ≥900001 lock-log tag
// relies on them staying lockable.
List<ARPlaneInfo> mergeOverlayPlanes({
  required List<ARPlaneInfo> live,
  required Iterable<ARPlaneInfo> held,
  required Iterable<ARPlaneInfo> synthetics,
}) {
  final liveIds = {for (final p in live) p.id};
  return [
    ...live,
    for (final p in held)
      if (!liveIds.contains(p.id)) _asHeld(p),
    ...synthetics,
  ];
}

ARPlaneInfo _asHeld(ARPlaneInfo p) => p.fresh
    ? ARPlaneInfo(
        id: p.id,
        planeType: p.planeType,
        centerX: p.centerX,
        centerY: p.centerY,
        centerZ: p.centerZ,
        extentX: p.extentX,
        extentZ: p.extentZ,
        yaw: p.yaw,
        polygon: p.polygon,
        fresh: false,
        tracking: p.tracking,
        subsumed: p.subsumed,
      )
    : p;
