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

  static const Duration stillHintAfter = Duration(seconds: 4);

  static ScanCoachState evaluate({
    required List<ARPlaneInfo> planes,
    required Duration elapsed,
    String? trackingIssue,
  }) {
    // Coverage = the smaller extent of the best floor plane — the same gate
    // placement uses (both axes must fit the item footprint).
    var coverage = 0.0;
    var sawPlane = false;
    for (final p in planes) {
      if (!p.isHorizontal) continue;
      sawPlane = true;
      final c = math.min(p.extentX, p.extentZ);
      if (c > coverage) coverage = c;
    }
    final ready = coverage >= ArPlacementPolicy.minFloorExtentM;
    final progress =
        (coverage / ArPlacementPolicy.minFloorExtentM).clamp(0.0, 1.0);
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
      tip: issue ?? _baseTip(step, elapsed: elapsed, sawPlane: sawPlane),
      hasIssue: issue != null,
    );
  }

  static String _baseTip(
    ScanCoachStep step, {
    required Duration elapsed,
    required bool sawPlane,
  }) {
    switch (step) {
      case ScanCoachStep.findFloor:
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
