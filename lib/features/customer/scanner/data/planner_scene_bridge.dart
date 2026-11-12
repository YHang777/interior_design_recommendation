import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show Icons, Offset;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../../../../models/room_design.dart';
import '../../ar/data/catalog_model_resolver.dart';
import '../../ar/data/glb_bounds.dart';
import '../../ar/data/glb_generator.dart' show FloorFinish, WallFinish, generateRoomShellGlb;
import 'camera_rig.dart' show ScenePose;
import 'furniture_catalog.dart';
import 'room_fit.dart' show footprintH, footprintW;
import 'room_shell.dart' show ShellGeometry, cutawayMask, shellRing;
import 'scene3d_controller.dart';

// Keeps a Scene3D scene in lockstep with the planner state: one shell node
// (walls + finishes) and one node per placement. Every call is fire-and-
// forget — a missing or failing native view must never break the editor.
class PlannerSceneBridge {
  PlannerSceneBridge({
    Scene3DController? controller,
    CatalogModelResolver? catalogResolver,
    Future<Directory> Function()? cacheRootProvider,
  })  : controller = controller ?? Scene3DController(),
        _catalogResolver = catalogResolver ??
            CatalogModelResolver(cacheRootProvider: cacheRootProvider ?? _cacheRoot),
        _cacheRootProvider = cacheRootProvider ?? _cacheRoot {
    // Every (re)bind starts a fresh native scene, so drop the diff caches and
    // let the owner re-push its state — the caches must never block that.
    this.controller.onBind = (viewId) {
      forgetScene();
      onBound?.call(viewId);
    };
  }

  /// Owner hook fired after [forgetScene] on platform-view bind/rebind.
  void Function(int viewId)? onBound;

  final Scene3DController controller;
  final CatalogModelResolver _catalogResolver;
  final Future<Directory> Function() _cacheRootProvider;

  static const String shellId = 'room-shell';

