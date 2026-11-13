import 'package:flutter/services.dart';

import 'camera_rig.dart' show ScenePose;

// Channel wrapper for the non-AR SceneView platform view
// ('ar_flutter_plugin_2/scene'). All camera math stays in Dart — poses go
// over the wire, transforms come back as maps.

class SceneModel {
  const SceneModel({
    required this.id,
    required this.source,
    this.fromAsset = true,
    this.xM = 0,
    this.yM = 0,
    this.zM = 0,
    this.yawDeg = 0,
    this.scaleX = 1,
    this.scaleY = 1,
    this.scaleZ = 1,
    this.castShadows = true,
  });

  final String id;

  /// Flutter asset key, or an absolute file path when [fromAsset] is false.
  final String source;

  final bool fromAsset;

  /// World position of the model's grounded origin, meters.
  final double xM;

  final double yM;

  final double zM;

  /// Euler yaw around +Y in degrees (plan rotation maps to −rotation).
  final double yawDeg;

  final double scaleX;

  final double scaleY;

  final double scaleZ;

  // Off for the walkthrough ceiling — it would shade the whole room from the
  // key light.
  final bool castShadows;

  Map<String, Object?> toArgs({bool includeSource = true}) => {
        'id': id,
        if (includeSource) ...{
          'source': source,
          'sourceType': fromAsset ? 'asset' : 'file',
        },
        'x': xM,
        'y': yM,
        'z': zM,
        'yawDeg': yawDeg,
        'scale': [scaleX, scaleY, scaleZ],
        if (!castShadows) 'castShadows': false,
      };
}

class SceneHit {
  const SceneHit({
    required this.id,
    required this.distanceM,
    required this.xM,
    required this.yM,
    required this.zM,
  });

  final String id;

  final double distanceM;

  final double xM;

  final double yM;

  final double zM;

  factory SceneHit.fromMap(Map<Object?, Object?> map) => SceneHit(
        id: map['id'] as String,
        distanceM: (map['distance'] as num).toDouble(),
        xM: (map['x'] as num).toDouble(),
        yM: (map['y'] as num).toDouble(),
        zM: (map['z'] as num).toDouble(),
      );
}

class Scene3DController {
  Scene3DController({int? viewId}) : _viewId = viewId;

  int? _viewId;

  MethodChannel? _channel;

  /// Fires when a platform view binds — syncs queued before the view existed
  /// were dropped, so the owner must re-push scene state here.
  void Function(int viewId)? onBind;

  void bindTo(int viewId) {
    if (_viewId == viewId) return;
    _viewId = viewId;
    _channel = null;
    onBind?.call(viewId);
  }

  /// Whether a platform view is bound — pushes before [bindTo] are dropped
  /// silently, so callers must not record them as delivered.
  bool get isBound => _viewId != null;

  MethodChannel? get _ch {
    final id = _viewId;
    if (id == null) return null;
    return _channel ??= MethodChannel('scene3d_$id');
  }

  Future<void> setCamera(ScenePose pose) =>
      _invoke('setCamera', {
        'eye': [pose.eyeX, pose.eyeY, pose.eyeZ],
        'target': [pose.targetX, pose.targetY, pose.targetZ],
        'up': [0.0, 1.0, 0.0],
        'fovDeg': pose.fovDeg,
      });

  Future<void> addModel(SceneModel model) =>
      _invoke('addModel', model.toArgs());

  Future<void> updateModel(SceneModel model) =>
      _invoke('updateModel', model.toArgs(includeSource: false));

  Future<void> removeModel(String id) => _invoke('removeModel', {'id': id});

  Future<void> clearModels() => _invoke('clearModels', null);

  Future<List<SceneHit>> hitTest(Offset local) async {
    final ch = _ch;
    if (ch == null) return const [];
    final raw = await ch.invokeMethod<List<Object?>>('hitTest', {
      'x': local.dx,
      'y': local.dy,
    });
    return (raw ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(SceneHit.fromMap)
        .toList();
  }

  Future<Offset?> worldToScreen(double xM, double yM, double zM) async {
    final ch = _ch;
    if (ch == null) return null;
    final raw = await ch.invokeMethod<Map<Object?, Object?>>('worldToScreen', {
      'x': xM,
      'y': yM,
      'z': zM,
    });
    if (raw == null) return null;
    return Offset(
      (raw['x'] as num).toDouble(),
      (raw['y'] as num).toDouble(),
    );
  }

  Future<void> _invoke(String method, Object? args) async {
    final ch = _ch;
    if (ch == null) return;
    await ch.invokeMethod<void>(method, args);
  }
}
