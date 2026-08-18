import 'dart:async';
import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import '../../../../../core/constants/app_colors.dart';
import '../../data/furniture_model_library.dart';

/// A furniture item placed in the AR scene, tracked for cleanup/removal.
class _PlacedItem {
  const _PlacedItem(this.item, this.node, this.anchor);
  final ArFurnitureItem item;
  final ARNode node;
  final ARAnchor anchor;
}

/// Real AR furniture viewer.
///
/// Renders the live camera feed with ARCore (SceneView/Filament on Android),
/// detects surfaces, and lets the user tap to place 3D furniture models.
/// Placed models can be dragged (pan), rotated (two-finger twist) and
/// removed. The catalog bar at the bottom lists the models for the design /
/// product this screen was opened from.
///
/// Before showing the AR view, the screen checks that Google Play Services
/// for AR (ARCore) is installed on the device — otherwise the user gets a
/// helpful install screen instead of a frozen camera image.
class ArViewerScreen extends StatefulWidget {
  const ArViewerScreen({super.key, this.items, this.title = 'AR Preview'});

  /// Furniture catalog to offer. When null or empty, the full library is shown.
  final List<ArFurnitureItem>? items;

  final String title;

  @override
  State<ArViewerScreen> createState() => _ArViewerScreenState();
}

class _ArViewerScreenState extends State<ArViewerScreen> {
  static const _channel =
      MethodChannel('com.example.interior_design_recommendation/arcore');
  static const _arCoreStoreUrl =
      'https://play.google.com/store/apps/details?id=com.google.ar.core';

  ARSessionManager? _session;
  ARObjectManager? _objects;
  ARAnchorManager? _anchors;

  late final List<ArFurnitureItem> _catalog =
      (widget.items == null || widget.items!.isEmpty)
          ? ArFurnitureLibrary.all
          : widget.items!;

  final List<_PlacedItem> _placed = [];
  ArFurnitureItem? _selected;
  String? _selectedNodeName;
  String? _arError;
  bool _planesFound = false;
  bool _busy = false;

  /// true while checking whether ARCore is installed on this device.
  bool _checking = true;
  bool _arCoreAvailable = false;

