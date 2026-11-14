import 'dart:async';

import 'package:flutter/foundation.dart';

// AR and the planner/walk-through 3D views share one native Filament
// engine. Tearing a 3D view down while an AR session is still closing
// killed ARCore's frame update (FatalException, device 2026-11-14), so
// view rebuilds wait until every AR screen has fully disposed.
class NativeSceneGuard {
  NativeSceneGuard._();

  static final ValueNotifier<int> liveArSessions = ValueNotifier<int>(0);

  static DateTime? _lastArClosedAt;

  static void arOpened() => liveArSessions.value++;

  static void arClosed() {
    if (liveArSessions.value > 0) liveArSessions.value--;
    _lastArClosedAt = DateTime.now();
  }

  // ARCore allows one camera session: a new AR screen must not create its
  // session until the previous one has released the camera.
  static Future<void> beforeArOpen({
    Duration release = const Duration(milliseconds: 1200),
  }) async {
    await settled(grace: Duration.zero);
    final closed = _lastArClosedAt;
    if (closed == null) return;
    final left = release - DateTime.now().difference(closed);
    if (left > Duration.zero) await Future<void>.delayed(left);
  }

  static Future<void> settled({
    Duration grace = const Duration(milliseconds: 600),
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (liveArSessions.value > 0) {
      final done = Completer<void>();
      void listener() {
        if (liveArSessions.value == 0 && !done.isCompleted) done.complete();
      }

      liveArSessions.addListener(listener);
      try {
        await done.future.timeout(timeout, onTimeout: () {});
      } finally {
        liveArSessions.removeListener(listener);
      }
    }
    await Future<void>.delayed(grace);
  }
}
