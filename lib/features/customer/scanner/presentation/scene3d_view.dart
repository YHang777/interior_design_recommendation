import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show StandardMessageCodec;

import '../data/scene3d_controller.dart';

// Hosts the non-AR SceneView platform view ('ar_flutter_plugin_2/scene').
// Camera control stays in the caller's rig — the native scene renders only
// and never auto-rotates.

class Scene3DView extends StatefulWidget {
  const Scene3DView({
    super.key,
    required this.controller,
    this.onTap,
    this.onLongPress,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    this.fallback,
  });

  final Scene3DController controller;

  final void Function(Offset localPosition)? onTap;

  final void Function(Offset localPosition)? onLongPress;

  final GestureScaleStartCallback? onScaleStart;

  final GestureScaleUpdateCallback? onScaleUpdate;

  final GestureScaleEndCallback? onScaleEnd;

  /// Rendered instead of the platform view where 3D is unsupported.
  final Widget? fallback;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  State<Scene3DView> createState() => _Scene3DViewState();
}

class _Scene3DViewState extends State<Scene3DView> {
  late final Map<Type, GestureRecognizerFactory> _gestures;

  @override
  void initState() {
    super.initState();
    _gestures = <Type, GestureRecognizerFactory>{
      _SceneCanvasRecognizer: GestureRecognizerFactoryWithHandlers<
          _SceneCanvasRecognizer>(
        () => _SceneCanvasRecognizer(this),
        (r) {},
      ),
    };
  }

  void _fireTap(Offset local) => widget.onTap?.call(local);

  void _fireLongPress(Offset local) => widget.onLongPress?.call(local);

  void _fireScaleStart(Offset local, int pointerCount) =>
      widget.onScaleStart?.call(ScaleStartDetails(
        localFocalPoint: local,
        pointerCount: pointerCount,
      ));

  void _fireScaleUpdate(
          Offset local, int pointerCount, double scale, Offset delta) =>
      widget.onScaleUpdate?.call(ScaleUpdateDetails(
        localFocalPoint: local,
        focalPointDelta: delta,
        scale: scale,
        pointerCount: pointerCount,
      ));

  void _fireScaleEnd(int pointerCount) => widget.onScaleEnd
      ?.call(ScaleEndDetails(velocity: Velocity.zero, pointerCount: pointerCount));

  @override
  Widget build(BuildContext context) {
    if (!Scene3DView.supported) {
      return widget.fallback ?? const SizedBox.expand();
    }
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: _gestures,
      child: AndroidView(
        viewType: 'ar_flutter_plugin_2/scene',
        creationParams: const <String, Object?>{},
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: widget.controller.bindTo,
      ),
    );
  }
}

// One recognizer owns the whole canvas: it resolves accepted on the first
// pointer down, which rejects the platform view's arena captain (that
// captain registers first and sweep is first-member-wins — any recognizer
// that waits for the sweep loses to it). The native scene is render-only
// anyway; owning the canvas also keeps enclosing scrollables from stealing
// drags meant for orbiting or looking around.
class _SceneCanvasRecognizer extends OneSequenceGestureRecognizer {
  _SceneCanvasRecognizer(this._state);

  final _Scene3DViewState _state;

  final Map<int, Offset> _pointers = {};
  Offset _startFocal = Offset.zero;
  Offset _lastFocal = Offset.zero;
  double _startSpan = 1;
  Timer? _longPressTimer;
  bool _dragging = false;
  bool _longPressFired = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    resolve(GestureDisposition.accepted);
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 1) {
      _startFocal = event.localPosition;
      _lastFocal = _startFocal;
      _longPressFired = false;
      _dragging = false;
      _longPressTimer?.cancel();
      _longPressTimer = Timer(kLongPressTimeout, _fireLongPress);
    } else if (_pointers.length == 2) {
      _longPressTimer?.cancel();
      if (_dragging) {
        _dragging = false;
        _state._fireScaleEnd(1);
      }
      _startSpan = _span();
      _lastFocal = _focal();
      _state._fireScaleStart(_lastFocal, 2);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      final pos = _pointers[event.pointer];
      if (pos == null) return;
      _pointers[event.pointer] = event.localPosition;
      if (_pointers.length >= 2) {
        final focal = _focal();
        final span = _span();
        _state._fireScaleUpdate(
          focal,
          _pointers.length,
          _startSpan > 0 ? span / _startSpan : 1,
          focal - _lastFocal,
        );
        _lastFocal = focal;
      } else {
        if (!_dragging &&
            (event.localPosition - _startFocal).distance > kTouchSlop) {
          _longPressTimer?.cancel();
          _dragging = true;
          _state._fireScaleStart(_startFocal, 1);
        }
        if (_dragging) {
          _state._fireScaleUpdate(
            event.localPosition,
            1,
            1,
            event.localPosition - _lastFocal,
          );
          _lastFocal = event.localPosition;
        }
      }
    } else if (event is PointerUpEvent) {
      if (!_pointers.containsKey(event.pointer)) return;
      // stopTrackingPointer fires didStopTrackingLastPointer synchronously,
      // so every decision must read state captured before it runs.
      final wasCount = _pointers.length;
      final wasDragging = _dragging;
      final wasLongPress = _longPressFired;
      _pointers.remove(event.pointer);
      if (_pointers.isEmpty) {
        _longPressTimer?.cancel();
        if (wasDragging) {
          _dragging = false;
          _state._fireScaleEnd(1);
        } else if (wasCount >= 2) {
          _state._fireScaleEnd(wasCount);
        } else if (!wasLongPress) {
          _state._fireTap(event.localPosition);
        }
        _longPressFired = false;
      } else if (_pointers.length == 1 && wasCount >= 2) {
        // Pinch lifted to one finger: hand over to a fresh one-finger drag.
        _state._fireScaleEnd(wasCount);
        _lastFocal = _focal();
        _startFocal = _lastFocal;
        _dragging = true;
        _state._fireScaleStart(_lastFocal, 1);
      }
      stopTrackingPointer(event.pointer);
    } else if (event is PointerCancelEvent) {
      if (!_pointers.containsKey(event.pointer)) return;
      final wasCount = _pointers.length;
      final wasDragging = _dragging;
      _pointers.remove(event.pointer);
      _longPressTimer?.cancel();
      if (wasDragging || wasCount >= 2) {
        _state._fireScaleEnd(wasCount);
      }
      _dragging = false;
      _longPressFired = true;
      stopTrackingPointer(event.pointer);
    }
  }

  void _fireLongPress() {
    if (_pointers.length == 1 && !_dragging && !_longPressFired) {
      _longPressFired = true;
      _state._fireLongPress(_startFocal);
    }
  }

  Offset _focal() {
    if (_pointers.length < 2) return _pointers.values.first;
    final sorted = _pointers.keys.toList()..sort();
    return (_pointers[sorted[0]]! + _pointers[sorted[1]]!) / 2;
  }

  double _span() {
    if (_pointers.length < 2) return 1;
    final sorted = _pointers.keys.toList()..sort();
    return (_pointers[sorted[0]]! - _pointers[sorted[1]]!).distance;
  }

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {
    _pointers.remove(pointer);
    _longPressTimer?.cancel();
    if (_dragging) {
      _dragging = false;
      _state._fireScaleEnd(1);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointers.clear();
    _longPressTimer?.cancel();
    _dragging = false;
    _longPressFired = false;
  }

  @override
  String get debugDescription => 'scene3d canvas';
}
