import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:interior_design_recommendation/features/customer/ar/data/overlay_lock.dart';

ARPlaneInfo _plane({
  int id = 1,
  double cx = 0,
  double cy = 1,
  double cz = 2,
  double ex = 1.4,
  double ez = 1.2,
  double yaw = 0,
  bool fresh = true,
}) =>
    ARPlaneInfo(
      id: id,
      planeType: 2,
      centerX: cx,
      centerY: cy,
      centerZ: cz,
      extentX: ex,
      extentZ: ez,
      yaw: yaw,
      fresh: fresh,
    );

void main() {
  final ring = [
    Vector3(-1, 0, 2),
    Vector3(1, 0, 2),
    Vector3(1, 2, 2),
    Vector3(-1, 2, 2),
  ];

  test('fresh=false observations never advance agree and never lock', () {
    final l = OverlayLock();
    for (var i = 0; i < 10; i++) {
      final locked = l.advance(_plane(fresh: false), ring: ring, smoothY: 1);
      expect(locked, isFalse,
          reason: 'cached byte-identical telemetry is not lock evidence');
    }
    expect(l.agree, 0);
    expect(l.locked, isFalse);
  });

  test('four fresh agreeing frames lock on the paint-time geometry', () {
    final l = OverlayLock();
    for (var i = 0; i < 3; i++) {
      expect(l.advance(_plane(), ring: ring, smoothY: 1.05), isFalse);
    }
    expect(l.agree, 3);
    expect(
      l.advance(_plane(), ring: ring, smoothY: 1.05),
      isTrue,
      reason: 'the fourth fresh agreement freezes the id',
    );
    expect(l.locked, isTrue);
    expect(l.centerY, closeTo(1.05, 1e-12),
        reason: 'frozen center uses the paint-time smoothY');
    expect(identical(l.polygon, ring), isTrue,
        reason: 'frozen ring is the paint-time outline');
    expect(l.centerX, closeTo(0, 1e-12));
    expect(l.yaw, closeTo(0, 1e-12));
  });

  test('an anchored streak is not fooled by pairwise-agreeing drift', () {
    final l = OverlayLock();
    // Each step is +0.04 from the previous (pairwise window 0.05) but
    // 0.12 from the anchor — the old adopt-after-check baseline drifted
    // with the frames and locked at four.
    for (final cx in [0.0, 0.04, 0.08, 0.12]) {
      l.advance(_plane(cx: cx), ring: const [], smoothY: 1);
    }
    expect(l.locked, isFalse,
        reason: 'the streak re-anchored instead of walking to a freeze');
    expect(l.agree, lessThan(4));
  });

  test('deviates fires on yaw rotation even with both rings empty', () {
    final l = OverlayLock();
    l.adopt(_plane(yaw: 0));
    expect(l.deviates(_plane(yaw: 0.2)), isTrue,
        reason: 'the yaw term must precede the empty-ring early-return');
  });

  test('deviates fires on extent growth, not just shrink', () {
    final l = OverlayLock();
    l.adopt(_plane(ex: 2.0));
    expect(l.deviates(_plane(ex: 2.5)), isTrue);
    expect(l.deviates(_plane(ex: 2.3)), isFalse,
        reason: 'within the 0.4 m tolerance');
  });

  test('within-threshold jitter keeps the lock', () {
    final l = OverlayLock();
    l.adopt(_plane());
    expect(
      l.deviates(_plane(cx: 0.1, yaw: 0.1, ex: 1.7, ez: 1.5)),
      isFalse,
      reason: 'center 0.1 m, yaw 0.1 rad, extents +0.3 all inside gates',
    );
  });

  test('agrees across the ±π yaw seam', () {
    final l = OverlayLock();
    l.adopt(_plane(yaw: 3.14));
    expect(l.agrees(_plane(yaw: -3.14)), isTrue,
        reason: 'the seam crossing is the same orientation');
    expect(l.agrees(_plane(yaw: -3.0)), isFalse,
        reason: 'a genuinely different yaw still disagrees');
  });
}
