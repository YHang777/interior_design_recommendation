import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
import '../../ar/data/room_finishes.dart';
import '../../homeowner/presentation/providers/design_providers.dart';
import '../../scanner/data/camera_rig.dart';
import '../../scanner/data/furniture_catalog.dart';
import '../data/showroom_designs.dart';
import 'walkthrough_controller.dart';
import 'walkthrough_painter.dart';
import 'walkthrough_scene.dart';

// Street View style walkthrough of a plan: you stand in the room in first
// person — ↑↓ walk forward/back along the heading, ←→ turn in place, drag the
// view to look around — and furniture can be placed at your spot. With no
// design it opens the showroom instead: predesigned room-type layouts browsed
// with arrow keys (or swipes) for inspiration, each walkable the same way.
// Pose stays 2D (position + heading); VR swaps the painter, not the model.
class WalkthroughScreen extends ConsumerStatefulWidget {
  const WalkthroughScreen({super.key, this.design});

  final RoomDesign? design;

  @override
  ConsumerState<WalkthroughScreen> createState() => _WalkthroughScreenState();
}

class _WalkthroughScreenState extends ConsumerState<WalkthroughScreen> {
  late WalkthroughController _ctl;
  final FirstPersonRig _rig = FirstPersonRig();
  final FocusNode _focus = FocusNode();
  final PageController _galleryCtrl = PageController();
  RoomCatalogItem? _placing;
  int _placingRotation = 0;
  bool _showHint = true;
  Timer? _repeat;
  final Map<String, ui.Image> _sprites = {};
  bool _inGallery;
  int _galleryPage = 0;
  RoomDesign? _showroomDesign;
  RoomDesign? _returnDesign;

  _WalkthroughScreenState() : _inGallery = false;

  @override
  void initState() {
    super.initState();
    _inGallery = widget.design == null;
    _ctl = WalkthroughController(design: widget.design ?? _emptyDesign());
    _loadSprites();
  }