  static Future<Directory> _cacheRoot() async {
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  final Map<String, SceneModel> _nodes = {};
  final Map<String, ({double w, double h, double d, double cx, double cy, double cz})>
      _naturalBounds = {};
  String? _shellKey;

  // ── camera ──

  Future<void> setCamera(ScenePose pose) async {
    try {
      await controller.setCamera(pose);
    } catch (_) {}
  }

  /// Forget what the scene is believed to contain (not the native scene
  /// itself) so the next syncs re-push everything.
  void forgetScene() {
    _nodes.clear();
    _shellKey = null;
  }

  // ── shell ──

  Future<void> syncShell({
    required List<Offset> wallsCm,
    required double roomWCm,
    required double roomHCm,
    required FloorFinish floor,
    required WallFinish wall,
    Offset? cutawayCameraCm,
  }) async {
    final ring = shellRing(wallsCm: wallsCm, roomWCm: roomWCm, roomHCm: roomHCm);
    final shell = ShellGeometry(ringCm: ring);
    // The cutaway mask is a discrete bitstring in the key: the camera may move
    // freely inside one mask without regenerating the shell.
    final mask = cutawayCameraCm == null ? null : cutawayMask(shell, cutawayCameraCm);
    final maskKey =
        mask == null ? '-' : mask.map((cut) => cut ? '1' : '0').join();
    final key = _fnv1a([
      for (final p in ring) '${p.dx},${p.dy}',
      floor.type.name,
      '${floor.colorArgb}',
      '${floor.sizeM}',
      wall.type.name,
      '${wall.colorArgb}',
      maskKey,
    ].join('|'));
    if (key == _shellKey && _nodes.containsKey(shellId)) return;
    try {
      final bytes = generateRoomShellGlb(
          shell: shell, floor: floor, wall: wall, cutMask: mask);
      final dir = await _cacheRootProvider();
      final file =
          File('${dir.path}${Platform.pathSeparator}planner_shell_$key.glb');
      await file.writeAsBytes(bytes, flush: true);
      final model = SceneModel(
        id: shellId,
        source: file.path,
        fromAsset: false,
      );
      if (_nodes.containsKey(shellId)) {
        await controller.removeModel(shellId);
      }
      final sent = controller.isBound;
      await controller.addModel(model);
      // Record only what reached the view — a dropped pre-bind push must stay
      // retryable or the re-push hits this cache and pushes nothing.
      if (sent) {
        _shellKey = key;
        _nodes[shellId] = model;
      }
    } catch (_) {}
  }

  // ── furniture ──

  Future<void> syncFurniture(List<FurniturePlacement> items) async {
    final seen = <String>{};
    for (final f in items) {
      seen.add(f.id);
      try {
        final model = await _modelFor(f);
        if (model == null) continue;
        final prev = _nodes[f.id];
        final sameSource = prev != null &&
            prev.source == model.source &&
            prev.fromAsset == model.fromAsset;
        if (prev == null || !sameSource) {
          // A changed source is a new mesh (the generated GLB is re-authored at
          // the new size and its unit-scale transform can be identical) — only
          // a full addModel can swap geometry, updateModel carries no source.
          final sent = controller.isBound;
          await controller.addModel(model);
          if (sent) _nodes[f.id] = model;
        } else if (!_sameTransform(prev, model)) {
          final sent = controller.isBound;
          try {
            await controller.updateModel(model);
            if (sent) _nodes[f.id] = model;
          } catch (_) {
            _nodes.remove(f.id); // retry as a fresh add next sync
          }
        }
      } catch (_) {}
    }
    for (final id in _nodes.keys.toList()) {
      if (id == shellId || seen.contains(id)) continue;
      _nodes.remove(id);
      try {
        await controller.removeModel(id);
      } catch (_) {}
    }
  }

  Future<void> clearAll() async {
    _nodes.clear();
    _shellKey = null;
    try {
      await controller.clearModels();
    } catch (_) {}
  }

  // Placement → scene node: model origin lands so the scaled bounds center
  // sits over the placement's plan center (native places the model-space
  // origin at x/z and grounds min-Y at y).
  Future<SceneModel?> _modelFor(FurniturePlacement f) async {
    if (f.width <= 0 || f.height <= 0) return null;
    final src = await _catalogResolver.resolve(catalogItemFor(f));
    final nat = await _naturalOf(src);
    if (nat == null) return null;
    final targetW = f.width / 100;
    final targetH = plannerHeightMOf(f);
    final targetD = f.height / 100;
    final sx = nat.w > 1e-6 ? targetW / nat.w : 1.0;
    final sy = nat.h > 1e-6 ? targetH / nat.h : 1.0;
    final sz = nat.d > 1e-6 ? targetD / nat.d : 1.0;
    final cxM = (f.x + footprintW(f) / 2) / 100;
    final czM = (f.y + footprintH(f) / 2) / 100;
    return SceneModel(
      id: f.id,
      source: src.source,
      fromAsset: src.sourceType == 'asset',
      xM: cxM - nat.cx * sx,
      yM: 0,
      zM: czM - nat.cz * sz,
      yawDeg: -f.rotation,
      scaleX: sx,
      scaleY: sy,
      scaleZ: sz,
    );
  }

  Future<
      ({double w, double h, double d, double cx, double cy, double cz})?> _naturalOf(
      CatalogModelSource src) async {
    final key = src.source;
    final cached = _naturalBounds[key];
    if (cached != null) return cached;
    try {
      final Uint8List bytes;
      if (src.sourceType == 'asset') {
        final data = await rootBundle.load(src.source);
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } else {
        bytes = await src.file!.readAsBytes();
      }
      final b = GlbBounds.fromGlbBytes(bytes);
      final nat = (
        w: b.widthM,
        h: b.heightM,
        d: b.depthM,
        cx: b.centerX,
        cy: b.centerY,
        cz: b.centerZ,
      );
      _naturalBounds[key] = nat;
      return nat;
    } catch (_) {
      return null;
    }
  }

  static bool _sameTransform(SceneModel a, SceneModel b) =>
      a.xM == b.xM &&
      a.yM == b.yM &&
      a.zM == b.zM &&
      a.yawDeg == b.yawDeg &&
      a.scaleX == b.scaleX &&
      a.scaleY == b.scaleY &&
      a.scaleZ == b.scaleZ;

  static String _fnv1a(String text) {
    var h = 0x811C9DC5;
    for (final c in text.toLowerCase().codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }
}

@visibleForTesting
RoomCatalogItem catalogItemFor(FurniturePlacement f) {
  for (final c in roomCatalog) {
    if (c.iconName == f.iconName) return c;
  }
  return RoomCatalogItem(f.name, f.iconName, Icons.folder, 'misc', f.width,
      f.height, f.imageAsset, math.max(30.0, math.min(220.0, f.height)));
}

double plannerHeightMOf(FurniturePlacement f) =>
    catalogItemFor(f).heightCm / 100;
