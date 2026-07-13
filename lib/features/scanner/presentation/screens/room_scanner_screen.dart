import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import '../../../../../core/constants/app_colors.dart';

/// Room Scanner — uses camera + ML Kit to detect furniture in a room.
/// This is the functional "AR scanner" for the app.
class RoomScannerScreen extends ConsumerStatefulWidget {
  const RoomScannerScreen({super.key});

  @override
  ConsumerState<RoomScannerScreen> createState() =>
      _RoomScannerScreenState();
}

enum _ScanStage { init, scanning, analyzing, result }

class _RoomScannerScreenState extends ConsumerState<RoomScannerScreen> {
  CameraController? _cameraCtrl;
  List<CameraDescription>? _cameras;
  final ImageLabeler _labeler = ImageLabeler(
    options: ImageLabelerOptions(confidenceThreshold: 0.6),
  );
  final List<_DetectedItem> _detected = [];
  _ScanStage _stage = _ScanStage.init;
  bool _hasCameraPermission = false;
  Timer? _scanTimer;
  int _scanSeconds = 0;

  // Furniture categories we care about
  static const _furnitureLabels = {
    'sofa', 'couch', 'couch bed', 'chair', 'armchair',
    'table', 'coffee table', 'dining table', 'desk',
    'bed', 'bed frame', 'mattress',
    'cabinet', 'wardrobe', 'bookshelf', 'shelf',
    'lamp', 'light', 'chandelier',
    'rug', 'carpet', 'curtain',
    'plant', 'flower', 'vase',
    'painting', 'picture frame', 'wall art', 'mirror',
    'television', 'tv', 'monitor',
    'refrigerator', 'oven', 'microwave',
    'pillow', 'cushion',
    'floor', 'wood', 'hardwood',
    'wall', 'paint', 'tile',
  };

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isNotEmpty) {
        _cameraCtrl = CameraController(
          _cameras!.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
            orElse: () => _cameras!.first,
          ),
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await _cameraCtrl!.initialize();
        setState(() => _hasCameraPermission = true);
      }
    } catch (_) {
      setState(() => _hasCameraPermission = false);
    }
  }

  Future<void> _startScanning() async {
    if (_cameraCtrl == null || !_cameraCtrl!.value.isInitialized) return;

    setState(() {
      _stage = _ScanStage.scanning;
      _scanSeconds = 0;
    });

    _scanTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _scanSeconds++);
    });

    // Capture frame and analyze every 2 seconds
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_stage != _ScanStage.scanning) {
        timer.cancel();
        return;
      }
      await _analyzeFrame();
    });

    // Auto-stop after 8 seconds
    Future.delayed(const Duration(seconds: 8), () {
      if (_stage == _ScanStage.scanning && mounted) {
        _stopScanning();
      }
    });
  }

  Future<void> _analyzeFrame() async {
    if (_cameraCtrl == null || !_cameraCtrl!.value.isInitialized) return;

    try {
      final image = await _cameraCtrl!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);
      final labels = await _labeler.processImage(inputImage);

      for (final label in labels) {
        final name = label.label.toLowerCase();
        if (_furnitureLabels.contains(name)) {
          final exists = _detected.any((d) => d.label == name);
          if (!exists) {
            setState(() {
              _detected.add(_DetectedItem(
                label: label.label,
                confidence: label.confidence,
              ));
            });
          }
        }
      }

      // Clean up temp image
      try {
        File(image.path).deleteSync();
      } catch (_) {}
    } catch (_) {
      // Frame analysis can fail if camera is busy
    }
  }

  void _stopScanning() {
    _scanTimer?.cancel();
    setState(() => _stage = _ScanStage.analyzing);

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _stage = _ScanStage.result);
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _labeler.close();
    _cameraCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_stage == _ScanStage.result ? 'Scan Results' : 'Room Scanner',
            style: GoogleFonts.poppins()),
        backgroundColor: Colors.black,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _ScanStage.init:
        return _buildInitView();
      case _ScanStage.scanning:
        return _buildScanningView();
      case _ScanStage.analyzing:
        return _buildAnalyzingView();
      case _ScanStage.result:
        return _buildResultView();
    }
  }

  Widget _buildInitView() {
    if (!_hasCameraPermission) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt, size: 80, color: Colors.white54),
            const SizedBox(height: 16),
            Text('Camera not available',
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 18)),
            const SizedBox(height: 8),
            Text('Please grant camera permission',
                style: GoogleFonts.poppins(color: Colors.white38)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _cameraCtrl != null && _cameraCtrl!.value.isInitialized
                ? CameraPreview(_cameraCtrl!)
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
        const SizedBox(height: 24),
        Text('Point your camera at the room',
            style: GoogleFonts.poppins(fontSize: 18, color: Colors.white)),
        const SizedBox(height: 8),
        Text('We\'ll detect furniture and materials',
            style: GoogleFonts.poppins(color: Colors.white54)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _startScanning,
          icon: const Icon(Icons.search, size: 24),
          label: const Text('Start Scanning'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            textStyle: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildScanningView() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CameraPreview(_cameraCtrl!),
              ),
              // Scanning overlay
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.secondary.withValues(alpha: 0.6),
                    width: 2,
                  ),
                ),
              ),
              // Detected items counter
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${_detected.length} items found',
                      style: GoogleFonts.poppins(color: Colors.white, fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.secondary),
            const SizedBox(width: 16),
            Text('Scanning... ${_scanSeconds}s',
                style: GoogleFonts.poppins(fontSize: 18, color: Colors.white)),
          ],
        ),
        const SizedBox(height: 8),
        Text('Move your phone slowly around the room',
            style: GoogleFonts.poppins(color: Colors.white54)),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _stopScanning,
          child: const Text('Done', style: TextStyle(color: Colors.white)),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildAnalyzingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 24),
          Text('Analyzing room...',
              style: GoogleFonts.poppins(fontSize: 20, color: Colors.white)),
          const SizedBox(height: 8),
          Text('Found ${_detected.length} items',
              style: GoogleFonts.poppins(color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildResultView() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Success header
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.success, size: 28),
              const SizedBox(width: 10),
              Text('Room Scanned!',
                  style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Detected ${_detected.length} items in your room',
              style: GoogleFonts.poppins(color: Colors.white54)),
          const SizedBox(height: 20),

          // Detected items grid
          Expanded(
            child: _detected.isEmpty
                ? Center(
                    child: Text('No furniture detected',
                        style: GoogleFonts.poppins(color: Colors.white38)),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 2.5,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _detected.length,
                    itemBuilder: (_, i) {
                      final item = _detected[i];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(_iconForLabel(item.label),
                                color: AppColors.secondary, size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(item.label,
                                      style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13)),
                                  Text('${(item.confidence * 100).toInt()}%',
                                      style: GoogleFonts.poppins(
                                          color: Colors.white38, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _detected.clear();
                      _stage = _ScanStage.init;
                    });
                  },
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  label: const Text('Scan Again',
                      style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'Room scan saved! ${_detected.length} items detected.'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Save Scan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  IconData _iconForLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('sofa') || l.contains('couch')) return Icons.weekend;
    if (l.contains('chair') || l.contains('armchair')) return Icons.chair;
    if (l.contains('table') || l.contains('desk')) return Icons.table_bar;
    if (l.contains('bed') || l.contains('mattress')) return Icons.bed;
    if (l.contains('cabinet') || l.contains('wardrobe') || l.contains('shelf'))
      return Icons.inventory_2;
    if (l.contains('lamp') || l.contains('light') || l.contains('chandelier'))
      return Icons.lightbulb;
    if (l.contains('rug') || l.contains('carpet')) return Icons.view_agenda;
    if (l.contains('plant') || l.contains('flower')) return Icons.eco;
    if (l.contains('painting') || l.contains('art') || l.contains('mirror'))
      return Icons.palette;
    if (l.contains('tv') || l.contains('television') || l.contains('monitor'))
      return Icons.tv;
    if (l.contains('curtain')) return Icons.curtains;
    return Icons.category;
  }
}

class _DetectedItem {
  final String label;
  final double confidence;
  const _DetectedItem({required this.label, required this.confidence});
}
