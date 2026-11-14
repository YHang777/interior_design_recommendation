import 'dart:convert';
import 'dart:io';

import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_math/vector_math_64.dart';

import 'plane_overlay_math.dart';

class ArSessionRecorder {
  ArSessionRecorder._(this._sink, this._t0);

  final IOSink _sink;
  final DateTime _t0;
  DateTime? _lastPlanesAt;
  DateTime? _lastPaintAt;
  bool _closed = false;

  static const _planesEvery = Duration(milliseconds: 500);
  static const _paintEvery = Duration(milliseconds: 500);
  static const _keepFiles = 10;

  static Future<ArSessionRecorder?> start() async {
    if (!kDebugMode) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final recDir = Directory('${dir.path}/ar_rec');
      await recDir.create(recursive: true);
      final old = recDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jsonl'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in old.take(
          old.length >= _keepFiles ? old.length - _keepFiles + 1 : 0)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
      final now = DateTime.now();
      final stamp = now
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('-', '')
          .split('.')
          .first;
      final file = File('${recDir.path}/ar_$stamp.jsonl');
      final rec = ArSessionRecorder._(file.openWrite(), now);
      rec._write({'k': 'start', 'wall': now.toIso8601String()});
      return rec;
    } catch (_) {
      return null;
    }
  }

  int get _ms => DateTime.now().difference(_t0).inMilliseconds;

  void _write(Map<String, Object?> m) {
    if (_closed) return;
    try {
      _sink.writeln(jsonEncode({'t': _ms, ...m}));
    } catch (_) {}
  }

  static double _r(double v, [int dp = 3]) =>
      v.isFinite ? double.parse(v.toStringAsFixed(dp)) : 0;

  static List<double> _flatDecimated(List<double> flat, int maxVerts) {
    final n = flat.length ~/ 3;
    if (n == 0) return const [];
    final stride = n <= maxVerts ? 1 : (n / maxVerts).ceil();
    return [
      for (var i = 0; i < n; i += stride) ...[
        _r(flat[i * 3], 2),
        _r(flat[i * 3 + 1], 2),
        _r(flat[i * 3 + 2], 2),
      ]
    ];
  }

  void planes(List<ARPlaneInfo> planes, Matrix4? vp) {
    final now = DateTime.now();
    if (_lastPlanesAt != null && now.difference(_lastPlanesAt!) < _planesEvery) {
      return;
    }
    _lastPlanesAt = now;
    _write({
      'k': 'planes',
      if (vp != null) 'vp': [for (final v in vp.storage) _r(v, 5)],
      'p': [
        for (final p in planes)
          {
            'id': p.id,
            'ty': p.planeType,
            'c': [_r(p.centerX), _r(p.centerY), _r(p.centerZ)],
            'e': [_r(p.extentX), _r(p.extentZ)],
            'yaw': _r(p.yaw),
            if (p.subsumed) 'sub': 1,
            'poly': _flatDecimated(p.polygon, 24),
          }
      ],
    });
  }

  void paint({
    required List<PlaneQuad> quads,
    required List<PlaneQuad> masks,
    required PlaneQuad? synthetic,
    required double? floorY,
    required double? refY,
    required double? cameraY,
    required bool trusted,
    required List<ARPlaneInfo> syntheticWalls,
  }) {
    final now = DateTime.now();
    if (_lastPaintAt != null && now.difference(_lastPaintAt!) < _paintEvery) {
      return;
    }
    _lastPaintAt = now;
    List<double> corners(PlaneQuad q) {
      final cs = planeQuadCorners(q);
      final stride = cs.length <= 24 ? 1 : (cs.length / 24).ceil();
      return [
        for (var i = 0; i < cs.length; i += stride) ...[
          _r(cs[i].x, 2),
          _r(cs[i].y, 2),
          _r(cs[i].z, 2),
        ]
      ];
    }

    _write({
      'k': 'paint',
      'floorY': floorY == null ? null : _r(floorY),
      'refY': refY == null ? null : _r(refY),
      'camY': cameraY == null ? null : _r(cameraY),
      'trusted': trusted,
      'q': [
        for (final q in quads)
          {'kind': q.kind == PlaneQuadKind.wall ? 'w' : 'f', 'v': corners(q)}
      ],
      'm': [for (final q in masks) corners(q)],
      if (synthetic != null) 'syn': corners(synthetic),
      'sw': [
        for (final p in syntheticWalls)
          {
            'c': [_r(p.centerX), _r(p.centerY), _r(p.centerZ)],
            'e': [_r(p.extentX), _r(p.extentZ)],
            'yaw': _r(p.yaw),
          }
      ],
    });
  }

  void camera(Matrix4 pose) {
    _write({
      'k': 'cam',
      'pose': [for (final v in pose.storage) _r(v, 4)],
    });
  }

  void cloud(List<double> flat, {double? probe, int? feature, int? depth}) {
    _write({
      'k': 'cloud',
      'n': flat.length ~/ 3,
      if (feature != null) 'nf': feature,
      if (depth != null) 'nd': depth,
      if (probe != null) 'probe': _r(probe),
      'pts': _flatDecimated(flat, 400),
    });
  }

  void note(String msg) => _write({'k': 'note', 'msg': msg});

  Future<void> close() async {
    if (_closed) return;
    _write({'k': 'end'});
    _closed = true;
    try {
      await _sink.flush();
      await _sink.close();
    } catch (_) {}
  }
}
