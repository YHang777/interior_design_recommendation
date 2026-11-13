import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/material.dart' show Icons, Offset;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../../../../models/room_design.dart';
import '../../ar/data/catalog_model_resolver.dart';
import '../../ar/data/glb_bounds.dart';
import '../../ar/data/glb_generator.dart'
    show
        DraftWall,
        FloorFinish,
        WallFinish,
        generateRoomCeilingGlb,
        generateRoomShellGlb;
import 'camera_rig.dart' show ScenePose;
import 'furniture_catalog.dart';
import 'room_fit.dart'
    show distToSegment, footprintH, footprintW, furnitureRect, interiorWallSegments;
import 'room_shell.dart'
    show ShellGeometry, cutawayMask, kShellCutawayHeightCm, shellRing;
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
  static const String ceilingId = 'room-ceiling';

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
    _ceilingKey = null;
  }

  // ── shell ──

  Future<void> syncShell({
    required List<Offset> wallsCm,
    required double roomWCm,
    required double roomHCm,
    required FloorFinish floor,
    required WallFinish wall,
    Offset? cutawayCameraCm,
    bool ceiling = false,
    List<List<Offset>> interiorWallsCm = const [],
  }) async {
    final ring = shellRing(wallsCm: wallsCm, roomWCm: roomWCm, roomHCm: roomHCm);
    final shell = ShellGeometry(ringCm: ring);
    final drafts = [
      ...draftWallsFor(
          wallsCm: wallsCm,
          roomWCm: roomWCm,
          roomHCm: roomHCm,
          cameraCm: cutawayCameraCm),
      ...interiorWallDrafts(
          chains: interiorWallsCm,
          roomWCm: roomWCm,
          roomHCm: roomHCm,
          cameraCm: cutawayCameraCm),
    ];
    // The cutaway mask is a discrete bitstring in the key: the camera may move
    // freely inside one mask without regenerating the shell.
    final mask = cutawayCameraCm == null ? null : cutawayMask(shell, cutawayCameraCm);
    // Wall-hung pieces follow their wall: a newly cut wall hides its art.
    final cutChanged = !listEquals(mask, _cutMask);
    _cutShell = shell;
    _cutMask = mask;
    if (cutChanged && _lastItems.isNotEmpty) syncFurniture(_lastItems);
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
      for (final d in drafts)
        'd${d.aCm.dx},${d.aCm.dy},${d.bCm.dx},${d.bCm.dy},${d.cut}',
    ].join('|'));
    await _syncCeiling(ceiling ? shell : null, wall);
    if (key == _shellKey && _nodes.containsKey(shellId)) return;
    try {
      final bytes = generateRoomShellGlb(
          shell: shell,
          floor: floor,
          wall: wall,
          cutMask: mask,
          draftWalls: drafts);
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

  String? _ceilingKey;

  Future<void> _syncCeiling(ShellGeometry? shell, WallFinish wall) async {
    if (shell == null) {
      if (_nodes.remove(ceilingId) != null) {
        _ceilingKey = null;
        try {
          await controller.removeModel(ceilingId);
        } catch (_) {}
      }
      return;
    }
    final key = _fnv1a(
        [for (final p in shell.ringCm) '${p.dx},${p.dy}'].join('|'));
    if (key == _ceilingKey && _nodes.containsKey(ceilingId)) return;
    try {
      final bytes = generateRoomCeilingGlb(shell: shell, wall: wall);
      final dir = await _cacheRootProvider();
      final file =
          File('${dir.path}${Platform.pathSeparator}planner_ceiling_$key.glb');
      await file.writeAsBytes(bytes, flush: true);
      // Native grounds the model's lowest point at yM — lift it back to the
      // wall tops.
      final model = SceneModel(
        id: ceilingId,
        source: file.path,
        fromAsset: false,
        yM: shell.wallHeightCm / 100,
        castShadows: false,
      );
      if (_nodes.containsKey(ceilingId)) {
        await controller.removeModel(ceilingId);
      }
      final sent = controller.isBound;
      await controller.addModel(model);
      if (sent) {
        _ceilingKey = key;
        _nodes[ceilingId] = model;
      }
    } catch (_) {}
  }

  // ── furniture ──

  List<FurniturePlacement> _lastItems = const [];
  ShellGeometry? _cutShell;
  List<bool>? _cutMask;
  final Set<String> _pendingRefs = {};

  Future<void> _syncChain = Future<void>.value();

  // Syncs run strictly one after another: a stand-in add still in flight
  // must never land after (and over) the real model that replaced it.
  Future<void> syncFurniture(List<FurniturePlacement> items) {
    _lastItems = List.of(items);
    final snapshot = _lastItems;
    final next = _syncChain.then((_) => _syncFurnitureNow(
        piecesVisibleWithCutaway(snapshot, shell: _cutShell, mask: _cutMask)));
    _syncChain = next.catchError((_) {});
    return next;
  }

  Future<void> _syncFurnitureNow(List<FurniturePlacement> items) async {
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
      if (id == shellId || id == ceilingId || seen.contains(id)) continue;
      _nodes.remove(id);
      try {
        await controller.removeModel(id);
      } catch (_) {}
    }
  }

  Future<void> clearAll() async {
    _nodes.clear();
    _shellKey = null;
    _ceilingKey = null;
    try {
      await controller.clearModels();
    } catch (_) {}
  }

  // Placement → scene node: model origin lands so the scaled bounds center
  // sits over the placement's plan center (native places the model-space
  // origin at x/z and grounds min-Y at y).
  Future<SceneModel?> _modelFor(FurniturePlacement f) async {
    if (f.width <= 0 || f.height <= 0) return null;
    final item = catalogItemFor(f);
    // The piece's own GLB (marketplace / bundled variant) wins; the catalog
    // model for its type is the fallback.
    final ref = f.modelUrl;
    CatalogModelSource? own;
    if (ref != null && ref.isNotEmpty) {
      if (ref.startsWith('http') && !_catalogResolver.isModelRefSettled(ref)) {
        // Network GLB still downloading: show the catalog stand-in now and
        // re-sync when it lands, so the piece is never blank for seconds.
        if (_pendingRefs.add(ref)) {
          _catalogResolver.resolveModelRef(ref).whenComplete(() {
            _pendingRefs.remove(ref);
            syncFurniture(_lastItems);
          });
        }
      } else {
        own = await _catalogResolver.resolveModelRef(ref);
      }
    }
    final src = own ?? await _catalogResolver.resolve(item);
    // An unmeasurable model still places at the catalog box — a piece the
    // plan shows must never vanish from the 3D scene without a trace.
    final nat = await _naturalOf(src) ??
        (
          w: item.defaultWidth / 100,
          h: item.heightCm / 100,
          d: item.defaultHeight / 100,
          cx: 0.0,
          cy: 0.0,
          cz: 0.0,
        );
    final targetW = f.width / 100;
    final targetH = plannerHeightMOf(f);
    final targetD = f.height / 100;
    // A model authored with its long side on Z (sofa facing +X) would be
    // squashed into the seller box; turn it a quarter instead so the long
    // sides line up and the per-axis stretch stays near uniform.
    final turn = src.isBundled &&
        longAxisDisagrees(nat.w, nat.d, targetW, targetD);
    final sx = turn
        ? (nat.w > 1e-6 ? targetD / nat.w : 1.0)
        : (nat.w > 1e-6 ? targetW / nat.w : 1.0);
    final sy = nat.h > 1e-6 ? targetH / nat.h : 1.0;
    final sz = turn
        ? (nat.d > 1e-6 ? targetW / nat.d : 1.0)
        : (nat.d > 1e-6 ? targetD / nat.d : 1.0);
    final yawDeg = -f.rotation + (turn ? 90.0 : 0.0);
    // Native places the model-space origin at x/z, then scales and yaws
    // about it — so the scaled bounds center must be rotated by the same
    // yaw before it is subtracted, or off-center models drift when turned.
    final a = yawDeg * math.pi / 180;
    final ox = nat.cx * sx;
    final oz = nat.cz * sz;
    final rx = ox * math.cos(a) + oz * math.sin(a);
    final rz = -ox * math.sin(a) + oz * math.cos(a);
    final cxM = (f.x + footprintW(f) / 2) / 100;
    final czM = (f.y + footprintH(f) / 2) / 100;
    return SceneModel(
      id: f.id,
      source: src.source,
      fromAsset: src.sourceType == 'asset',
      xM: cxM - rx,
      yM: (f.elevationCm ?? 0) / 100,
      zM: czM - rz,
      yawDeg: yawDeg,
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
      final b = GlbBounds.sceneFromGlbBytes(bytes);
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
    (f.heightCm != null && f.heightCm! > 0 ? f.heightCm! : catalogItemFor(f).heightCm) /
    100;

// True when the model's long footprint side runs across the seller box's
// long side and both are clearly elongated (ratio > 1.2) — square-ish
// pieces never get turned.
bool longAxisDisagrees(double natW, double natD, double tgtW, double tgtD) {
  if (natW <= 1e-6 || natD <= 1e-6 || tgtW <= 1e-6 || tgtD <= 1e-6) {
    return false;
  }
  final natRatio = math.max(natW, natD) / math.min(natW, natD);
  final tgtRatio = math.max(tgtW, tgtD) / math.min(tgtW, tgtD);
  if (natRatio < 1.2 || tgtRatio < 1.2) return false;
  return (natW >= natD) != (tgtW >= tgtD);
}

// Corners placed so far but not yet a closed outline (< 3) still render as
// real walls: two corners make one run, a lone corner a post. A run between
// the planner camera and the room center is cut to dollhouse height.
List<DraftWall> draftWallsFor({
  required List<Offset> wallsCm,
  required double roomWCm,
  required double roomHCm,
  Offset? cameraCm,
}) {
  if (wallsCm.isEmpty || wallsCm.length >= 3) return const [];
  if (wallsCm.length == 1) return [DraftWall(wallsCm[0], wallsCm[0])];
  final a = wallsCm[0];
  final b = wallsCm[1];
  var cut = false;
  if (cameraCm != null) {
    final centre = Offset(roomWCm / 2, roomHCm / 2);
    double side(Offset p) =>
        (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
    cut = side(cameraCm) * side(centre) < 0;
  }
  return [DraftWall(a, b, cut: cut)];
}

// Interior walls: every segment of every chain is a real slab inside the
// room (a lone corner a post). Same dollhouse cut as the room walls: a run
// standing between the planner camera and the room center drops low.
List<DraftWall> interiorWallDrafts({
  required List<List<Offset>> chains,
  required double roomWCm,
  required double roomHCm,
  Offset? cameraCm,
}) {
  final out = <DraftWall>[];
  final centre = Offset(roomWCm / 2, roomHCm / 2);
  for (final (a, b) in interiorWallSegments(chains)) {
    var cut = false;
    if (cameraCm != null && a != b) {
      double side(Offset p) =>
          (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
      cut = side(cameraCm) * side(centre) < 0;
    }
    out.add(DraftWall(a, b, cut: cut));
  }
  return out;
}

// Dollhouse cutaway: a wall between the camera and the room is cut to
// kShellCutawayHeightCm, so art hung on it above that height would float in
// mid-air. Such pieces are left out until the camera moves round and the wall
// stands full height again. Without a mask (first-person walk) nothing is cut.
List<FurniturePlacement> piecesVisibleWithCutaway(
  List<FurniturePlacement> items, {
  ShellGeometry? shell,
  List<bool>? mask,
  double cutHeightCm = kShellCutawayHeightCm,
}) {
  if (shell == null || mask == null || !mask.contains(true)) return items;
  final segs = shell.wallSegments;
  bool hidden(FurniturePlacement f) {
    if (!f.isRaised) return false;
    final top = (f.elevationCm ?? 0) + (f.heightCm ?? 0);
    if (top <= cutHeightCm) return false;
    final c = furnitureRect(f).center;
    for (var i = 0; i < segs.length && i < mask.length; i++) {
      if (!mask[i]) continue;
      if (distToSegment(c, segs[i].a, segs[i].b) < 8) return true;
    }
    return false;
  }

  return [
    for (final f in items)
      if (!hidden(f)) f,
  ];
}
