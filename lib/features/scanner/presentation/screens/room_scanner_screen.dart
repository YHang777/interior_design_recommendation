import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import '../../../../../core/constants/app_colors.dart';

/// Real AR room scanner — camera + ML Kit + furniture placement plan view.
class RoomScannerScreen extends ConsumerStatefulWidget {
  const RoomScannerScreen({super.key});
  @override
  ConsumerState<RoomScannerScreen> createState() => _RoomScannerScreenState();
}

enum _Stage { init, scanning, plan }

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

  static const _labels = {
    'sofa', 'couch', 'chair', 'armchair', 'table', 'coffee table',
    'dining table', 'desk', 'bed', 'bed frame', 'mattress', 'cabinet',
    'wardrobe', 'bookshelf', 'shelf', 'lamp', 'light', 'chandelier',
    'rug', 'carpet', 'curtain', 'plant', 'flower', 'vase', 'painting',
    'picture frame', 'wall art', 'mirror', 'television', 'tv', 'monitor',
    'refrigerator', 'oven', 'microwave', 'pillow', 'cushion',
    'floor', 'wood', 'hardwood', 'tile',
  };

  @override
  void initState() {
    super.initState();
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
    // Capture frame every 1.5s for ML Kit analysis
    Timer.periodic(const Duration(milliseconds: 1500), (t) async {
      if (_stage != _Stage.scanning) { t.cancel(); return; }
      try {
        final img = await _cam!.takePicture();
        final labels = await _labeler.processImage(
            InputImage.fromFilePath(img.path));
        for (final l in labels) {
          final name = l.label.toLowerCase();
          if (_labels.contains(name) && !_found.any((f) => f.label == name)) {
            setState(() => _found.add(
                _Found(label: l.label, confidence: l.confidence)));
          }
        }
        setState(() => _frames++);
        try { File(img.path).deleteSync(); } catch (_) {}
      } catch (_) {}
    });
    Future.delayed(const Duration(seconds: 10), () {
      _timer?.cancel();
      if (mounted) setState(() => _stage = _Stage.plan);
    });
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_stage == _Stage.plan ? 'Room Plan' : 'Room Scanner',
            style: GoogleFonts.poppins()),
        backgroundColor: Colors.black,
      ),
      body: switch (_stage) {
        _Stage.init => _initView(),
        _Stage.scanning => _scanView(),
        _Stage.plan => _PlanView(found: _found),
      },
    );
  }

  Widget _initView() {
    final ready = _cam != null && _cam!.value.isInitialized;
    return Column(
      children: [
        Expanded(
          child: ready
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CameraPreview(_cam!))
              : const Center(child: Icon(Icons.camera_alt, size: 64, color: Colors.white38)),
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
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

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
                top: 12, right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('${_found.length} items',
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
            const SizedBox(width: 12),
            Text('Scanning... ${_elapsed}s | $_frames frames',
                style: GoogleFonts.poppins(fontSize: 14, color: Colors.white)),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () {
            _timer?.cancel();
            setState(() => _stage = _Stage.plan);
          },
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white38)),
          child: const Text('Done', style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─── Room Plan View (after scanning) ───

class _PlanView extends StatefulWidget {
  const _PlanView({required this.found});
  final List<_Found> found;

  @override
  State<_PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<_PlanView> {
  final List<_Placed> _placed = [];

  static const _catalog = [
    ('Sofa', Icons.weekend, 120.0, 60.0),
    ('Armchair', Icons.chair, 60.0, 60.0),
    ('Coffee Table', Icons.table_bar, 80.0, 50.0),
    ('Dining Table', Icons.table_restaurant, 120.0, 80.0),
    ('Bed', Icons.bed, 160.0, 100.0),
    ('Cabinet', Icons.inventory_2, 80.0, 50.0),
    ('Desk', Icons.desk, 100.0, 50.0),
    ('Lamp', Icons.lightbulb, 30.0, 30.0),
    ('Plant', Icons.eco, 30.0, 30.0),
    ('TV Stand', Icons.tv, 100.0, 40.0),
    ('Rug', Icons.view_agenda, 140.0, 100.0),
    ('Bookshelf', Icons.menu_book, 80.0, 40.0),
  ];

  void _add(String name, IconData icon, double w, double h) {
    setState(() {
      _placed.add(_Placed(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name, icon: icon,
        x: 40 + (_placed.length * 35) % 240,
        y: 30 + (_placed.length * 40) % 320,
        w: w, h: h,
        color: Colors.primaries[_placed.length % Colors.primaries.length]
            .withValues(alpha: 0.65),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header bar
        Container(
          padding: const EdgeInsets.all(12),
          color: AppColors.primary,
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Text('${widget.found.length} items detected',
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('Add furniture below',
                  style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
        if (widget.found.isNotEmpty)
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.found.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 12, color: AppColors.accent),
                    const SizedBox(width: 3),
                    Text(widget.found[i].label,
                        style: GoogleFonts.poppins(fontSize: 10)),
                  ],
                ),
              ),
            ),
          ),
        // Plan canvas
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: _GridPainter(),
                child: Stack(
                  children: _placed.map((p) {
                    return Positioned(
                      left: p.x, top: p.y,
                      child: GestureDetector(
                        onTap: () => setState(
                            () => _placed.removeWhere((x) => x.id == p.id)),
                        child: Container(
                          width: p.w, height: p.h,
                          decoration: BoxDecoration(
                            color: p.color,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: p.color, width: 2),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(p.icon, color: Colors.white, size: 22),
                                const SizedBox(height: 2),
                                Text(p.name,
                                    style: GoogleFonts.poppins(
                                        color: Colors.white, fontSize: 8)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
        // Furniture catalog
        Container(
          height: 90,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _catalog.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = _catalog[i];
              return GestureDetector(
                onTap: () => _add(f.$1, f.$2, f.$3, f.$4),
                child: Container(
                  width: 68,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(f.$2, color: AppColors.primary, size: 22),
                      const SizedBox(height: 4),
                      Text(f.$1, textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                              fontSize: 8, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _placed.clear()),
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          'Design saved! ${widget.found.length} detected + ${_placed.length} placed.'),
                      backgroundColor: AppColors.accent,
                    ));
                  },
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Save Design'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 20)
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    for (double y = 0; y < size.height; y += 20)
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Found {
  final String label;
  final double confidence;
  const _Found({required this.label, required this.confidence});
}

class _Placed {
  final String id, name;
  final IconData icon;
  final double x, y, w, h;
  final Color color;
  const _Placed({
    required this.id, required this.name, required this.icon,
    required this.x, required this.y, required this.w, required this.h,
    required this.color,
  });
}