  @override
  void dispose() {
    _repeat?.cancel();
    _galleryCtrl.dispose();
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // Decode every catalog photo (plus anything already on the design) so the
  // painter can stand them up as billboards; failures stay box/icon fallback.
  void _loadSprites() {
    final paths = <String>{
      for (final c in roomCatalog)
        if (c.imageAsset != null) c.imageAsset!,
      for (final f in _ctl.furniture)
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
      // Missing/broken asset — painter falls back to icon card or box.
    }
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

  @visibleForTesting
  RoomDesign get debugDesign => _currentDesign();

  @visibleForTesting
  bool get debugInGallery => _inGallery;

  @visibleForTesting
  int get debugGalleryIndex => _galleryPage;

  @visibleForTesting
  String? get debugShowroomId => _showroomDesign?.id;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back walks the mode stack first: a showroom room returns to the
      // gallery, and only leaving the gallery hands the current plan to
      // whoever pushed us (placements land back in the planner unsaved).
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_inGallery) {
          Navigator.of(context).pop(_returnDesign ?? widget.design);
        } else if (_showroomDesign != null) {
          _leaveToGallery();
        } else {
          Navigator.of(context).pop(_currentDesign());
        }
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text(
          _inGallery
              ? 'Showroom'
              : _showroomDesign?.name ?? 'Walkthrough',
          style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        actions: [
          if (!_inGallery) ...[
            IconButton(
              icon: const Icon(Icons.view_carousel),
              tooltip: 'Rooms',
              onPressed: _leaveToGallery,
            ),
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
        ],
      ),
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: _inGallery ? _galleryView() : _walkView(),
      ),
      ),
    );
  }

  // ─── Showroom gallery ───

  Widget _galleryView() {
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _galleryCtrl,
            onPageChanged: (i) => setState(() => _galleryPage = i),
            itemCount: showroomRooms.length,
            itemBuilder: (_, i) => _showroomCard(showroomRooms[i]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < showroomRooms.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _galleryPage ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _galleryPage
                            ? AppColors.accent
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '← → browse rooms · tap a room to walk',
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ),
              if (widget.design != null) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _resumeOwnDesign,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: Text(
                    'Back to my design',
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _showroomCard(ShowroomRoom room) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: GestureDetector(
        onTap: () => _enterShowroom(room),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: ColoredBox(
                      color: const Color(0xFFFAF7F0),
                      child: CustomPaint(
                        painter: _PlanThumbPainter(room.design),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(room.icon,
                            size: 20, color: AppColors.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            room.name,
                            style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      room.description,
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => _enterShowroom(room),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(40),
                        textStyle: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Walk this room'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _enterShowroom(ShowroomRoom room) {
    if (_showroomDesign == null && widget.design != null) {
      _returnDesign = _currentDesign();
    }
    _showroomDesign = room.design;
    _placing = null;
    _placingRotation = 0;
    _showHint = true;
    _rebuildController(room.design);
    setState(() => _inGallery = false);
  }

  void _leaveToGallery() {
    if (_showroomDesign == null && widget.design != null) {
      _returnDesign = _currentDesign();
    }
    setState(() {
      _inGallery = true;
      _showroomDesign = null;
      _placing = null;
      _placingRotation = 0;
    });
  }

  void _resumeOwnDesign() {
    final back = _returnDesign ?? widget.design;
    if (back == null) return;
    _returnDesign = null;
    _showroomDesign = null;
    _showHint = true;
    _rebuildController(back);
    setState(() => _inGallery = false);
  }

  void _rebuildController(RoomDesign design) {
    final old = _ctl;
    setState(() => _ctl = WalkthroughController(design: design));
    old.dispose();
    _loadSprites();
  }

  // ─── Walk view ───

  Widget _walkView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: WalkthroughScene(
            controller: _ctl,
            rig: _rig,
            design: _shellDesign,
            ghost: _placing == null ? null : _pending(),
            fallback: GestureDetector(
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
                    sprites: _sprites,
                    finishes: _painterFinishes,
                  ),
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
    );
  }

  // ─── Input ───

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_inGallery) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowLeft:
        case LogicalKeyboardKey.arrowUp:
          _flipGallery(-1);
        case LogicalKeyboardKey.arrowRight:
        case LogicalKeyboardKey.arrowDown:
          _flipGallery(1);
        case LogicalKeyboardKey.enter:
        case LogicalKeyboardKey.numpadEnter:
        case LogicalKeyboardKey.space:
          if (_galleryPage < showroomRooms.length) {
            _enterShowroom(showroomRooms[_galleryPage]);
          }
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
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

  void _flipGallery(int dir) {
    if (!_galleryCtrl.hasClients) return;
    final target = (_galleryPage + dir).clamp(0, showroomRooms.length - 1);
    if (target == _galleryPage) return;
    _galleryCtrl.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
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

  // The live plan as a RoomDesign: Save names/users it, and exiting pops it
  // to the caller — both must agree on what "the current plan" is. Walking a
  // showroom room snapshots that room (id cleared) so a save is a save-as.
  // The design's matched finishes paint the room; no finish fields (classic
  // cream look) for showroom rooms and pre-finish designs.
  FinishSelection? get _painterFinishes {
    final d = _showroomDesign ?? widget.design;
    if (d == null) return null;
    if (d.floorFinishType == null && d.wallFinishType == null) return null;
    return finishSelectionFrom(d);
  }

  // Finish source for the 3D room shell (live geometry rides the controller).
  RoomDesign get _shellDesign =>
      _showroomDesign ?? widget.design ?? _emptyDesign();

  RoomDesign _currentDesign({String? name, String? userId}) {
    final now = DateTime.now();
    final existing = _showroomDesign ?? widget.design;
    return RoomDesign(
      id: _showroomDesign != null ? '' : (existing?.id ?? ''),
      name: name ?? existing?.name ?? 'Walkthrough',
      roomType: existing?.roomType ?? 'living_room',
      widthCm: _ctl.roomW,
      heightCm: _ctl.roomH,
      furniture: List.of(_ctl.furniture),
      walls: List.of(_ctl.walls),
      detectedItems: existing?.detectedItems ?? const [],
      floorFinishType: existing?.floorFinishType,
      floorFinishColor: existing?.floorFinishColor,
      wallFinishType: existing?.wallFinishType,
      wallFinishColor: existing?.wallFinishColor,
      userId: userId ?? existing?.userId ?? '',
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Future<void> _saveDesign() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      showAppSnackbar(context, 'Please sign in to save designs',
          isError: true);
      return;
    }

    final existing = _showroomDesign ?? widget.design;
    final hasId = _showroomDesign == null &&
        existing != null &&
        existing.id.isNotEmpty;
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

    final design =
        _currentDesign(name: name, userId: user.uid).copyWith(id: designId);

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

// Top-down floor plan fitted into the card: wall ring as the floor slab,
// furniture footprints as chips (flat pieces read lighter than solid ones).
class _PlanThumbPainter extends CustomPainter {
  _PlanThumbPainter(this.design);

  final RoomDesign design;

  @override
  void paint(Canvas canvas, Size size) {
    final walls = design.walls;
    if (walls.length < 3) return;
    var minX = walls.first.dx, maxX = minX, minY = walls.first.dy, maxY = minY;
    for (final p in walls) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final w = math.max(maxX - minX, 1.0);
    final h = math.max(maxY - minY, 1.0);
    final scale =
        math.min((size.width - 28) / w, (size.height - 28) / h);
    final dx = (size.width - w * scale) / 2 - minX * scale;
    final dy = (size.height - h * scale) / 2 - minY * scale;

    final floor = Path()
      ..addPolygon(
          [for (final p in walls) Offset(p.dx * scale + dx, p.dy * scale + dy)],
          true);
    canvas.drawPath(floor, Paint()..color = const Color(0xFFF1EBDD));
    for (final f in design.furniture) {
      final rect = Rect.fromLTWH(
          f.x * scale + dx, f.y * scale + dy, f.width * scale, f.height * scale);
      final flat = f.height <= 4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1.5), const Radius.circular(3)),
        Paint()
          ..color =
              flat ? const Color(0xFFD8CCB8) : const Color(0xFFB98E6E),
      );
    }
    canvas.drawPath(
      floor,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFF6B5E4E),
    );
  }

  @override
  bool shouldRepaint(_PlanThumbPainter old) => old.design != design;
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
      return Image.asset(
        image,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _iconFallback(),
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
