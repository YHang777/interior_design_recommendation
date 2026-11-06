import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';

import 'placement_policy.dart';

enum ScanCoachStep {
  findFloor,
  sweepFloor,
  expandCoverage,
  findWall,
  sweepWall,
  ready,
}

class ScanCoachState {
  const ScanCoachState({
    required this.step,
    required this.ready,
    required this.progress,
    required this.tip,
    this.hasIssue = false,
    this.wall = false,
  });

  final ScanCoachStep step;

  final bool ready;

  final double progress;

  final String tip;

  final bool hasIssue;

  // True when the user is placing something on a wall — the overlay shows
  // the wall step ladder instead of the floor one.
  final bool wall;
}

class ScanCoach {
  const ScanCoach._();

  static const double sweepDoneCoverageM = 0.45;

  // Horizontal planes this far above the known floor are furniture tops —
  // they must not count as floor coverage.
  static const double floorLevelToleranceM = 0.3;

  // While the floor height is still unknown, a surface only counts as
  // coverage when it sits this far below the phone — the strict band
  // mirrors PlaneMemory's camera-height prior, so desks / beds are not
  // mistaken for the floor before floorY exists.
  static const double plausibleFloorBelowMinM = 0.85;
  static const double plausibleFloorBelowMaxM = 2.4;

  static const Duration stillHintAfter = Duration(seconds: 4);

  // Below this many degrees under the horizon the camera barely sees the
  // floor — ARCore needs the floor in frame to detect or grow it.
  static const double shallowPitchDeg = -20;

  static ScanCoachState evaluate({
    required List<ARPlaneInfo> planes,
    required Duration elapsed,
    String? trackingIssue,
    double? floorY,
    double? floorCoverageM,
    double? cameraY,
    double? cameraPitchDeg,
    bool wall = false,
  }) {
    if (wall) return _evaluateWall(planes, elapsed, trackingIssue);
    // Coverage = the smaller extent of the best FLOOR-level plane — the same
    // gate placement uses (both axes must fit the item footprint). A table
    // top scanned before the floor must not fake "Ready". [floorCoverageM]
    // is the plane memory's merged floor region, which several small ARCore
    // patches accumulate into — it can only raise coverage, never lower it.
    var coverage = 0.0;
    var sawPlane = false;
    var sawElevated = false;
    for (final p in planes) {
      if (!p.isHorizontal) continue;
      if (floorY != null && (p.centerY - floorY).abs() > floorLevelToleranceM) {
        sawElevated = true;
        continue;
      }
      if (floorY == null && cameraY != null) {
        final below = cameraY - p.centerY;
        if (below < plausibleFloorBelowMinM || below > plausibleFloorBelowMaxM) {
          continue;
        }
      }
      sawPlane = true;
      final c = math.min(p.extentX, p.extentZ);
      if (c > coverage) coverage = c;
    }
    if (floorCoverageM != null && floorCoverageM > coverage) {
      coverage = floorCoverageM;
      sawPlane = true;
    }
    // Long scans on small / fragmented floors drop to the relaxed gate —
    // never keep "keep sweeping" over a room that will never reach 1.0 m.
    final relaxed = elapsed >= ArPlacementPolicy.relaxGatesAfter;
    final gate = relaxed
        ? ArPlacementPolicy.minFloorExtentRelaxedM
        : ArPlacementPolicy.minFloorExtentM;
    // Ready means placement can actually work: enough coverage AND an
    // established floor height — placement refuses without floorY, so the
    // coach must not promise "Ready" over a desk or a still-unconfirmed
    // floor.
    final ready = coverage >= gate && floorY != null;
    final progress = (coverage / gate).clamp(0.0, 1.0);
    final ScanCoachStep step;
    if (ready) {
      step = ScanCoachStep.ready;
    } else if (coverage >= sweepDoneCoverageM) {
      step = ScanCoachStep.expandCoverage;
    } else if (coverage >= ArPlacementPolicy.minPlaneExtentM) {
      step = ScanCoachStep.sweepFloor;
    } else {
      step = ScanCoachStep.findFloor;
    }
    final issue = issueTip(trackingIssue);
    // Tracking trouble first, then the angle the user is holding the phone
    // at — a shallow camera is usually WHY nothing else is happening.
    final pitch = ready ? null : pitchTip(cameraPitchDeg);
    return ScanCoachState(
      step: step,
      ready: ready,
      progress: progress,
      tip: issue ??
          pitch ??
          _baseTip(step,
              elapsed: elapsed, sawPlane: sawPlane, sawElevated: sawElevated),
      hasIssue: issue != null,
    );
  }

