import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../models/room_design.dart';
import '../../ar/data/glb_generator.dart' show FloorFinish, WallFinish;
import '../../ar/data/room_finishes.dart';
import '../../scanner/data/camera_rig.dart';
import '../../scanner/data/plan_scene_math.dart';
import '../../scanner/data/planner_scene_bridge.dart';
import '../../scanner/data/room_fit.dart';
import '../../scanner/presentation/scene3d_view.dart';
import 'walkthrough_controller.dart';

// First-person 3D stage for the walkthrough: the native scene shows the room
// shell and real GLB furniture, the camera rides the walker (position from the
// controller, pitch/zoom from the rig), and a pending piece previews as a
// translucent projected box. Where 3D is unsupported the painter fallback
// renders instead — same controller, same flows.
class WalkthroughScene extends StatefulWidget {
  const WalkthroughScene({
    super.key,
    required this.controller,
    required this.rig,
    required this.design,
    this.ghost,
    required this.fallback,
  });

  final WalkthroughController controller;
  final FirstPersonRig rig;

  /// Finish fields for the room shell; live geometry comes from [controller].
  final RoomDesign design;

  /// Unresolved placement template — the overlay resolves it per camera move
  /// so the preview tracks the walker.
  final FurniturePlacement? ghost;

  final Widget fallback;

  @override
  State<WalkthroughScene> createState() => _WalkthroughSceneState();
}

class _WalkthroughSceneState extends State<WalkthroughScene> {
  final PlannerSceneBridge _bridge = PlannerSceneBridge();
  String _sig = '';
  ScenePose _pose = const ScenePose(
      eyeX: 0,
      eyeY: 1.5,
      eyeZ: 0,
      targetX: 0,
      targetY: 1.5,
      targetZ: 1,
      fovDeg: 70);
  FurniturePlacement? _resolvedGhost;
  double _pinchZoom = 1;
  double? _aspect;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onModel);
    _bridge.onBound = (_) => _pushAll();
  }

  @override
  void didUpdateWidget(WalkthroughScene old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onModel);
      widget.controller.addListener(_onModel);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onModel);
    super.dispose();
  }

  void _onModel() {
    if (mounted) setState(() {});
  }

  // ── scene sync ──

  void _pushAll() {
    _pushCamera();
    _syncModels(force: true);
  }

  void _pushCamera() {
    final c = widget.controller;
    widget.rig.setZoom(c.zoom, aspect: _aspect);
    _pose = widget.rig.pose(
      walkerXCm: c.walker.dx,
      walkerYCm: c.walker.dy,
      headingRad: c.heading,
    );
    _bridge.setCamera(_pose);
  }

  void _syncModels({bool force = false}) {
    final c = widget.controller;
    final sel = finishSelectionFrom(widget.design);
    final floor = FloorFinish(
      type: sel.floorType,
      colorArgb: sel.floorColorArgb,
      sizeM: sel.floorSizeM,
    );
    final wall = WallFinish(type: sel.wallType, colorArgb: sel.wallColorArgb);
    final sig = '${c.roomW}x${c.roomH}#'
        '${c.walls.map((p) => '${p.dx},${p.dy}').join('|')}#'
        '${c.interiorWalls.map((ch) => ch.map((p) => '${p.dx},${p.dy}').join(';')).join('|')}#'
        '${sel.floorType},${sel.floorColorArgb},${sel.floorSizeM}#'
        '${sel.wallType},${sel.wallColorArgb}#'
        '${c.furniture.map((f) => '${f.id}:${f.x},${f.y},${f.rotation},${f.width},${f.height},${f.elevationCm},${f.heightCm},${f.modelUrl}').join('|')}';
    if (!force && sig == _sig) return;
    _sig = sig;
    _bridge.syncShell(
        wallsCm: c.walls,
        roomWCm: c.roomW,
        roomHCm: c.roomH,
        floor: floor,
        wall: wall,
        ceiling: true,
        interiorWallsCm: c.interiorWalls);
    _bridge.syncFurniture(c.furniture);
  }

  // ── look + zoom gestures ──

  void _onScaleStart(ScaleStartDetails d) {
    if (d.pointerCount >= 2) _pinchZoom = widget.controller.zoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2) {
      widget.controller.setZoom(_pinchZoom * d.scale);
    } else {
      // Grab-the-world: dragging right looks left, dragging down looks up.
      widget.controller.turn(-d.focalPointDelta.dx * 0.005);
      widget.rig.look(d.focalPointDelta.dy * 0.004);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!Scene3DView.supported) return widget.fallback;
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      if (size.width > 0 && size.height > 0 && size.isFinite) {
        _aspect = size.width / size.height;
      }
      return _stage();
    });
  }

  Widget _stage() {
    _pushCamera();
    _syncModels();
    _resolvedGhost = widget.ghost == null
        ? null
        : widget.controller.resolveGhost(widget.ghost!);
    return Stack(
      fit: StackFit.expand,
      children: [
        Scene3DView(
          controller: _bridge.controller,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
        ),
        if (_resolvedGhost != null)
          IgnorePointer(
            child: CustomPaint(
              painter: _GhostBoxPainter(
                pose: _pose,
                ghost: _resolvedGhost!,
                heightM: plannerHeightMOf(_resolvedGhost!),
              ),
            ),
          ),
      ],
    );
  }

  @visibleForTesting
  ScenePose get debugLastCamera => _pose;

  @visibleForTesting
  FurniturePlacement? get debugLastGhost => _resolvedGhost;
}

