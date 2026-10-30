import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';

import 'furniture_model_library.dart';
import 'placement_policy.dart';

enum ReticleStatus { searching, locked, tooFar, tooClose, noFloorYet }

class ReticleState {
  const ReticleState(this.status, {this.distanceM});

  final ReticleStatus status;

  final double? distanceM;
}

class ReticleAdvisor {
  const ReticleAdvisor._();

  static ReticleState evaluate({
    required List<ARHitTestResult> hits,
    required PlacementType intent,
    double? liveFloorY,
    bool Function(ARHitTestResult hit)? vouchedFloor,
    bool Function(ARHitTestResult hit)? vouchedWall,
  }) {
    ARHitTestResult? chosen;
    switch (intent) {
      case PlacementType.floor:
        if (liveFloorY == null) {
          return const ReticleState(ReticleStatus.noFloorYet);
        }
        chosen = ArPlacementPolicy.chooseFloorHit(hits,
            liveFloorY: liveFloorY, vouchedFloor: vouchedFloor);
        break;
      case PlacementType.wall:
        chosen = ArPlacementPolicy.chooseWallHit(hits, vouchedWall: vouchedWall);
        break;
      case PlacementType.any:
        chosen = ArPlacementPolicy.chooseAnyHit(hits,
            liveFloorY: liveFloorY,
            vouchedFloor: vouchedFloor,
            vouchedWall: vouchedWall);
        break;
    }
    if (chosen != null) {
      return ReticleState(ReticleStatus.locked, distanceM: chosen.distance);
    }
    final oriented = hits.where((h) {
      if (h.type != ARHitTestResultType.plane) return false;
      switch (intent) {
        case PlacementType.floor:
          return ArPlacementPolicy.isHorizontalPlane(h);
        case PlacementType.wall:
          return !ArPlacementPolicy.isHorizontalPlane(h);
        case PlacementType.any:
          return true;
      }
    }).toList();
    if (oriented.isEmpty) {
      return const ReticleState(ReticleStatus.searching);
    }
    final tooFar = oriented
        .where((h) => h.distance > ArPlacementPolicy.maxPlacementDistanceM);
    if (tooFar.isNotEmpty) {
      return ReticleState(ReticleStatus.tooFar, distanceM: tooFar.first.distance);
    }
    final tooClose = oriented
        .where((h) => h.distance < ArPlacementPolicy.minPlacementDistanceM);
    if (tooClose.isNotEmpty) {
      return ReticleState(ReticleStatus.tooClose,
          distanceM: tooClose.first.distance);
    }
    return const ReticleState(ReticleStatus.searching);
  }
}
