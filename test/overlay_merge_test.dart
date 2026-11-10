import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interior_design_recommendation/features/customer/ar/data/overlay_merge.dart';

ARPlaneInfo _p({int id = 1, bool fresh = true}) => ARPlaneInfo(
      id: id,
      planeType: 2,
      centerX: 0,
      centerY: 1,
      centerZ: 2,
      extentX: 1.4,
      extentZ: 1.2,
      yaw: 0,
      fresh: fresh,
    );

void main() {
  test('a held-only plane is re-presented as fresh=false', () {
    final merged = mergeOverlayPlanes(
      live: [_p(id: 1)],
      held: [_p(id: 2)],
      synthetics: const [],
    );
    final heldOnly = merged.singleWhere((p) => p.id == 2);
    expect(heldOnly.fresh, isFalse,
        reason: 'out of the payload means not updating — cached bytes '
            'agreeing with themselves are not lock evidence');
    expect(merged.first.id, 1);
    expect(merged.first.fresh, isTrue,
        reason: 'live telemetry keeps its own flag');
  });

  test('a live id wins over its held twin and is not duplicated', () {
    final merged = mergeOverlayPlanes(
      live: [_p(id: 1)],
      held: [_p(id: 1, fresh: false)],
      synthetics: [_p(id: 900001)],
    );
    expect(merged.map((p) => p.id), [1, 900001]);
    expect(merged.first.fresh, isTrue);
  });

  test('synthetics keep fresh=true and ride after held geometry', () {
    final merged = mergeOverlayPlanes(
      live: const [],
      held: [_p(id: 2)],
      synthetics: [_p(id: 900001)],
    );
    expect(merged.map((p) => p.id), [2, 900001]);
    expect(merged.last.fresh, isTrue,
        reason: 'synthetics stay lockable — the ≥900001 lock-log tag '
            'depends on it');
    expect(merged.first.fresh, isFalse);
  });

  test('an already-stale held plane passes through unchanged', () {
    final stale = _p(id: 2, fresh: false);
    final merged = mergeOverlayPlanes(
      live: const [],
      held: [stale],
      synthetics: const [],
    );
    expect(identical(merged.single, stale), isTrue);
  });
}