  /// Set when the AR view stays silent for too long (no planes, no error) —
  /// typical for devices blocked by Google's ARCore whitelist.
  bool _arUnresponsive = false;
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _selected = _catalog.first;
    _checkArCore();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _session?.dispose();
    super.dispose();
  }

  /// Starts a watchdog: if nothing AR-ish happens within 12 s, the device
  /// is likely blocked (unsupported hardware / whitelist) and the camera
  /// would just stay frozen — surface that instead of leaving the user
  /// staring at a static image.
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 12), () {
      if (!mounted) return;
      if (_planesFound || _arError != null || _placed.isNotEmpty) return;
      setState(() => _arUnresponsive = true);
    });
  }

  // ─── ARCore availability ───

  Future<void> _checkArCore() async {
    var available = false;
    try {
      available = await _channel.invokeMethod<bool>('isArCoreAvailable') ??
          false;
    } catch (_) {
      // Channel missing (e.g. non-Android) — fall through and let the AR
      // view itself surface any error.
      available = true;
    }
    if (!mounted) return;
    setState(() {
      _arCoreAvailable = available;
      _checking = false;
    });
  }

  Future<void> _openArCoreInstall() async {
    final uri = Uri.parse(_arCoreStoreUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _showMessage('Could not open the Play Store. Search for '
          '"Google Play Services for AR" manually.');
    }
  }

  // ─── AR lifecycle ───

  void _onArViewCreated(
    ARSessionManager session,
    ARObjectManager objects,
    ARAnchorManager anchors,
    ARLocationManager location,
  ) {
    _session = session;
    _objects = objects;
    _anchors = anchors;

    // Planes shown so the user can see detected surfaces; taps are handled by
    // us (onPlaneOrPointTap); pans/rotations use the built-in node gestures.
    _session!.onInitialize(
      showAnimatedGuide: false,
      showFeaturePoints: false,
      showPlanes: true,
      handleTaps: true,
      handlePans: true,
      handleRotation: true,
    );
    _objects!.onInitialize();

    _session!.onPlaneOrPointTap = _onPlaneOrPointTap;
    _session!.onPlaneDetected = (count) {
      if (mounted && count > 0 && !_planesFound) {
        setState(() {
          _planesFound = true;
          _arUnresponsive = false;
        });
      }
    };
    _session!.onError = (error) {
      if (mounted) setState(() => _arError = error);
    };
    _objects!.onNodeTap = _onNodeTap;

    _startWatchdog();
  }

  /// Places the selected furniture where the user tapped.
  /// Prefers a hit on a detected plane; falls back to a feature-point hit so
  /// furniture can still be placed while surface detection is warming up.
  Future<void> _onPlaneOrPointTap(List<ARHitTestResult> hits) async {
    if (_busy || _selected == null || hits.isEmpty) return;

    ARHitTestResult? hit;
    for (final h in hits) {
      if (h.type == ARHitTestResultType.plane) {
        hit = h;
        break;
      }
    }
    hit ??= hits.first;

    _busy = true;
    try {
      final anchor = ARPlaneAnchor(transformation: hit.worldTransform);
      final anchorOk = await _anchors?.addAnchor(anchor) ?? false;
      if (anchorOk != true) {
        _showMessage('Could not create anchor — keep moving your phone.');
        return;
      }

      final item = _selected!;
      final node = ARNode(
        type: NodeType.localGLTF2,
        uri: item.uri,
        scale: Vector3.all(item.widthMeters),
        position: Vector3(0.0, 0.0, 0.0),
        rotation: Vector4(1.0, 0.0, 0.0, 0.0),
      );
      final nodeOk =
          await _objects?.addNode(node, planeAnchor: anchor) ?? false;
      if (nodeOk == true) {
        setState(() => _placed.add(_PlacedItem(item, node, anchor)));
      } else {
        await _anchors?.removeAnchor(anchor);
        _showMessage('Could not load the 3D model for ${item.name}.');
      }
    } finally {
      _busy = false;
    }
  }

  void _onNodeTap(List<String> nodeNames) {
    if (nodeNames.isEmpty) return;
    setState(() => _selectedNodeName = nodeNames.first);
  }

  Future<void> _deleteNode(String name) async {
    _PlacedItem? entry;
    for (final p in _placed) {
      if (p.node.name == name) {
        entry = p;
        break;
      }
    }
    if (entry == null) return;
    await _objects?.removeNode(entry.node);
    await _anchors?.removeAnchor(entry.anchor);
    if (mounted) {
      setState(() {
        _placed.remove(entry);
        _selectedNodeName = null;
      });
    }
  }

  Future<void> _clearAll() async {
    for (final p in _placed) {
      await _objects?.removeNode(p.node);
      await _anchors?.removeAnchor(p.anchor);
    }
    if (mounted) {
      setState(() {
        _placed.clear();
        _selectedNodeName = null;
      });
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _checking
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent))
          : !_arCoreAvailable
              ? _buildArCoreMissing()
              : _buildArView(),
    );
  }

  /// Shown when Google Play Services for AR is not installed — without it the
  /// AR view would just show a frozen image, so we explain instead.
  Widget _buildArCoreMissing() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.view_in_ar,
                size: 72, color: AppColors.textHint),
            const SizedBox(height: 16),
            Text('AR is not available yet',
                style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 10),
            Text(
              'To place furniture in AR, your phone needs\n'
              '"Google Play Services for AR" (ARCore).\n'
              'It is free and takes a minute to install.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 14, color: Colors.white70, height: 1.6),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openArCoreInstall,
              icon: const Icon(Icons.get_app),
              label: const Text('Install from Play Store'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back',
                  style: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(height: 24),
            Text(
              'Note: some phones without Google services do not '
              'support ARCore. Try another Android device if the '
              'install fails.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The AR camera view — plane detection + tap handling.
        ARView(
          onARViewCreated: _onArViewCreated,
          planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
        ),

        // Top bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.title,
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text('${_placed.length} placed',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.white)),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined,
                      color: Colors.white),
                  tooltip: 'Clear all',
                  onPressed: _placed.isEmpty ? null : _clearAll,
                ),
              ],
            ),
          ),
        ),

        // Hint banner
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Center(
              child: Container(
                margin: const EdgeInsets.only(top: 56, left: 24, right: 24),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _hintText,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.white),
                ),
              ),
            ),
          ),
        ),

        // AR error overlay (e.g. session failed to start)
        if (_arError != null)
          Positioned(
            left: 24,
            right: 24,
            top: 120,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xF2262626),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.error),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.error, size: 32),
                  const SizedBox(height: 8),
                  Text('AR is not available on this device',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(
                    '$_arError',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _openArCoreInstall,
                    icon: const Icon(Icons.get_app, size: 18),
                    label: const Text('Install Google Play Services for AR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Unresponsive watchdog overlay — camera stays frozen when the
        // device is blocked by Google's ARCore whitelist.
        if (_arUnresponsive && _arError == null)
          Positioned(
            left: 24,
            right: 24,
            top: 120,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xF2262626),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.warning),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber,
                      color: AppColors.warning, size: 32),
                  const SizedBox(height: 8),
                  Text('The camera is not tracking',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(
                    'ARCore could not start on this device. Google only '
                    'supports AR on an official list of phone models — '
                    'this phone may not be on it.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      setState(() => _arUnresponsive = false);
                      _startWatchdog();
                    },
                    child: const Text('Try Again',
                        style: TextStyle(color: AppColors.accent)),
                  ),
                ],
              ),
            ),
          ),

        // Delete button for the tapped node
        if (_selectedNodeName != null)
          Positioned(
            right: 16,
            bottom: 132,
            child: FloatingActionButton.small(
              heroTag: 'ar-delete',
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              tooltip: 'Remove furniture',
              onPressed: () => _deleteNode(_selectedNodeName!),
              child: const Icon(Icons.delete_outline),
            ),
          ),

        // Furniture catalog
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Container(
              height: 108,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18)),
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _catalog.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final item = _catalog[i];
                  final selected = item.modelFile == _selected?.modelFile;
                  return GestureDetector(
                    onTap: () => setState(() => _selected = item),
                    child: Container(
                      width: 76,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.accent
                            : Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: selected
                            ? Border.all(
                                color: AppColors.accentLight, width: 2)
                            : Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(item.icon, size: 26, color: Colors.white),
                          const SizedBox(height: 3),
                          Text(
                            item.name,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                                color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  String get _hintText {
    if (_arError != null) return 'AR is unavailable — see message above.';
    if (!_planesFound) {
      return 'Move your phone slowly to detect surfaces, then tap to place '
          '${_selected?.name ?? 'furniture'}';
    }
    if (_placed.isEmpty) {
      return 'Tap a detected surface to place ${_selected?.name ?? 'furniture'}';
    }
    return 'Tap to place ${_selected?.name ?? 'furniture'} • '
        'Drag to move • Twist to rotate • Tap model to remove';
  }
}
