import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';

import 'placement_policy.dart';

enum ScanCoachStep { findFloor, sweepFloor, expandCoverage, ready }

class ScanCoachState {
  const ScanCoachState({
    required this.step,
    required this.ready,
    required this.progress,
    required this.tip,
    this.hasIssue = false,
  });

  final ScanCoachStep step;

  final bool ready;

  final double progress;

  final String tip;

  final bool hasIssue;
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

  static ScanCoachState evaluate({
    required List<ARPlaneInfo> planes,
    required Duration elapsed,
    String? trackingIssue,
    double? floorY,
    double? floorCoverageM,
    double? cameraY,
  }) {
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
    return ScanCoachState(
      step: step,
      ready: ready,
      progress: progress,
      tip: issue ??
          _baseTip(step,
              elapsed: elapsed, sawPlane: sawPlane, sawElevated: sawElevated),
      hasIssue: issue != null,
    );
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
          return 'Check the lighting and hold still';
        }
        return 'Tilt down until the floor fills the view';
      case ScanCoachStep.sweepFloor:
        return 'Sweep slowly side to side — about a second each way';
      case ScanCoachStep.expandCoverage:
        return 'Keep sweeping a little wider';
      case ScanCoachStep.ready:
        return 'Ready — tap the floor to place';
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
