import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../models/room_design.dart';
import '../../../homeowner/presentation/providers/design_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// Real AR room scanner — camera + ML Kit + interactive floor plan editor.
class RoomScannerScreen extends ConsumerStatefulWidget {
  const RoomScannerScreen({super.key, this.existingDesign});
  final RoomDesign? existingDesign;

  @override
  ConsumerState<RoomScannerScreen> createState() => _RoomScannerScreenState();
}

enum _Stage { init, scanning, roomSelect, plan }

class _RoomScannerScreenState extends ConsumerState<RoomScannerScreen> {
  CameraController? _cam;
  List<CameraDescription>? _cameras;
  final ImageLabeler _labeler =
      ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.5));
  final List<_Found> _found = [];
  _Stage _stage = _Stage.init;
  int _elapsed = 0;
  int _frames = 0;
  Timer? _timer;
  String _roomType = 'living_room';

  // Editor state
  late List<FurniturePlacement> _furniture;
  double _roomW = 400;
  double _roomH = 500;
  int _selectedIdx = -1;
  bool _isEditingDimensions = false;

  static const _labels = {
    'sofa', 'couch', 'chair', 'armchair', 'table', 'coffee table',
    'dining table', 'desk', 'bed', 'bed frame', 'mattress', 'cabinet',
    'wardrobe', 'bookshelf', 'shelf', 'lamp', 'light', 'chandelier',
    'rug', 'carpet', 'curtain', 'plant', 'flower', 'vase', 'painting',
    'picture frame', 'wall art', 'mirror', 'television', 'tv', 'monitor',
    'refrigerator', 'oven', 'microwave', 'pillow', 'cushion',
    'floor', 'wood', 'hardwood', 'tile',
  };

  // ─── Furniture catalog with image assets ───
  static const _catalog = [
    _Cat('Sofa', 'sofa', Icons.weekend, 'seating', 180, 90,
        'assets/images/furniture_sofa_modern.png'),
    _Cat('Armchair', 'armchair', Icons.chair, 'seating', 70, 70,
        'assets/images/furniture_chair_modern.png'),
    _Cat('Coffee Table', 'coffee_table', Icons.table_bar, 'tables', 100, 50,
        'assets/images/furniture_table_coffee.png'),
    _Cat('Dining Table', 'dining_table', Icons.table_restaurant, 'tables', 140, 100,
        'assets/images/furniture_table_dining.png'),
    _Cat('Bed', 'bed', Icons.bed, 'bedroom', 200, 160,
        'assets/images/furniture_bed_modern.png'),
    _Cat('Cabinet', 'cabinet', Icons.inventory_2, 'storage', 90, 50,
        'assets/images/furniture_cabinet_modern.png'),
    _Cat('Desk', 'desk', Icons.desk, 'office', 120, 60,
        'assets/images/furniture_desk_modern.png'),
    _Cat('Floor Lamp', 'floor_lamp', Icons.lightbulb, 'lighting', 25, 25,
        'assets/images/furniture_lamp_floor.png'),
    _Cat('Plant', 'plant', Icons.eco, 'decor', 30, 30,
        'assets/images/plant.jpg'),
    _Cat('TV Stand', 'tv_stand', Icons.tv, 'media', 140, 45, null),
    _Cat('Rug', 'rug', Icons.view_agenda, 'decor', 160, 120,
        'assets/images/furniture_rug_modern.png'),
    _Cat('Bookshelf', 'bookshelf', Icons.menu_book, 'storage', 90, 30, null),
  ];

  // ─── Room types ───
  static const _roomTypes = [
    ('living_room', 'Living Room', Icons.weekend),
    ('bedroom', 'Bedroom', Icons.bed),
    ('kitchen', 'Kitchen', Icons.kitchen),
    ('bathroom', 'Bathroom', Icons.bathtub),
    ('dining_room', 'Dining Room', Icons.table_restaurant),
    ('home_office', 'Home Office', Icons.desk),
  ];

  @override
  void initState() {
    super.initState();
    _furniture = widget.existingDesign?.furniture.toList() ?? [];
    if (widget.existingDesign != null) {
      _roomW = widget.existingDesign!.widthCm;
      _roomH = widget.existingDesign!.heightCm;
      _roomType = widget.existingDesign!.roomType;
      _found.addAll(widget.existingDesign!.detectedItems
          .map((l) => _Found(label: l, confidence: 0.9)));
      _stage = _Stage.plan;
    }
    _setupCam();
  }

  Future<void> _setupCam() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isNotEmpty) {
        _cam = CameraController(
          _cameras!.firstWhere(
              (c) => c.lensDirection == CameraLensDirection.back,
              orElse: () => _cameras!.first),
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await _cam!.initialize();
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  void _startScan() async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    setState(() {
      _stage = _Stage.scanning;
      _found.clear();
      _elapsed = 0;
      _frames = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
    Timer.periodic(const Duration(milliseconds: 1500), (t) async {
      if (_stage != _Stage.scanning) {
        t.cancel();
        return;
      }
      try {
        final img = await _cam!.takePicture();
        final labels =
            await _labeler.processImage(InputImage.fromFilePath(img.path));
        for (final l in labels) {
          final name = l.label.toLowerCase();
          if (_labels.contains(name) && !_found.any((f) => f.label == name)) {
            setState(
                () => _found.add(_Found(label: l.label, confidence: l.confidence)));
          }
        }
        setState(() => _frames++);
        try {
          File(img.path).deleteSync();
        } catch (_) {}
      } catch (_) {}
    });
    Future.delayed(const Duration(seconds: 10), () {
      _timer?.cancel();
      if (mounted && _stage == _Stage.scanning) {
        setState(() => _stage = _Stage.roomSelect);
      }
    });
  }

  void _autoPlaceFound() {
    final rng = Random();
    final items = <FurniturePlacement>[];
    for (final f in _found) {
      final cat = _matchCatalog(f.label);
      final x = (rng.nextDouble() * (_roomW - cat.defaultWidth))
          .clamp(10.0, _roomW - cat.defaultWidth - 10);
      final y = (rng.nextDouble() * (_roomH - cat.defaultHeight))
          .clamp(10.0, _roomH - cat.defaultHeight - 10);
      items.add(FurniturePlacement(
        id: DateTime.now().microsecondsSinceEpoch.toString() + items.length.toString(),
        name: cat.name,
        iconName: cat.iconName,
        x: x,
        y: y,
        width: cat.defaultWidth,
        height: cat.defaultHeight,
        imageAsset: cat.imageAsset,
      ));
    }
    setState(() => _furniture = items);
  }

  _Cat _matchCatalog(String label) {
    final lower = label.toLowerCase();
    for (final c in _catalog) {
      if (c.name.toLowerCase().contains(lower) ||
          lower.contains(c.name.toLowerCase())) {
        return c;
      }
    }
    return _Cat(label, 'unknown', Icons.folder, 'misc', 80, 60, null);
  }

  void _addFromCatalog(_Cat cat) {
    final id =
        DateTime.now().microsecondsSinceEpoch.toString();
    final x = (20 + _furniture.length * 30) % (_roomW - cat.defaultWidth).toInt();
    final y = (15 + _furniture.length * 35) % (_roomH - cat.defaultHeight).toInt();
    setState(() {
      _furniture.add(FurniturePlacement(
        id: id,
        name: cat.name,
        iconName: cat.iconName,
        x: x.toDouble().clamp(5, _roomW - cat.defaultWidth - 5),
        y: y.toDouble().clamp(5, _roomH - cat.defaultHeight - 5),
        width: cat.defaultWidth,
        height: cat.defaultHeight,
        imageAsset: cat.imageAsset,
      ));
    });
  }

  Future<void> _saveDesign() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please sign in to save designs'),
              backgroundColor: AppColors.error),
        );
      }
      return;
    }

    final nameCtrl = TextEditingController(
        text: widget.existingDesign?.name ?? 'My $_roomTypeLabel Design');

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
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
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    final ds = ref.read(roomDesignDatasourceProvider);
    final now = DateTime.now();
    final designId = widget.existingDesign?.id ??
        'design-${now.millisecondsSinceEpoch}';

    final design = RoomDesign(
      id: designId,
      name: name,
      roomType: _roomType,
      widthCm: _roomW,
      heightCm: _roomH,
      furniture: _furniture,
      detectedItems: _found.map((f) => f.label).toList(),
      userId: user.uid,
      createdAt: widget.existingDesign?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      if (widget.existingDesign != null) {
        await ds.updateDesign(designId, design.toJson());
      } else {
        await ds.createDesign(
            designId: designId, data: design.toJson());
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Design "$name" saved!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  String get _roomTypeLabel {
    for (final rt in _roomTypes) {
      if (rt.$1 == _roomType) return rt.$2;
    }
    return _roomType;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _labeler.close();
    _cam?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _stage == _Stage.plan
          ? AppColors.background
          : Colors.black,
      appBar: AppBar(
        title: Text(
          switch (_stage) {
            _Stage.init || _Stage.scanning => 'Room Scanner',
            _Stage.roomSelect => 'Room Scanner',
            _Stage.plan => widget.existingDesign != null
                ? 'Edit: ${widget.existingDesign!.name}'
                : 'Room Plan',
          },
          style: GoogleFonts.poppins(),
        ),
        backgroundColor:
            _stage == _Stage.plan ? AppColors.background : Colors.black,
        foregroundColor:
            _stage == _Stage.plan ? AppColors.textPrimary : Colors.white,
        actions: _stage == _Stage.plan
            ? [
                IconButton(
                  icon: const Icon(Icons.save),
                  tooltip: 'Save Design',
                  onPressed: _saveDesign,
                ),
              ]
            : null,
      ),
      body: switch (_stage) {
        _Stage.init => _initView(),
        _Stage.scanning => _scanView(),
        _Stage.roomSelect => _roomSelectView(),
        _Stage.plan => _planEditor(),
      },
    );
  }

  // ─── Init view (camera preview) ───
  Widget _initView() {
    final ready = _cam != null && _cam!.value.isInitialized;
    return Column(
      children: [
        Expanded(
          child: ready
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CameraPreview(_cam!))
              : const Center(
                  child:
                      Icon(Icons.camera_alt, size: 64, color: Colors.white38)),
        ),
        const SizedBox(height: 20),
        Text('Point camera at the room',
            style: GoogleFonts.poppins(fontSize: 18, color: Colors.white)),
        const SizedBox(height: 6),
        Text('We\'ll detect furniture and materials',
            style: GoogleFonts.poppins(color: Colors.white54)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: ready ? _startScan : null,
          icon: const Icon(Icons.search, size: 24),
          label: const Text('Start Scanning'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ─── Scanning view ───
  Widget _scanView() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CameraPreview(_cam!)),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('${_found.length} items',
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.accent)),
            const SizedBox(width: 12),
            Text('Scanning... ${_elapsed}s | $_frames frames',
                style: GoogleFonts.poppins(
                    fontSize: 14, color: Colors.white)),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () {
            _timer?.cancel();
            setState(() => _stage = _Stage.roomSelect);
          },
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white38)),
          child: const Text('Done',
              style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─── Room type selector ───
  Widget _roomSelectView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 64, color: AppColors.accent),
          const SizedBox(height: 16),
          Text('${_found.length} items detected!',
              style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 8),
          Text('Select your room type to begin designing:',
              style: GoogleFonts.poppins(
                  color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _roomTypes.map((rt) {
              final selected = _roomType == rt.$1;
              return GestureDetector(
                onTap: () => setState(() => _roomType = rt.$1),
                child: Container(
                  width: 140,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 20),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.accent
                        : Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: selected
                        ? Border.all(
                            color: AppColors.accentLight, width: 2)
                        : null,
                  ),
                  child: Column(
                    children: [
                      Icon(rt.$3,
                          color: Colors.white, size: 32),
                      const SizedBox(height: 8),
                      Text(rt.$2,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: () {
              _autoPlaceFound();
              setState(() => _stage = _Stage.plan);
            },
            icon: const Icon(Icons.design_services),
            label: const Text('Start Designing'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 40, vertical: 16),
              minimumSize: const Size(double.infinity, 56),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Floor plan editor ───
  Widget _planEditor() {
    return Column(
      children: [
        // Detected items — tappable chips that auto-add to plan
        if (_found.isNotEmpty)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.document_scanner, size: 14,
                        color: AppColors.accent),
                    const SizedBox(width: 6),
                    Text('Detected — tap to add to plan',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent)),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 34,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _found.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: 6),
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () {
                        final cat = _matchCatalog(_found[i].label);
                        _addFromCatalog(cat);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.accent
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.accent
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_circle_outline,
                                size: 14, color: AppColors.accent),
                            const SizedBox(width: 5),
                            Text(_found[i].label,
                                style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.accent)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Room canvas — floor plan style
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedIdx = -1),
            child: Center(
              child: AspectRatio(
                aspectRatio: _roomW / _roomH,
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBF5), // warm paper
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppColors.primary,
                        width: 3), // thick wall border
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder: (ctx, constraints) {
                      final canvasW =
                          constraints.maxWidth;
                      final canvasH =
                          constraints.maxHeight;
                      final scaleX = canvasW / _roomW;
                      final scaleY = canvasH / _roomH;
                      final s = min(scaleX, scaleY);
                      return Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          // Subtle grid
                          CustomPaint(
                            painter:
                                _FloorPlanGridPainter(
                                    s, _roomW, _roomH),
                            size: Size.infinite,
                          ),
                          // Dimension labels on walls
                          _dimLabel('${_roomW.toInt()} cm',
                              top: -20,
                              left: canvasW / 2 - 30),
                          _dimLabel('${_roomH.toInt()} cm',
                              left: -22,
                              top: canvasH / 2 - 10,
                              vertical: true),
                          // Room type label
                          Positioned(
                            top: 6,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                        horizontal: 10,
                                        vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary
                                      .withValues(
                                          alpha: 0.75),
                                  borderRadius:
                                      BorderRadius
                                          .circular(10),
                                ),
                                child: Text(
                                  _roomTypeLabel,
                                  style: GoogleFonts
                                      .poppins(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight:
                                        FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Furniture placements
                          ..._furniture
                              .asMap()
                              .entries
                              .map((entry) {
                            final idx = entry.key;
                            final f = entry.value;
                            final isSelected =
                                idx == _selectedIdx;
                            final itemW =
                                f.width * s;
                            final itemH =
                                f.height * s;
                            return Positioned(
                              left: f.x * s,
                              top: f.y * s,
                              child: GestureDetector(
                                onTap: () => setState(() =>
                                    _selectedIdx =
                                        idx),
                                onLongPress: () {
                                  setState(() {
                                    _furniture.removeAt(
                                        idx);
                                    if (_selectedIdx ==
                                        idx) {
                                      _selectedIdx =
                                          -1;
                                    }
                                  });
                                },
                                onPanUpdate:
                                    (details) {
                                  final newX = (f.x +
                                          details
                                              .delta
                                              .dx /
                                              s)
                                      .clamp(
                                          0.0,
                                          _roomW -
                                              f.width)
                                      .toDouble();
                                  final newY = (f.y +
                                          details
                                              .delta
                                              .dy /
                                              s)
                                      .clamp(
                                          0.0,
                                          _roomH -
                                              f.height)
                                      .toDouble();
                                  final updated =
                                      _furniture
                                          .toList();
                                  updated[idx] = f
                                      .copyWith(
                                          x: newX,
                                          y: newY);
                                  setState(() =>
                                      _furniture =
                                          updated);
                                },
                                child: Container(
                                  width: itemW,
                                  height: itemH,
                                  decoration:
                                      BoxDecoration(
                                    color: isSelected
                                        ? AppColors
                                            .accent
                                            .withValues(
                                                alpha:
                                                    0.3)
                                        : AppColors
                                            .primary
                                            .withValues(
                                                alpha:
                                                    0.15),
                                    borderRadius:
                                        BorderRadius
                                            .circular(
                                                3),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors
                                              .accent
                                          : AppColors
                                              .primary
                                              .withValues(alpha: 0.4),
                                      width:
                                          isSelected
                                              ? 2.5
                                              : 1.2,
                                    ),
                                  ),
                                  child: itemW > 40 &&
                                          itemH > 30
                                      ? Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize:
                                              MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _iconFor(f
                                                  .iconName),
                                              size: min(
                                                  itemW *
                                                      0.35,
                                                  20),
                                              color: isSelected
                                                  ? AppColors.accent
                                                  : AppColors.textSecondary,
                                            ),
                                            if (itemW >
                                                55)
                                              Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                                child: Text(
                                                  f.name,
                                                  textAlign: TextAlign.center,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: min(itemW * 0.1, 10),
                                                    fontWeight: FontWeight.w600,
                                                    color: isSelected
                                                        ? AppColors.accent
                                                        : AppColors.textPrimary,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        )
                                      : Center(
                                          child: Icon(
                                            _iconFor(f
                                                .iconName),
                                            size: min(
                                                itemW *
                                                    0.5,
                                                14),
                                            color: isSelected
                                                ? AppColors.accent
                                                : AppColors.textSecondary,
                                          ),
                                        ),
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),

        // Selected item info
        if (_selectedIdx >= 0 &&
            _selectedIdx < _furniture.length)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            color: AppColors.surface,
            child: Row(
              children: [
                Icon(Icons.touch_app,
                    size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _furniture[_selectedIdx].name,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ),
                Text('Tap to select • Drag to move • Long-press to remove',
                    style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: AppColors.textHint)),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    setState(() {
                      _furniture.removeAt(_selectedIdx);
                      _selectedIdx = -1;
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

        // Furniture catalog
        Container(
          height: 84,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border:
                Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Text('Add:',
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(width: 6),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _catalog.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final cat = _catalog[i];
                    return GestureDetector(
                      onTap: () => _addFromCatalog(cat),
                      child: Container(
                        width: 60,
                        padding:
                            const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.border),
                        ),
                        child: Column(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Icon(cat.icon,
                                size: 20,
                                color: AppColors.primary),
                            const SizedBox(height: 2),
                            Text(cat.name,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors
                                        .textSecondary)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Bottom bar: dimensions + actions
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border:
                Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              // Room dimensions editor
              if (_isEditingDimensions) ...[
                SizedBox(
                  width: 80,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'W (cm)',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final parsed = double.tryParse(v);
                      if (parsed != null && parsed > 50) {
                        setState(() => _roomW = parsed);
                      }
                    },
                    controller: TextEditingController(
                        text: _roomW.toInt().toString()),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'H (cm)',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final parsed = double.tryParse(v);
                      if (parsed != null && parsed > 50) {
                        setState(() => _roomH = parsed);
                      }
                    },
                    controller: TextEditingController(
                        text: _roomH.toInt().toString()),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.check, size: 20),
                  onPressed: () => setState(
                      () => _isEditingDimensions = false),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ] else ...[
                GestureDetector(
                  onTap: () => setState(
                      () => _isEditingDimensions = true),
                  child: Row(
                    children: [
                      const Icon(Icons.crop_free,
                          size: 18,
                          color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                          'Room: ${_roomW.toInt()} × ${_roomH.toInt()} cm',
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: AppColors.textSecondary)),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit,
                          size: 14,
                          color: AppColors.textHint),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _furniture.clear();
                    _selectedIdx = -1;
                  });
                },
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Clear'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _saveDesign,
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dimLabel(String text,
      {double? top, double? left, bool vertical = false}) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary)),
    );
    return Positioned(
      top: top,
      left: left,
      child: vertical
          ? RotatedBox(quarterTurns: 3, child: child)
          : child,
    );
  }

  // ─── Icon lookup ───
  IconData _iconFor(String iconName) {
    for (final c in _catalog) {
      if (c.iconName == iconName) return c.icon;
    }
    return Icons.folder;
  }
}

// ─── Catalog item ───
class _Cat {
  final String name;
  final String iconName;
  final IconData icon;
  final String category;
  final double defaultWidth;
  final double defaultHeight;
  final String? imageAsset;

  const _Cat(this.name, this.iconName, this.icon, this.category,
      this.defaultWidth, this.defaultHeight, this.imageAsset);
}

// ─── Floor plan grid painter ───
class _FloorPlanGridPainter extends CustomPainter {
  _FloorPlanGridPainter(this.scale, this.roomW, this.roomH);
  final double scale;
  final double roomW;
  final double roomH;

  @override
  void paint(Canvas canvas, Size size) {
    // Subtle 50cm grid
    final grid50 = 50 * scale;
    final p = Paint()
      ..color = const Color(0xFFE8E4DB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.3;
    for (double x = grid50; x < size.width; x += grid50) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = grid50; y < size.height; y += grid50) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }

    // 100cm grid (slightly stronger)
    final grid100 = 100 * scale;
    final p100 = Paint()
      ..color = const Color(0xFFD4CFC4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (double x = grid100; x < size.width; x += grid100) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p100);
    }
    for (double y = grid100; y < size.height; y += grid100) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p100);
    }
  }

  @override
  bool shouldRepaint(covariant _FloorPlanGridPainter old) =>
      old.scale != scale || old.roomW != roomW || old.roomH != roomH;
}

// ─── Data classes ───
class _Found {
  final String label;
  final double confidence;
  const _Found({required this.label, required this.confidence});
}
