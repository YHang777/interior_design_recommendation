import 'dart:math';

// ── scene coordinates ──
// Plan cm map to scene meters as (x/100, y-up, y/100): +X east, +Z south,
// +Y up — same grounding the AR GLB path uses (models rest at y = 0).

class ScenePose {
  const ScenePose({
    required this.eyeX,
    required this.eyeY,
    required this.eyeZ,
    required this.targetX,
    required this.targetY,
    required this.targetZ,
    required this.fovDeg,
  });

  final double eyeX;
  final double eyeY;
  final double eyeZ;
  final double targetX;
  final double targetY;
  final double targetZ;
  final double fovDeg;
}

// Planner camera: drag to orbit around the room, pinch to dolly. Opens at
// an elevated 3/4 top view and NEVER auto-rotates.
class OrbitRig {
  OrbitRig({
    this.targetXm = 0,
    this.targetZm = 0,
    this.azimuthRad = -pi / 4,
    this.polarRad = 0.95,
    this.distanceM = 5,
    this.fovDeg = 55,
    this.maxDistanceM = 30,
  });

  factory OrbitRig.frameRoom({
    required double roomWCm,
    required double roomHCm,
  }) {
    final diag = sqrt(roomWCm * roomWCm + roomHCm * roomHCm) / 100.0;
    return OrbitRig(
      targetXm: roomWCm / 200.0,
      targetZm: roomHCm / 200.0,
      azimuthRad: -pi / 4,
      polarRad: 0.95,
      distanceM: max(2.2, diag * 0.85),
      fovDeg: 55,
      maxDistanceM: max(6.0, diag * 2.5),
    );
  }

  double targetXm;
  double targetZm;
  double azimuthRad;
  double polarRad;
  double distanceM;
  double fovDeg;
  double maxDistanceM;

  void orbit(double dAzimuthRad, double dPolarRad) {
    azimuthRad = _wrapPi(azimuthRad + dAzimuthRad);
    polarRad = (polarRad + dPolarRad).clamp(0.05, 1.45);
  }

  void dolly(double factor) {
    distanceM = (distanceM * factor).clamp(0.8, maxDistanceM);
  }

  void pan(double dXm, double dZm) {
    targetXm += dXm;
    targetZm += dZm;
  }

  ScenePose get pose {
    final horiz = distanceM * sin(polarRad);
    return ScenePose(
      eyeX: targetXm + horiz * cos(azimuthRad),
      eyeY: distanceM * cos(polarRad),
      eyeZ: targetZm + horiz * sin(azimuthRad),
      targetX: targetXm,
      targetY: 0,
      targetZ: targetZm,
      fovDeg: fovDeg,
    );
  }
}

// Orbit distance at which the whole room (plus wall thickness) fits the
// narrower of the two view angles — a portrait phone's horizontal FOV is far
// tighter than the vertical one, so a diagonal-only rule cropped the room.
double fitRoomDistanceM({
  required double roomWCm,
  required double roomHCm,
  required double fovDeg,
  required double aspect,
  double wallHeightM = 2.7,
}) {
  // The orbit pivots on the FLOOR center, and the far walls rise 2.7 m above
  // it — the bounding radius must include that height or the wall tops crop.
  final halfDiag = sqrt(roomWCm * roomWCm + roomHCm * roomHCm) / 200.0 + 0.15;
  final radius = sqrt(halfDiag * halfDiag + wallHeightM * wallHeightM);
  final halfV = fovDeg * pi / 360.0;
  final halfH = atan(tan(halfV) * (aspect > 0 ? aspect : 1.0));
  final half = min(halfV, halfH);
  return max(2.2, radius / sin(half) * 0.95);
}

// Walkthrough camera: eye at standing height over the walker, heading from
// the controller, drag-look only adds pitch.
class FirstPersonRig {
  FirstPersonRig({
    this.pitchRad = -0.08,
    this.fovDeg = 70,
    this.eyeHeightM = 1.5,
  });

  double pitchRad;
  double fovDeg;
  final double eyeHeightM;

  void look(double dPitchRad) {
    pitchRad = (pitchRad + dPitchRad).clamp(-0.6, 0.45);
  }

  void zoomFov(double deltaDeg) {
    fovDeg = (fovDeg + deltaDeg).clamp(35.0, 95.0);
  }

  // Walkthrough zoom (1 = human) narrows the lens instead of moving the eye.
  // With the viewport [aspect], zoom 1 aims for a ~75° HORIZONTAL view: a
  // portrait phone at a fixed 70° vertical saw only ~35° across, so one wall
  // filled the screen. Capped at 95° vertical to keep edges undistorted.
  void setZoom(double zoom, {double? aspect}) {
    var base = 70.0;
    if (aspect != null && aspect > 0 && aspect < 1) {
      const halfH = 37.5 * pi / 180;
      base = 2 * atan(tan(halfH) / aspect) * 180 / pi;
    }
    fovDeg = (base / zoom).clamp(35.0, 95.0);
  }

  ScenePose pose({
    required double walkerXCm,
    required double walkerYCm,
    required double headingRad,
  }) {
    final ex = walkerXCm / 100.0;
    final ez = walkerYCm / 100.0;
    final cp = cos(pitchRad);
    return ScenePose(
      eyeX: ex,
      eyeY: eyeHeightM,
      eyeZ: ez,
      targetX: ex + cos(headingRad) * cp,
      targetY: eyeHeightM + sin(pitchRad),
      targetZ: ez + sin(headingRad) * cp,
      fovDeg: fovDeg,
    );
  }
}

double _wrapPi(double a) {
  var x = a;
  while (x > pi) {
    x -= 2 * pi;
  }
  while (x < -pi) {
    x += 2 * pi;
  }
  return x;
}
