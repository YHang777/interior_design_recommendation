import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../models/room_design.dart';
import '../../ar/data/room_finishes.dart' show FinishSelection;
import '../../scanner/data/furniture_catalog.dart';
import 'walkthrough_controller.dart';
import 'walkthrough_painter.dart';

// Live 3D mirror of the plan for the planner's preview pane: the walkthrough
// renderer on a private controller that slowly orbits, so the preview is
// always moving without stealing the walk controls.
class PlanPreview3D extends StatefulWidget {
  const PlanPreview3D({super.key, required this.design, this.finishes, this.spin = true});

  final RoomDesign design;
  final FinishSelection? finishes;

  // Off for the planner's static fallback — the room must never auto-rotate.
  final bool spin;

  @override
  State<PlanPreview3D> createState() => _PlanPreview3DState();
}

class _PlanPreview3DState extends State<PlanPreview3D> {
  WalkthroughController? _controller;
  Timer? _orbit;
  final Map<String, ui.Image> _sprites = {};
  String _builtSig = '';

  @override
  void initState() {
    super.initState();
    if (widget.spin) {
      _orbit = Timer.periodic(const Duration(milliseconds: 120), (_) {
        _controller?.turn(0.02);
      });
    }
  }

  @override
  void dispose() {
    _orbit?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  // The planner rebuilds a fresh RoomDesign per edit; only geometry changes
  // reset the preview pose.
  String _signature(RoomDesign d) {
    final items = d.furniture
        .map((f) => '${f.id}:${f.x.toInt()},${f.y.toInt()},${f.rotation},'
            '${f.width.toInt()},${f.height.toInt()}')
        .join('|');
    final walls =
        d.walls.map((p) => '${p.dx.toInt()},${p.dy.toInt()}').join('|');
    return '${d.widthCm.toInt()}x${d.heightCm.toInt()}#$walls#$items';
  }

  WalkthroughController _syncController() {
    final sig = _signature(widget.design);
    final existing = _controller;
    if (existing != null && sig == _builtSig) return existing;
    _builtSig = sig;
    final next = WalkthroughController(design: widget.design);
    // Safe while a ListenableBuilder still listens: removeListener is
    // allowed on a disposed ChangeNotifier.
    existing?.dispose();
    _controller = next;
    _loadSprites(next);
    return next;
  }

  void _loadSprites(WalkthroughController controller) {
    final paths = <String>{
      for (final c in roomCatalog)
        if (c.imageAsset != null) c.imageAsset!,
      for (final f in controller.furniture)
        if (f.imageAsset != null && f.imageAsset!.isNotEmpty) f.imageAsset!,
    };
    for (final path in paths) {
      if (_sprites.containsKey(path)) continue;
      _loadSprite(path);
    }
  }

  Future<void> _loadSprite(String path) async {
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _sprites[path] = frame.image);
    } catch (_) {
      // Missing/broken asset — the painter falls back to icon card or box.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _syncController();
    return ListenableBuilder(
      listenable: controller,
      builder: (_, _) => CustomPaint(
        size: Size.infinite,
        painter: WalkthroughPainter(
          controller: controller,
          sprites: _sprites,
          finishes: widget.finishes,
        ),
      ),
    );
  }
}
