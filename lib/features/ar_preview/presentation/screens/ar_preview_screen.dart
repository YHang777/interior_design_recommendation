import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/gradient_scaffold.dart';

/// Photo-based AR Preview — take/select a room photo, overlay materials/colors.
/// This delivers the "AR visualization" core feature without needing ARCore.
class ArPreviewScreen extends ConsumerStatefulWidget {
  const ArPreviewScreen({super.key});

  @override
  ConsumerState<ArPreviewScreen> createState() => _ArPreviewScreenState();
}

class _ArPreviewScreenState extends ConsumerState<ArPreviewScreen> {
  String? _imagePath;
  String _activeTool = 'wall'; // wall, floor, furniture
  final List<_OverlayZone> _zones = [];
  final ImagePicker _picker = ImagePicker();

  // Color palettes
  static const _wallColors = [
    Color(0xFFFFFFFF), Color(0xFFF5F0E8), Color(0xFFE8E0D5),
    Color(0xFFD4C5B9), Color(0xFFBCAAA4), Color(0xFF8D7B6F),
    Color(0xFF5C6B73), Color(0xFF2C3E50), Color(0xFF1A252F),
    Color(0xFFE8F5E9), Color(0xFFBBDEFB), Color(0xFFFFF3E0),
  ];

  static const _floorColors = [
    Color(0xFFDEB887), Color(0xFFD2B48C), Color(0xFF8B7355),
    Color(0xFF6B4226), Color(0xFF4A3728), Color(0xFF808080),
    Color(0xFFC0C0C0), Color(0xFFF5F5DC), Color(0xFFE8DCC8),
  ];

  void _addZone(Offset position) {
    setState(() {
      _zones.add(_OverlayZone(
        position: position,
        color: _activeTool == 'wall'
            ? _wallColors[0].withValues(alpha: 0.5)
            : _floorColors[0].withValues(alpha: 0.5),
        radius: 80,
        tool: _activeTool,
      ));
    });
  }

  void _updateZoneColor(int index, Color color) {
    setState(() {
      _zones[index] = _zones[index].copyWith(
          color: color.withValues(alpha: 0.5));
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked != null) setState(() => _imagePath = picked.path);
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('AR Preview'),
        actions: [
          if (_imagePath != null)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Preview saved (mocked)')),
                );
              },
            ),
        ],
      ),
      child: _imagePath == null ? _buildImagePicker() : _buildEditor(),
    );
  }

  Widget _buildImagePicker() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.view_in_ar, size: 80, color: Colors.white.withValues(alpha: 0.6)),
            const SizedBox(height: 24),
            Text('AR Room Preview',
                style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 8),
            Text('Take a photo of your room and preview\nnew colors and materials instantly.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: AppColors.textPrimary.withValues(alpha: 0.8))),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.camera_alt, size: 28),
              label: const Text('Take Photo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                minimumSize: const Size(double.infinity, 56),
                textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library, color: AppColors.textPrimary),
              label: const Text('Choose from Gallery',
                  style: TextStyle(color: Colors.white)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white38),
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 56),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      children: [
        // Photo with overlays
        Expanded(
          child: GestureDetector(
            onTapDown: (details) => _addZone(details.localPosition),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.file(
                    File(_imagePath!),
                    fit: BoxFit.contain,
                  ),
                ),
                // Overlay zones
                ..._zones.asMap().entries.map((entry) {
                  final zone = entry.value;
                  return Positioned(
                    left: zone.position.dx - zone.radius,
                    top: zone.position.dy - zone.radius,
                    child: GestureDetector(
                      onTap: () => _showColorPicker(entry.key, zone),
                      child: Container(
                        width: zone.radius * 2,
                        height: zone.radius * 2,
                        decoration: BoxDecoration(
                          color: zone.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.6),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),

        // Toolbar
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.black87,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Tool selector
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ToolBtn('Wall', Icons.format_paint, _activeTool == 'wall',
                      () => setState(() => _activeTool = 'wall')),
                  const SizedBox(width: 8),
                  _ToolBtn('Floor', Icons.view_agenda, _activeTool == 'floor',
                      () => setState(() => _activeTool = 'floor')),
                  const SizedBox(width: 8),
                  _ToolBtn('Furniture', Icons.chair, _activeTool == 'furniture',
                      () => setState(() => _activeTool = 'furniture')),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.undo, color: AppColors.textPrimary),
                    onPressed: _zones.isNotEmpty
                        ? () => setState(() => _zones.removeLast())
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear_all, color: AppColors.textPrimary),
                    onPressed: () => setState(() => _zones.clear()),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Color quick-palette
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: (_activeTool == 'wall' ? _wallColors : _floorColors)
                      .length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final color = _activeTool == 'wall'
                        ? _wallColors[i]
                        : _floorColors[i];
                    return GestureDetector(
                      onTap: () {
                        if (_zones.isNotEmpty) {
                          _updateZoneColor(_zones.length - 1, color);
                        }
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                          boxShadow: [
                            BoxShadow(
                                color: color.withValues(alpha: 0.4),
                                blurRadius: 4)
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
      ],
    );
  }

  void _showColorPicker(int index, _OverlayZone zone) {
    final colors =
        zone.tool == 'wall' ? _wallColors : _floorColors;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose ${zone.tool} color',
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: colors.map((c) {
                return GestureDetector(
                  onTap: () {
                    _updateZoneColor(index, c);
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade300)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _OverlayZone {
  final Offset position;
  final Color color;
  final double radius;
  final String tool;
  const _OverlayZone({
    required this.position,
    required this.color,
    required this.radius,
    required this.tool,
  });

  _OverlayZone copyWith({Color? color}) {
    return _OverlayZone(
      position: position,
      color: color ?? this.color,
      radius: radius,
      tool: tool,
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn(this.label, this.icon, this.active, this.onTap);
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.accent : Colors.white12,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, color: active ? Colors.white : Colors.white54, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.poppins(
                    color: active ? Colors.white : Colors.white54,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
