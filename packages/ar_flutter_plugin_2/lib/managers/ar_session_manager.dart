import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:ar_flutter_plugin_2/models/ar_plane_fit.dart';
import 'package:ar_flutter_plugin_2/utils/json_converters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart';

typedef ARHitResultHandler = void Function(List<ARHitTestResult> hits);
typedef ARPlaneResultHandler = void Function(int planeCount);
// viewProjection ships with the planes from the SAME frame (null only for a
// stale native side that still sends the bare list).
typedef ARPlanesUpdateHandler = void Function(
  List<ARPlaneInfo> planes,
  Matrix4? viewProjection,
);
typedef ErrorHandler = void Function(String error);
typedef TrackingFailureHandler = void Function(String? reason);

class ARSessionManager {
  late MethodChannel _channel;

  final bool debug;

  final BuildContext buildContext;

  final PlaneDetectionConfig planeDetectionConfig;

  late ARHitResultHandler onPlaneOrPointTap;

  late ARPlaneResultHandler onPlaneDetected;

  ARPlanesUpdateHandler? onPlanesUpdate;

  ErrorHandler? onError;

  TrackingFailureHandler? onTrackingFailure;

  ARSessionManager(int id, this.buildContext, this.planeDetectionConfig,
      {this.debug = false}) {
    _channel = MethodChannel('arsession_$id');
    _channel.setMethodCallHandler(_platformCallHandler);
    if (debug) {
      print("ARSessionManager initialized");
    }
  }

  Future<Matrix4?> getCameraPose() async {
    try {
      final serializedCameraPose =
          await _channel.invokeMethod<List<dynamic>>('getCameraPose', {});
      return MatrixConverter().fromJson(serializedCameraPose!);
    } catch (e) {
      print('Error caught: ' + e.toString());
      return null;
    }
  }

  // World → clip matrix for drawing over the camera feed (projection * view,
  // display orientation included), or null when the camera isn't ready.
  Future<Matrix4?> getCameraViewProjection() async {
    try {
      final raw =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getCameraMatrices', {});
      if (raw == null) return null;
      final projection = Matrix4.fromList(
          (raw['projection'] as List<dynamic>).cast<double>());
      final view =
          Matrix4.fromList((raw['view'] as List<dynamic>).cast<double>());
      return projection * view;
    } catch (e) {
      if (debug) print('getCameraViewProjection error: $e');
      return null;
    }
  }

  Future<Matrix4?> getPose(ARAnchor anchor) async {
    try {
      if (anchor.name.isEmpty) {
        throw Exception("Anchor can not be resolved. Anchor name is empty.");
      }
      final serializedCameraPose =
          await _channel.invokeMethod<List<dynamic>>('getAnchorPose', {
        "anchorId": anchor.name,
      });
      return MatrixConverter().fromJson(serializedCameraPose!);
    } catch (e) {
      print('Error caught: ' + e.toString());
      return null;
    }
  }

  Future<double?> getDistanceBetweenAnchors(
      ARAnchor anchor1, ARAnchor anchor2) async {
    var anchor1Pose = await getPose(anchor1);
    var anchor2Pose = await getPose(anchor2);
    var anchor1Translation = anchor1Pose?.getTranslation();
    var anchor2Translation = anchor2Pose?.getTranslation();
    if (anchor1Translation != null && anchor2Translation != null) {
      return getDistanceBetweenVectors(anchor1Translation, anchor2Translation);
    } else {
      return null;
    }
  }

  Future<double?> getDistanceFromAnchor(ARAnchor anchor) async {
    Matrix4? cameraPose = await getCameraPose();
    Matrix4? anchorPose = await getPose(anchor);
    Vector3? cameraTranslation = cameraPose?.getTranslation();
    Vector3? anchorTranslation = anchorPose?.getTranslation();
    if (anchorTranslation != null && cameraTranslation != null) {
      return getDistanceBetweenVectors(anchorTranslation, cameraTranslation);
    } else {
      return null;
    }
  }

  double getDistanceBetweenVectors(Vector3 vector1, Vector3 vector2) {
    num dx = vector1.x - vector2.x;
    num dy = vector1.y - vector2.y;
    num dz = vector1.z - vector2.z;
    double distance = sqrt(dx * dx + dy * dy + dz * dz);
    return distance;
  }

  void disableCamera() {
    _channel.invokeMethod<void>('disableCamera');
  }

  void enableCamera() {
    _channel.invokeMethod<void>('enableCamera');
  }

  void showPlanes(bool showPlanes){
    _channel.invokeMethod<void>('showPlanes', {
    "showPlanes": showPlanes,
    });
  }