// Translucent placement preview: the piece's true box, projected through the
// same camera math as the rendered scene and clipped at the near plane so it
// still shows while standing at (or inside) its footprint.
class _GhostBoxPainter extends CustomPainter {
  _GhostBoxPainter(
      {required this.pose, required this.ghost, required this.heightM});

  final ScenePose pose;
  final FurniturePlacement ghost;
  final double heightM;

  @override
  void paint(Canvas canvas, Size size) {
    final x0 = ghost.x / 100;
    final x1 = (ghost.x + footprintW(ghost)) / 100;
    final z0 = ghost.y / 100;
    final z1 = (ghost.y + footprintH(ghost)) / 100;

    void fill(List<({double x, double y, double z})> poly, Color color) {
      final pts = projectWorldPolyNear(pose, size, poly);
      if (pts.length < 3) return;
      canvas.drawPath(Path()..addPolygon(pts, true), Paint()..color = color);
    }

    void stroke(List<({double x, double y, double z})> poly, Color color) {
      final pts = projectWorldPolyNear(pose, size, poly);
      if (pts.length < 3) return;
      canvas.drawPath(
        Path()..addPolygon(pts, true),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = color,
      );
    }

    final accent = AppColors.accent;
    for (var i = 0; i < 4; i++) {
      final ax = i == 0 || i == 3 ? x0 : x1;
      final bx = i == 0 || i == 1 ? x1 : x0;
      final az = i <= 1 ? z0 : z1;
      final bz = i == 1 || i == 2 ? z1 : z0;
      fill(
        [
          (x: ax, y: 0, z: az),
          (x: bx, y: 0, z: bz),
          (x: bx, y: heightM, z: bz),
          (x: ax, y: heightM, z: az),
        ],
        accent.withValues(alpha: 0.10),
      );
    }
    fill(
      [
        (x: x0, y: 0, z: z0),
        (x: x1, y: 0, z: z0),
        (x: x1, y: 0, z: z1),
        (x: x0, y: 0, z: z1),
      ],
      accent.withValues(alpha: 0.30),
    );
    fill(
      [
        (x: x0, y: heightM, z: z0),
        (x: x1, y: heightM, z: z0),
        (x: x1, y: heightM, z: z1),
        (x: x0, y: heightM, z: z1),
      ],
      accent.withValues(alpha: 0.14),
    );
    stroke(
      [
        (x: x0, y: 0, z: z0),
        (x: x1, y: 0, z: z0),
        (x: x1, y: 0, z: z1),
        (x: x0, y: 0, z: z1),
      ],
      accent.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_GhostBoxPainter old) =>
      old.pose != pose || old.ghost != ghost || old.heightM != heightM;
}
