import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/user_errors.dart';
import '../../../../models/room_design.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/catalog_picker_sheet.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../homeowner/presentation/providers/design_providers.dart';
import '../../scanner/data/furniture_catalog.dart';
import 'walkthrough_controller.dart';
import 'walkthrough_painter.dart';

// Street View style walkthrough of a saved plan: you stand in the room in
// first person — ↑↓ walk forward/back along the heading, ←→ turn in place,
// drag the view to look around — and furniture can be placed at your spot.
// Pose stays 2D (position + heading); VR swaps the painter, not the model.
class WalkthroughScreen extends ConsumerStatefulWidget {
  const WalkthroughScreen({super.key, this.design});

  final RoomDesign? design;

  @override
  ConsumerState<WalkthroughScreen> createState() => _WalkthroughScreenState();
}

class _WalkthroughScreenState extends ConsumerState<WalkthroughScreen> {
  late final WalkthroughController _ctl;
  final FocusNode _focus = FocusNode();
  RoomCatalogItem? _placing;
  int _placingRotation = 0;
  bool _showHint = true;
  Timer? _repeat;

  @override
  void initState() {
    super.initState();
    _ctl = WalkthroughController(design: widget.design ?? _emptyDesign());
  }

  @override
  void dispose() {
    _repeat?.cancel();
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  static RoomDesign _emptyDesign() => RoomDesign(
        id: '',
        name: 'Walkthrough',
        roomType: 'living_room',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        userId: '',
      );

  @visibleForTesting
  Offset get debugWalker => _ctl.walker;

  @visibleForTesting
  double get debugHeading => _ctl.heading;

  @visibleForTesting
  List<FurniturePlacement> get debugFurniture => List.of(_ctl.furniture);

  @visibleForTesting
  bool get debugPlacing => _placing != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text(
          'Walkthrough',
          style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add furniture',
            onPressed: _openFurniturePicker,
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: 'Save Design',
            onPressed: _saveDesign,
          ),
        ],
      ),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: GestureDetector(
                // Drag right → the world follows the finger, i.e. you look
                // left — the same grab-the-scene feel as Street View.
                onHorizontalDragUpdate: (d) {
                  final delta = d.primaryDelta;
                  if (delta != null) _act(() => _ctl.turn(-delta * 0.005));
                },
                child: ListenableBuilder(
                  listenable: _ctl,
                  builder: (_, _) => CustomPaint(
                    size: Size.infinite,
                    painter: WalkthroughPainter(
                      controller: _ctl,
                      ghost: _placing == null
                          ? null
                          : _ctl.resolveGhost(_pending()),
                    ),
                  ),
                ),
              ),
            ),
            if (_showHint && _placing == null)
              const Positioned(
                  top: 12, left: 0, right: 0, child: Center(child: _HintChip())),
            if (_placing != null)
              Positioned(
                  top: 12, left: 12, right: 12, child: _placementBar()),
            Positioned(
              left: 14,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _circleButton(
                    icon: Icons.add,
                    tooltip: 'Zoom in',
                    onTap: () => _ctl.setZoom(_ctl.zoom * 1.25),
                  ),
                  const SizedBox(height: 8),
                  _circleButton(
                    icon: Icons.remove,
                    tooltip: 'Zoom out',
                    onTap: () => _ctl.setZoom(_ctl.zoom / 1.25),
                  ),
                ],
              ),
            ),
            Positioned(right: 14, bottom: 24, child: _dPad()),
          ],
        ),
      ),
    );
  }

  // ─── Input ───

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _act(() => _ctl.walk(1));
      case LogicalKeyboardKey.arrowDown:
        _act(() => _ctl.walk(-1));
      case LogicalKeyboardKey.arrowLeft:
        _act(() => _ctl.turn(-WalkthroughController.turnStepRad));
      case LogicalKeyboardKey.arrowRight:
        _act(() => _ctl.turn(WalkthroughController.turnStepRad));
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _act(VoidCallback action) {
    action();
    if (_showHint && mounted) setState(() => _showHint = false);
  }

  void _startRepeat(VoidCallback action) {
    _act(action);
    _repeat?.cancel();
    _repeat = Timer.periodic(const Duration(milliseconds: 90),
        (_) => mounted ? _act(action) : _repeat?.cancel());
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  Widget _padButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback action,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => _act(action),
        onLongPressStart: (_) => _startRepeat(action),
        onLongPressEnd: (_) => _stopRepeat(),
        onLongPressCancel: _stopRepeat,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, size: 24, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _dPad() {
    const gap = SizedBox(height: 4);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _padButton(
          icon: Icons.keyboard_arrow_up,
          tooltip: 'Walk forward',
          action: () => _ctl.walk(1),
        ),
        gap,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _padButton(
              icon: Icons.keyboard_arrow_left,
              tooltip: 'Turn left',
              action: () => _ctl.turn(-WalkthroughController.turnStepRad),
            ),
            const SizedBox(width: 46, height: 46),
            _padButton(
              icon: Icons.keyboard_arrow_right,
              tooltip: 'Turn right',
              action: () => _ctl.turn(WalkthroughController.turnStepRad),
            ),
          ],
        ),
        gap,
        _padButton(
          icon: Icons.keyboard_arrow_down,
          tooltip: 'Walk back',
          action: () => _ctl.walk(-1),
        ),
      ],
    );
  }

  // ─── Placement ───

  // Catalog pick → drawable placement. A fresh id per call: the ghost never
  // commits, and each Place gets its own identity (same id source the
  // planner uses for catalog adds).
  FurniturePlacement _pending() {
    final cat = _placing!;
    return FurniturePlacement(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      name: cat.name,
      iconName: cat.iconName,
      x: 0,
      y: 0,
      width: cat.defaultWidth,
      height: cat.defaultHeight,
      rotation: _placingRotation.toDouble(),
      imageAsset: cat.imageAsset,
    );
  }

  Widget _placementBar() {
    final item = _placing!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(item.icon, size: 20, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${item.name} — walk to position',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
          ),
          IconButton(
            tooltip: 'Rotate',
            icon: const Icon(Icons.rotate_90_degrees_ccw, size: 18),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(
                () => _placingRotation = (_placingRotation + 90) % 360),
          ),
          const SizedBox(width: 4),
          ElevatedButton(
            onPressed: _place,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              textStyle:
                  GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            child: const Text('Place'),
          ),
          IconButton(
            tooltip: 'Cancel placement',
            icon: const Icon(Icons.close, size: 18),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() {
              _placing = null;
              _placingRotation = 0;
            }),
          ),
        ],
      ),
    );
  }

  Future<void> _openFurniturePicker() async {
    final picked = await showCatalogPickerSheet<RoomCatalogItem>(
      context: context,
      title: 'Add furniture',
      subtitle: 'Pick a piece, then walk to where it should sit',
      items: roomCatalog,
      labelOf: (c) => c.name,
      categoryOf: (c) => c.category,
      tileBuilder: (_, cat) => _CatalogThumb(cat: cat),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _placing = picked;
      _placingRotation = 0;
    });
  }

  void _place() {
    if (_placing == null) return;
    final placed = _ctl.place(_pending());
    showAppSnackbar(context, '${placed.name} placed');
  }

  // ─── Save ───

  Future<void> _saveDesign() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      showAppSnackbar(context, 'Please sign in to save designs',
          isError: true);
      return;
    }

    final existing = widget.design;
    final hasId = existing != null && existing.id.isNotEmpty;
    final nameCtrl = TextEditingController(
        text: existing != null && existing.name.isNotEmpty
            ? existing.name
            : 'Walkthrough Design');

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsAlignment: MainAxisAlignment.center,
        title: const Text('Save Design'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Design name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            style: ElevatedButton.styleFrom(minimumSize: Size.zero),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty || !mounted) return;

    final ds = ref.read(roomDesignDatasourceProvider);
    final now = DateTime.now();
    final designId =
        hasId ? existing.id : 'design-${now.millisecondsSinceEpoch}';

    final design = RoomDesign(
      id: designId,
      name: name,
      roomType: existing?.roomType ?? 'living_room',
      widthCm: _ctl.roomW,
      heightCm: _ctl.roomH,
      furniture: List.of(_ctl.furniture),
      walls: List.of(_ctl.walls),
      detectedItems: existing?.detectedItems ?? const [],
      userId: user.uid,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      if (hasId) {
        await ds.updateDesign(designId, design.toJson());
      } else {
        await ds.createDesign(designId: designId, data: design.toJson());
      }
      if (mounted) {
        showAppSnackbar(
          context,
          'Design "$name" saved!',
          duration: const Duration(seconds: 3),
        );
        Navigator.pop(context, design);
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(
          context,
          userMessage(e,
              fallback: 'Could not save your design. Please try again.'),
          isError: true,
          duration: const Duration(seconds: 4),
        );
      }
    }
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '↑↓ walk · ←→ turn · drag to look',
        style: GoogleFonts.poppins(
            fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}

class _CatalogThumb extends StatelessWidget {
  const _CatalogThumb({required this.cat});

  final RoomCatalogItem cat;

  @override
  Widget build(BuildContext context) {
    final image = cat.imageAsset;
    if (image != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          image,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _iconFallback(),
        ),
      );
    }
    return _iconFallback();
  }

  Widget _iconFallback() => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(cat.icon, size: 24, color: AppColors.accent),
      );
}