  /// Fits a plane to ARCore's raw point cloud around [seed] and returns a
  /// refined surface (center + unit normal + confidence in 0..1), or null if
  /// there wasn't enough data to fit. This is more accurate than ARCore's
  /// plane polygon for placement, and the confidence lets callers refuse
  /// cluttered / untrustworthy surfaces.
  Future<ArPlaneFit?> refinePlane({
    required Vector3 seed,
    double radiusM = 0.6,
    bool wantHorizontal = true,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'refinePlane',
        {
          'seedX': seed.x,
          'seedY': seed.y,
          'seedZ': seed.z,
          'radiusM': radiusM,
          'wantHorizontal': wantHorizontal,
        },
      );
      if (raw == null) return null;
      return ArPlaneFit.fromMap(Map<String, dynamic>.from(raw));
    } catch (e) {
      if (debug) print('refinePlane error: $e');
      return null;
    }
  }

  // Low-percentile Y of accumulated point-cloud samples near [floorY],
  // or null when there aren't enough points to trust. The cloud keeps
  // receiving raw depth while plane telemetry goes quiet, so this is the
  // refocus signal that sees the real floor without any plane update.
  Future<double?> probeFloorY({
    required double floorY,
    double radiusM = 2.5,
    int minPoints = 12,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'probeFloorY',
        {
          'floorY': floorY,
          'radiusM': radiusM,
          'minPoints': minPoints,
        },
      );
      if (raw == null) return null;
      final y = (raw['y'] as num?)?.toDouble();
      return y != null && y.isFinite ? y : null;
    } catch (e) {
      if (debug) print('probeFloorY error: $e');
      return null;
    }
  }

  // Flat world xyz triplets from the accumulated feature-point cloud,
  // downsampled to at most 400 points; null when empty or on error.
  Future<List<double>?> acquireCloudPoints() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getCloudPoints');
      if (raw == null || raw.isEmpty) return null;
      return raw.map((e) => (e as num).toDouble()).toList();
    } catch (e) {
      if (debug) print('getCloudPoints error: $e');
      return null;
    }
  }

  // Same shape as acquireCloudPoints, but unprojected from the live depth
  // image: dense geometry that still returns points on white/textureless
  // walls where the feature-point cloud sees nothing. Null when empty or on
  // error (devices without depth simply never produce points).
  Future<List<double>?> acquireDepthPoints() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getDepthPoints');
      if (raw == null || raw.isEmpty) return null;
      return raw.map((e) => (e as num).toDouble()).toList();
    } catch (e) {
      if (debug) print('getDepthPoints error: $e');
      return null;
    }
  }

  Future<List<ARHitTestResult>> hitTest(double xPx, double yPx) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('hitTest', {
        'x': xPx,
        'y': yPx,
      });
      if (raw == null) return const [];
      return raw
          .map((e) => ARHitTestResult.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      if (debug) print('hitTest error: $e');
      return const [];
    }
  }

  Future<void> _platformCallHandler(MethodCall call) {
    if (debug) {
      print('_platformCallHandler call ${call.method} ${call.arguments}');
    }
    try {
      switch (call.method) {
        case 'onError':
          if (onError != null) {
            onError!(call.arguments[0]);
            print(call.arguments);
          }
          else{
            ScaffoldMessenger.of(buildContext).showSnackBar(SnackBar(
                content: Text(call.arguments[0]),
                action: SnackBarAction(
                    label: 'HIDE',
                    onPressed:
                    ScaffoldMessenger.of(buildContext).hideCurrentSnackBar)));
          }
          break;
        case 'onPlaneOrPointTap':
          if (onPlaneOrPointTap != null) {
            final rawHitTestResults = call.arguments as List<dynamic>;
            final serializedHitTestResults = rawHitTestResults
                .map(
                    (hitTestResult) => Map<String, dynamic>.from(hitTestResult))
                .toList();
            final hitTestResults = serializedHitTestResults.map((e) {
              return ARHitTestResult.fromJson(e);
            }).toList();
            onPlaneOrPointTap(hitTestResults);
          }
          break;
        case 'onPlaneDetected':
          if (onPlaneDetected != null) {
            final planeCountResult = call.arguments as int;
            onPlaneDetected(planeCountResult);
          }
          break;
        case 'onPlanesUpdate':
          final handler = onPlanesUpdate;
          if (handler != null) {
            final args = call.arguments;
            List<dynamic> rawPlanes;
            Matrix4? vp;
            if (args is Map) {
              rawPlanes = (args['planes'] as List?) ?? const [];
              final proj = args['projection'] as List?;
              final view = args['view'] as List?;
              if (proj != null &&
                  view != null &&
                  proj.length == 16 &&
                  view.length == 16) {
                vp = Matrix4.fromList(
                        [for (final e in proj) (e as num).toDouble()]) *
                    Matrix4.fromList(
                        [for (final e in view) (e as num).toDouble()]);
              }
            } else {
              rawPlanes = (args as List?) ?? const [];
            }
            final planes = rawPlanes
                .map((p) => ARPlaneInfo.fromJson(Map<String, dynamic>.from(p)))
                .toList();
            handler(planes, vp);
          }
          break;
        case 'onTrackingFailure':
          onTrackingFailure?.call(call.arguments as String?);
          break;
        case 'dispose':
          _channel.invokeMethod<void>("dispose");
          break;
        default:
          if (debug) {
            print('Unimplemented method ${call.method} ');
          }
      }
    } catch (e) {
      print('Error caught: ' + e.toString());
    }
    return Future.value();
  }

  Future<void> onInitialize({
    bool showAnimatedGuide = true,
    bool showFeaturePoints = false,
    bool showPlanes = true,
    String? customPlaneTexturePath,
    bool showWorldOrigin = false,
    bool handleTaps = true,
    bool handlePans = false,
    bool handleRotation = false,
  }) {
    return _channel.invokeMethod<void>('init', {
      'showAnimatedGuide': showAnimatedGuide,
      'showFeaturePoints': showFeaturePoints,
      'planeDetectionConfig': planeDetectionConfig.index,
      'showPlanes': showPlanes,
      'customPlaneTexturePath': customPlaneTexturePath,
      'showWorldOrigin': showWorldOrigin,
      'handleTaps': handleTaps,
      'handlePans': handlePans,
      'handleRotation': handleRotation,
    });
  }

  dispose() async {
    try {
      await _channel.invokeMethod<void>("dispose");
    } catch (e) {
      print(e);
    }
  }

  Future<ImageProvider> snapshot() async {
    final result = await _channel.invokeMethod<Uint8List>('snapshot');
    return MemoryImage(result!);
  }
}
