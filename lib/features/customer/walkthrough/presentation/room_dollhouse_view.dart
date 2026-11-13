import 'package:flutter/material.dart';

import '../../../../models/room_design.dart';
import '../../ar/data/glb_generator.dart' show FloorFinish, WallFinish;
import '../../ar/data/room_finishes.dart';
import '../../scanner/data/camera_rig.dart';
import '../../scanner/data/planner_scene_bridge.dart';
import '../../scanner/data/room_shell.dart';
import '../../scanner/presentation/scene3d_view.dart';

// Read-only 3D dollhouse of a design — real GLB furniture in the cutaway
// room shell, seen from the planner's elevated 3/4 orbit. It NEVER
// auto-rotates; [interactive] adds drag-to-orbit (off in the gallery, where
// swipes page and taps walk). [fallback] shows where native 3D is
// unavailable.
class RoomDollhouseView extends StatefulWidget {
  const RoomDollhouseView({
    super.key,
    required this.design,
    required this.fallback,
    this.interactive = false,
  });

  final RoomDesign design;
  final Widget fallback;
  final bool interactive;

  @override
  State<RoomDollhouseView> createState() => _RoomDollhouseViewState();
}

class _RoomDollhouseViewState extends State<RoomDollhouseView> {
  final PlannerSceneBridge _bridge = PlannerSceneBridge();
  late OrbitRig _rig;
  Size _viewport = Size.zero;
  String? _cutSig;

  @override
  void initState() {
    super.initState();
    _rig = OrbitRig.frameRoom(
        roomWCm: widget.design.widthCm, roomHCm: widget.design.heightCm);
    _bridge.onBound = (_) {
      _cutSig = null;
      _push();
    };
  }

  @override
  void didUpdateWidget(RoomDollhouseView old) {
    super.didUpdateWidget(old);
    if (old.design != widget.design) {
      _frame();
      _push();
    }
  }

  void _frame() {
    final d = widget.design;
    _rig = OrbitRig.frameRoom(roomWCm: d.widthCm, roomHCm: d.heightCm);
    if (_viewport.width > 0 && _viewport.height > 0) {
      _rig.distanceM = fitRoomDistanceM(
          roomWCm: d.widthCm,
          roomHCm: d.heightCm,
          fovDeg: _rig.fovDeg,
          aspect: _viewport.width / _viewport.height);
      _rig.maxDistanceM = _rig.distanceM * 1.8;
    }
  }

  Offset get _cameraCm => Offset(_rig.pose.eyeX * 100, _rig.pose.eyeZ * 100);

  void _push() {
    _bridge.setCamera(_rig.pose);
    _syncShell();
    _bridge.syncFurniture(widget.design.furniture);
  }

  void _syncShell() {
    final d = widget.design;
    final sel = finishSelectionFrom(d);
    final shell = ShellGeometry(
        ringCm: shellRing(
            wallsCm: d.walls, roomWCm: d.widthCm, roomHCm: d.heightCm));
    _cutSig = cutawaySignature(shell, _cameraCm);
    _bridge.syncShell(
      wallsCm: d.walls,
      roomWCm: d.widthCm,
      roomHCm: d.heightCm,
      floor: FloorFinish(
          type: sel.floorType,
          colorArgb: sel.floorColorArgb,
          sizeM: sel.floorSizeM),
      wall: WallFinish(type: sel.wallType, colorArgb: sel.wallColorArgb),
      cutawayCameraCm: _cameraCm,
      interiorWallsCm: d.interiorWalls,
    );
  }

  void _orbit(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2) {
      if (d.scale > 0) _rig.dolly(1 / d.scale.clamp(0.9, 1.1));
    } else {
      _rig.orbit(-d.focalPointDelta.dx * 0.008, d.focalPointDelta.dy * 0.006);
    }
    _bridge.setCamera(_rig.pose);
    // Re-cut only when the camera crosses to another wall's outer side.
    final d0 = widget.design;
    final shell = ShellGeometry(
        ringCm: shellRing(
            wallsCm: d0.walls, roomWCm: d0.widthCm, roomHCm: d0.heightCm));
    if (cutawaySignature(shell, _cameraCm) != _cutSig) _syncShell();
  }

  @override
  Widget build(BuildContext context) {
    if (!Scene3DView.supported) return widget.fallback;
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      if (size != _viewport && size.width > 0 && size.height > 0) {
        final first = _viewport.isEmpty;
        _viewport = size;
        if (first) {
          _frame();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _push();
          });
        }
      }
      final view = Scene3DView(
        controller: _bridge.controller,
        onScaleUpdate: widget.interactive ? _orbit : null,
        fallback: widget.fallback,
      );
      return widget.interactive ? view : IgnorePointer(child: view);
    });
  }
}