  // Wall placement: ARCore vertical planes are the whole game here (and
  // the weakest link on white walls), so the ladder tracks the wall gates
  // both placement uses — no floor-height requirement, no floor pitch tip.
  static ScanCoachState _evaluateWall(
    List<ARPlaneInfo> planes,
    Duration elapsed,
    String? trackingIssue,
  ) {
    var wallProgress = 0.0;
    for (final p in planes) {
      if (p.planeType != 2) continue;
      final a =
          math.min(p.extentX, p.extentZ) / ArPlacementPolicy.minWallExtentM;
      final b =
          math.max(p.extentX, p.extentZ) / ArPlacementPolicy.minWallLongExtentM;
      final prog = math.min(a, b).clamp(0.0, 1.0);
      if (prog > wallProgress) wallProgress = prog;
    }
    final ready = wallProgress >= 1.0;
    final step = ready
        ? ScanCoachStep.ready
        : wallProgress > 0
            ? ScanCoachStep.sweepWall
            : ScanCoachStep.findWall;
    final issue = issueTip(trackingIssue);
    return ScanCoachState(
      step: step,
      ready: ready,
      progress: wallProgress,
      wall: true,
      tip: issue ?? _wallTip(step, elapsed),
      hasIssue: issue != null,
    );
  }

  static String _wallTip(ScanCoachStep step, Duration elapsed) {
    switch (step) {
      case ScanCoachStep.findWall:
        return 'Aim at the wall — a corner or floor junction gives ARCore an edge';
      case ScanCoachStep.sweepWall:
        return _rotate(elapsed, const [
          'Move left and right along the wall — ARCore needs two viewing angles',
          'Step back 1–2 m so a full wall section is in view',
          'Plain paint is hard — angle across it so light reveals texture',
        ]);
      case ScanCoachStep.ready:
        return 'Ready — tap the wall to place';
      default:
        return 'Aim at the wall';
    }
  }

  // White-surface advice rotates in after the plain tip has had its turn —
  // textureless floors/walls are the #1 failure and parallax/lighting is
  // what actually fixes them. First entry is always the classic tip so the
  // early-session copy is unchanged.
  static String _rotate(Duration elapsed, List<String> tips) {
    if (tips.length == 1) return tips.first;
    final idx = (elapsed.inSeconds ~/ 6) % tips.length;
    return tips[idx];
  }

  // Concrete hold-angle advice while the phone is aimed near the horizon.
  // Null when the reading is missing/stale or the angle is already fine.
  static String? pitchTip(double? pitchDeg) {
    if (pitchDeg == null || !pitchDeg.isFinite) return null;
    if (pitchDeg > shallowPitchDeg) {
      return 'Point the camera down about 30° toward the floor';
    }
    return null;
  }

  static String _baseTip(
    ScanCoachStep step, {
    required Duration elapsed,
    required bool sawPlane,
    bool sawElevated = false,
  }) {
    switch (step) {
      case ScanCoachStep.findFloor:
        if (!sawPlane && sawElevated) {
          return 'That looks like furniture — scan the open floor';
        }
        if (!sawPlane && elapsed >= stillHintAfter) {
          return _rotate(elapsed, const [
            'Check the lighting and hold still',
            'Move slowly side to side — white floors need parallax',
            'Aim near a rug, edge, or seam for something to lock onto',
          ]);
        }
        return 'Tilt down until the floor fills the view';
      case ScanCoachStep.sweepFloor:
        return _rotate(elapsed, const [
          'Sweep slowly side to side — about a second each way',
          'Kneel and view the floor at about 30° so shadows give it texture',
          'Avoid glare — even a little texture helps ARCore lock on',
        ]);
      case ScanCoachStep.expandCoverage:
        return _rotate(elapsed, const [
          'Keep sweeping a little wider',
          'White floors are hard — walk the perimeter slowly',
          'Point at where the floor meets the wall for a clear edge',
        ]);
      case ScanCoachStep.ready:
        return 'Ready — tap the floor to place';
      // Wall steps never reach the floor path — evaluate() branches first.
      case ScanCoachStep.findWall:
      case ScanCoachStep.sweepWall:
        return 'Tilt down until the floor fills the view';
    }
  }

  static String? issueTip(String? reason) {
    switch (reason) {
      case 'EXCESSIVE_MOTION':
        return 'Slow down — your movements are too fast';
      case 'INSUFFICIENT_FEATURES':
        return 'Aim at a textured floor, not plain tiles';
      case 'INSUFFICIENT_LIGHT':
        return 'Too dark — move to a brighter spot';
      case 'CAMERA_UNAVAILABLE':
        return 'Camera is busy — close other camera apps';
      default:
        return null;
    }
  }
}
