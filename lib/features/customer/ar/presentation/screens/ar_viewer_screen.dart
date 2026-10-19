import 'dart:async';
import 'dart:math' as math;

import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin_2/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin_2/datatypes/node_types.dart';
import 'package:ar_flutter_plugin_2/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin_2/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin_2/models/ar_anchor.dart';
import 'package:ar_flutter_plugin_2/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin_2/models/ar_node.dart';
import 'package:ar_flutter_plugin_2/models/ar_plane_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/user_errors.dart';
import '../../../../../models/product.dart';
import '../../../../../shared/widgets/catalog_picker_sheet.dart';
import '../../../../../shared/widgets/confirm_dialog.dart';
import '../../../../../services/model_generation/model_glb_resolver.dart';
import '../../data/ar_product_entry.dart';
import '../../data/furniture_model_library.dart';
import '../../data/glb_bounds.dart';
import '../../data/placement_policy.dart';
import '../../data/glb_file_saver.dart';
import '../../data/glb_generator.dart';
import '../../data/room_finishes.dart';

class _PlacedItem {
  const _PlacedItem(this.label, this.node, this.anchor);

  final String label;
  final ARNode node;
  final ARAnchor anchor;
}

class _PendingFinish {
  const _PendingFinish({
    required this.kindWord,
    required this.label,
    required this.nodeName,
    required this.filePath,
    required this.scaleMeters,
  });

  final String kindWord;

  final String label;

  final String nodeName;

  final String filePath;

  final double scaleMeters;
}

class _BarEntry {
  _BarEntry.library(this.item) : product = null;

  _BarEntry.product(this.product) : item = null;

  final ArFurnitureItem? item;

  ArProductEntry? product;

  bool get isProduct => product != null;

  String get name => isProduct ? product!.name : item!.name;

  bool get placeable => !isProduct || product!.isResolved;
}

class ArViewerScreen extends StatefulWidget {
  const ArViewerScreen({
    super.key,
    this.items,
    this.product,
    this.title = 'AR Preview',
  });

  final List<ArFurnitureItem>? items;

  final Product? product;

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

  late final List<_BarEntry> _entries = _buildCatalog();

  bool _productGenerating = false;

  DateTime? _generationStartedAt;

  Timer? _generationTicker;

  int _selectedIndex = 0;

  final List<_PlacedItem> _placed = [];
  String? _selectedNodeName;
  String? _arError;
  bool _planesFound = false;
  bool _busy = false;

  bool _checking = true;
  bool _arCoreAvailable = false;

  bool _arUnresponsive = false;
  Timer? _watchdog;

  bool _showPlacedChip = false;
  Timer? _chipTimer;

  String? _finishChipText;

  bool _sessionWasLive = false;

  // ─── Room mode (floor / wall finishes) ───

  bool _roomMode = false;

  FinishSelection _selection = const FinishSelection();

  FloorFinishType get _floorType => _selection.floorType;
  WallFinishType get _wallType => _selection.wallType;
  double get _floorSizeM => _selection.floorSizeM;
  int get _floorColorArgb => _selection.floorColorArgb;
  int get _wallColorArgb => _selection.wallColorArgb;

  _PendingFinish? _pendingFinish;

  bool _arming = false;

  DateTime? _lastNoFinishHintAt;

  DateTime? _lastPlacementHintAt;

  List<ARPlaneInfo> _livePlanes = const [];

  DateTime? _livePlanesAt;

  static const Duration _liveFloorFreshFor = Duration(seconds: 2);

  double? get _currentLiveFloorY {
    final at = _livePlanesAt;
    if (at == null || DateTime.now().difference(at) > _liveFloorFreshFor) {
      return null;
    }
    return ArPlacementPolicy.liveFloorYFromPlanes(_livePlanes);
  }

  static const double _furnitureBarHeight = 72;
  static const double _roomBarHeight = 248;
  double get _bottomBarHeight =>
      _roomMode ? _roomBarHeight : _furnitureBarHeight;

  double get _barOverlayInset => MediaQuery.viewPaddingOf(context).bottom;

  _BarEntry? get _selectedEntry => (_entries.isEmpty ||
          _selectedIndex >= _entries.length)
      ? null
      : _entries[_selectedIndex];

  List<_BarEntry> _buildCatalog() {
    final product = widget.product;
    if (product != null) {
      return [_BarEntry.product(ArProductEntry(product: product))];
    }
    final items = (widget.items == null || widget.items!.isEmpty)
        ? ArFurnitureLibrary.all
        : widget.items!;
    return [for (final item in items) _BarEntry.library(item)];
  }

  @override
  void initState() {
    super.initState();
    _resolveProductModel();
    _checkArCore();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _chipTimer?.cancel();
    _generationTicker?.cancel();
    _stopRotateHold();
    _session?.dispose();
    super.dispose();
  }

  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 12), () {
      if (!mounted) return;
      if (_planesFound || _arError != null || _placed.isNotEmpty) return;
      setState(() => _arUnresponsive = true);
    });
  }

  // ─── Product true-size mode ───

  Future<void> _resolveProductModel() async {
    final product = widget.product;
    if (product == null) return;

    final resolver = ModelGlbResolver();
    ResolvedGlb? resolved;
    String? failure;
    try {
      resolved = await resolver.resolveProductGlb(product);
    } on No3dAvailableException catch (e) {
      failure = e.reason == No3dAvailableException.generatingSentinel
          ? No3dAvailableException.generatingSentinel
          : userMessage(e,
              fallback: "This product's 3D view isn't available right now.");
    } catch (e) {
      failure = userMessage(e,
          fallback: "Couldn't load this product's 3D view. Check your "
              'connection and try again.');
    } finally {
      resolver.dispose();
    }
    if (!mounted) return;

    if (resolved != null) {
      final file = resolved.file;
      setState(() {
        _productGenerating = false;
        _generationTicker?.cancel();
        _generationTicker = null;
        for (final entry in _entries) {
          if (entry.isProduct) {
            entry.product =
                ArProductEntry(product: product, resolvedFile: file);
          }
        }
      });
      return;
    }

    if (failure == No3dAvailableException.generatingSentinel) {
      setState(() {
        _productGenerating = true;
        _generationStartedAt =
            product.ar3d?.submittedAt ?? DateTime.now();
      });
      _generationTicker?.cancel();
      _generationTicker =
          Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {});
      });
      return;
    }

    setState(() {
      _productGenerating = false;
      _generationTicker?.cancel();
      _generationTicker = null;
      for (final entry in _entries) {
        if (entry.isProduct) {
          entry.product = ArProductEntry(
              product: product, productError: failure);
        }
      }
    });
    _showMessage(
      failure ?? 'No 3D model is available for this product yet.',
      color: AppColors.warning,
      duration: const Duration(seconds: 6),
    );
  }

  String get _generationElapsed {
    final since = _generationStartedAt;
    if (since == null) return '';
    final total = DateTime.now().difference(since).inSeconds;
    if (total < 0) return '0s';
    if (total < 60) return '${total}s';
    return '${total ~/ 60}m ${(total % 60).toString().padLeft(2, '0')}s';
  }

  void _showProductChip() {
    _chipTimer?.cancel();
    if (!mounted) return;
    setState(() => _showPlacedChip = true);
    _chipTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _showPlacedChip = false);
    });
  }

  void _dismissProductChip() {
    _chipTimer?.cancel();
    if (mounted) setState(() => _showPlacedChip = false);
  }

  String? get _placedChipText {
    if (_finishChipText != null) return _finishChipText;
    final product = widget.product;
    if (product == null) return null;
    final dims = product.dimensions?.label ?? '';
    return dims.isEmpty ? product.name : '${product.name} · $dims';
  }

  // ─── ARCore availability ───

  Future<void> _checkArCore() async {
    var available = false;
    try {
      available = await _channel.invokeMethod<bool>('isArCoreAvailable') ??
          false;
    } catch (_) {
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
          _sessionWasLive = true;
          _arUnresponsive = false;
        });
      }
    };
    _session!.onPlanesUpdate = (planes) {
      if (!mounted) return;
      _livePlanes = planes;
      _livePlanesAt = DateTime.now();
    };
    _session!.onError = (error) {
      if (mounted) setState(() => _arError = error);
    };
    _objects!.onNodeTap = _onNodeTap;

    _startWatchdog();
  }

  Future<void> _onPlaneOrPointTap(List<ARHitTestResult> hits) async {
    if (_busy || hits.isEmpty) return;

    if (_arError != null) {
      _showMessage('AR session stopped — close and reopen the viewer.',
          color: AppColors.warning);
      return;
    }

    final pending = _pendingFinish;
    if (pending != null) {
      await _placePendingFinish(pending, hits);
      return;
    }
    if (_roomMode) {
      final now = DateTime.now();
      if (_lastNoFinishHintAt == null ||
          now.difference(_lastNoFinishHintAt!) > const Duration(seconds: 2)) {
        _lastNoFinishHintAt = now;
        _showMessage('Choose a finish and press Place floor or Place wall '
            'first.',
            color: AppColors.primaryLight,
            duration: const Duration(seconds: 2));
      }
      return;
    }

    final entry = _selectedEntry;
    if (entry == null) return;
    if (!entry.placeable) {
      final p = entry.product;
      if (p != null && p.hasError) {
        _showMessage(p.productError!, color: AppColors.warning,
            duration: const Duration(seconds: 6));
      } else if (p != null && _productGenerating) {
        _showMessage(
            'Generating 3D model… $_generationElapsed — this product '
            'places only once its model is ready.',
            color: AppColors.primaryLight);
      } else {
        _showMessage('The 3D model is still preparing — try again in a '
            'moment.',
            color: AppColors.primaryLight);
      }
      return;
    }

    _busy = true;
    try {
      final node = _buildNode(entry);
      final placement = entry.isProduct
          ? PlacementType.floor
          : entry.item!.placement;
      final placed = await _placeNodeAtTap(
        hits,
        node,
        entry.name,
        failureMessage: 'Could not load the 3D model for ${entry.name}.',
        requiredPlacement: placement,
      );
      if (placed == null) return;
      if (!mounted) return;
      setState(() {
        _placed.add(placed);
        _sessionWasLive = true;
        _finishChipText = null;
      });
      if (entry.isProduct) _showProductChip();
    } finally {
      _busy = false;
    }
  }

  static Matrix4 _anchorTransformFor(
      ARHitTestResult hit, PlacementType placement) {
    if (placement == PlacementType.wall) {
      return ArPlacementPolicy.wallAnchorTransform(hit);
    }
    return Matrix4.copy(hit.worldTransform);
  }

  Future<_PlacedItem?> _placeNodeAtTap(
    List<ARHitTestResult> hits,
    ARNode node,
    String label, {
    String failureMessage = 'Could not place the item.',
    PlacementType requiredPlacement = PlacementType.any,
  }) async {
    final ARHitTestResult? hit;
    switch (requiredPlacement) {
      case PlacementType.floor:
        final liveFloorY = _currentLiveFloorY;
        if (liveFloorY == null) {
          _showLiveFloorScanHint();
          return null;
        }
        hit = ArPlacementPolicy.chooseFloorHit(hits, liveFloorY: liveFloorY);
        break;
      case PlacementType.wall:
        hit = ArPlacementPolicy.chooseWallHit(hits);
        break;
      case PlacementType.any:
        hit = ArPlacementPolicy.chooseAnyHit(hits);
        break;
    }

    if (hit == null) {
      _showPlacementHint(requiredPlacement);
      return null;
    }

    final anchor = ARPlaneAnchor(
        transformation: _anchorTransformFor(hit, requiredPlacement));
    final anchorOk = await _anchors?.addAnchor(anchor) ?? false;
    if (anchorOk != true) {
      _showMessage('Could not create anchor — keep moving your phone.');
      return null;
    }
    final nodeOk = await _objects?.addNode(node, planeAnchor: anchor) ?? false;
    if (nodeOk != true) {
      await _anchors?.removeAnchor(anchor);
      _showMessage(failureMessage);
      return null;
    }
    return _PlacedItem(label, node, anchor);
  }

  void _showLiveFloorScanHint() {
    final now = DateTime.now();
    if (_lastPlacementHintAt != null &&
        now.difference(_lastPlacementHintAt!) <= const Duration(seconds: 2)) {
      return;
    }
    _lastPlacementHintAt = now;
    _showMessage('Move your phone slowly to scan the floor, then tap.',
        color: AppColors.warning, duration: const Duration(seconds: 2));
  }

  void _showPlacementHint(PlacementType requiredPlacement) {
    final now = DateTime.now();
    if (_lastPlacementHintAt != null &&
        now.difference(_lastPlacementHintAt!) <= const Duration(seconds: 2)) {
      return;
    }
    _lastPlacementHintAt = now;
    String text;
    if (requiredPlacement == PlacementType.floor) {
      text = 'Point your phone at the floor, then tap to place.';
    } else if (requiredPlacement == PlacementType.wall) {
      text = 'Point your phone at a wall, then tap to place.';
    } else {
      text = 'Point your phone at a floor or wall, then tap to place.';
    }
    _showMessage(text,
        color: AppColors.warning, duration: const Duration(seconds: 2));
  }

  ARNode _buildNode(_BarEntry entry) {
    final position = Vector3(0.0, 0.0, 0.0);
    final rotation = Vector4(1.0, 0.0, 0.0, 0.0);
    if (entry.isProduct) {
      final e = entry.product!;
      return ARNode(
        type: NodeType.fileSystemAppFolderGLB,
        uri: Uri.file(e.resolvedFile!.path).toString(),
        scale: Vector3.all(e.scaleToMeters),
        position: position,
        rotation: rotation,
        data: {'horizontalOnly': true},
      );
    }
    final item = entry.item!;
    return ARNode(
      type: NodeType.localGLTF2,
      uri: item.uri,
      scale: Vector3.all(item.widthMeters),
      position: position,
      rotation: rotation,
      data: {'horizontalOnly': item.placement == PlacementType.floor},
    );
  }

  // ─── Room mode: floor / wall finish placement ───

  // ── FinishSelection behavior methods (fix 24): every selection change
  //    OLD selection (fix 13). ────────────────────────────────────────────

  void _selectFloorType(FloorFinishType type) {
    if (type == _selection.floorType) return;
    setState(() {
      _selection = _selection.selectFloorType(type);
      _pendingFinish = null;
    });
  }

  void _selectFloorColor(int argb) {
    if (argb == _selection.floorColorArgb) return;
    setState(() {
      _selection = _selection.selectFloorColor(argb);
      _pendingFinish = null;
    });
  }

  void _selectFloorSize(double sizeM) {
    if (sizeM == _selection.floorSizeM) return;
    setState(() {
      _selection = _selection.selectFloorSize(sizeM);
      _pendingFinish = null;
    });
  }

  void _selectWallType(WallFinishType type) {
    if (type == _selection.wallType) return;
    setState(() {
      _selection = _selection.selectWallType(type);
      _pendingFinish = null;
    });
  }

  void _selectWallColor(int argb) {
    if (argb == _selection.wallColorArgb) return;
    setState(() {
      _selection = _selection.selectWallColor(argb);
      _pendingFinish = null;
    });
  }

  void _setRoomMode(bool room) {
    if (room == _roomMode) return;
    setState(() {
      _roomMode = room;
      if (!room) _pendingFinish = null;
    });
  }

  void _cancelPendingFinish() {
    if (_pendingFinish == null) return;
    setState(() => _pendingFinish = null);
  }

  Future<void> _armFloorPlacement() =>
      _prepareFinishPlacement(isFloor: true);

  Future<void> _armWallPlacement() => _prepareFinishPlacement(isFloor: false);

  Future<void> _prepareFinishPlacement({required bool isFloor}) async {
    if (_arming) return;
    final selection = _selection;
    setState(() => _arming = true);
    try {
      final bytes = isFloor
          ? generateFloorGlb(
              finish: FloorFinish(
                type: selection.floorType,
                colorArgb: selection.floorColorArgb,
                sizeM: selection.floorSizeM,
              ))
          : generateWallGlb(
              finish: WallFinish(
                type: selection.wallType,
                colorArgb: selection.wallColorArgb,
              ));
      final colorArgb =
          isFloor ? selection.floorColorArgb : selection.wallColorArgb;
      final typeName =
          (isFloor ? selection.floorType.name : selection.wallType.name)
              .toLowerCase();
      final fileName = isFloor
          ? 'finish_floor_${selection.floorType.name}_'
              '${_hexColor(colorArgb)}_'
              '${_sizeToken(selection.floorSizeM)}m.glb'
          : 'finish_wall_${selection.wallType.name}_'
              '${_hexColor(colorArgb)}.glb';
      final path = await saveGlbToAppDocuments(bytes, fileName: fileName);

      final scaleMeters = _maxExtentMeters(bytes) ??
          (isFloor ? selection.floorSizeM : RoomFinishCatalog.wallHeightM);

      final palette = isFloor
          ? RoomFinishCatalog.colorsForFloor(selection.floorType)
          : RoomFinishCatalog.colorsForWall(selection.wallType);
      final typeLabel = isFloor
          ? RoomFinishCatalog.floorLabel(selection.floorType)
          : RoomFinishCatalog.wallLabel(selection.wallType);
      final kindWord = isFloor ? 'floor' : 'wall';
      final colorName = RoomFinishCatalog.colorName(colorArgb, palette);
      final label = '$colorName $typeLabel '
          '${kindWord[0].toUpperCase()}${kindWord.substring(1)}';

      if (!mounted || !_roomMode || selection != _selection) return;
      setState(() {
        _pendingFinish = _PendingFinish(
          kindWord: kindWord,
          label: label,
          nodeName: '${kindWord}_${typeName.toLowerCase()}_'
              '${_hexColor(colorArgb)}',
          filePath: path,
          scaleMeters: scaleMeters,
        );
      });
    } catch (e) {
      _showMessage('Could not prepare the ${isFloor ? 'floor' : 'wall'} '
          'finish. Please try again.');
    } finally {
      if (mounted) setState(() => _arming = false);
    }
  }

  double? _maxExtentMeters(Uint8List bytes) {
    try {
      final b = GlbBounds.fromGlbBytes(bytes);
      final m = math.max(b.widthM, math.max(b.heightM, b.depthM));
      return m.isFinite && m > 0 ? m : null;
    } catch (_) {
      return null;
    }
  }

  static String _hexColor(int argb) => argb.toRadixString(16).padLeft(8, '0');

  static String _sizeToken(double meters) =>
      meters == meters.roundToDouble()
          ? '${meters.round()}'
          : meters.toStringAsFixed(1);

  Future<void> _placePendingFinish(
      _PendingFinish pending, List<ARHitTestResult> hits) async {
    _busy = true;
    try {
      final node = ARNode(
        type: NodeType.fileSystemAppFolderGLB,
        uri: Uri.file(pending.filePath).toString(),
        scale: Vector3.all(pending.scaleMeters),
        name: pending.nodeName,
        data: {'horizontalOnly': pending.kindWord == 'floor'},
      );
      final requiredPlacement = pending.kindWord == 'floor'
          ? PlacementType.floor
          : PlacementType.wall;
      final placed = await _placeNodeAtTap(
        hits,
        node,
        pending.label,
        failureMessage: 'Could not load the ${pending.kindWord} finish.',
        requiredPlacement: requiredPlacement,
      );
      if (placed == null) return;
      if (!mounted) return;
      setState(() {
        _placed.add(placed);
        _sessionWasLive = true;
        _finishChipText = 'Placed ${pending.label}';
      });
      _showProductChip();
    } finally {
      _busy = false;
    }
  }

  void _onNodeTap(List<String> nodeNames) {
    if (nodeNames.isEmpty) return;
    _stopRotateHold();
    setState(() {
      _selectedNodeName = nodeNames.first;
      _sessionWasLive = true;
    });
  }

  static const double _rotateStepRad = 15.0 * math.pi / 180.0;

  Future<void> _rotateSelected(double deltaYawRad) async {
    final selected = _selectedNodeName;
    if (selected == null) return;
    _PlacedItem? entry;
    for (final p in _placed) {
      if (p.node.name == selected || p.anchor.name == selected) {
        entry = p;
        break;
      }
    }
    if (entry == null) return;
    try {
      await _objects?.rotateNodeY(entry.node.name, deltaYawRad);
    } catch (_) {
    }
  }

  Timer? _rotateHoldTimer;

  static const double _rotateHoldStepRad = 0.75 * math.pi / 180.0;

  static const Duration _rotateHoldTick = Duration(milliseconds: 50);

  void _beginRotateHold(double dirSign) {
    _rotateHoldTimer?.cancel();
    _rotateHoldTimer = Timer.periodic(_rotateHoldTick, (_) {
      _rotateSelected(dirSign * _rotateHoldStepRad);
    });
  }

  void _stopRotateHold() {
    _rotateHoldTimer?.cancel();
    _rotateHoldTimer = null;
  }

  Future<void> _deleteNode(String name) async {
    _PlacedItem? entry;
    for (final p in _placed) {
      if (p.node.name == name || p.anchor.name == name) {
        entry = p;
        break;
      }
    }
    if (entry == null) return;
    await _deletePlaced(entry);
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

  void _showPlacedSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refreshSheet) {
          final items = _placed.toList();
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        Text(
                          'Placed items (${items.length})',
                          style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white70),
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Nothing placed yet.',
                              style: GoogleFonts.poppins(
                                  fontSize: 13, color: Colors.white54),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final item = items[i];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.chair_outlined,
                                    color: Colors.white70, size: 20),
                                title: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: Colors.white),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: AppColors.error),
                                  tooltip: 'Remove ${item.label}',
                                  onPressed: () => _removePlaced(
                                      item, sheetContext, refreshSheet),
                                ),
                              );
                            },
                          ),
                  ),
                  if (items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: TextButton.icon(
                        onPressed: () async {
                          await _clearAll();
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                        },
                        icon: const Icon(Icons.delete_sweep_outlined,
                            size: 18),
                        label: Text(
                          'Remove all (${items.length})',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _removePlaced(
      _PlacedItem item, BuildContext sheetContext, StateSetter refreshSheet) {
    return _deletePlaced(item).then((_) {
      if (sheetContext.mounted) refreshSheet(() {});
    });
  }

  Future<void> _deletePlaced(_PlacedItem item) async {
    await _objects?.removeNode(item.node);
    await _anchors?.removeAnchor(item.anchor);
    if (!mounted) return;
    setState(() {
      _placed.remove(item);
      if (_selectedNodeName != null &&
          (item.node.name == _selectedNodeName ||
              item.anchor.name == _selectedNodeName)) {
        _selectedNodeName = null;
        _stopRotateHold();
      }
    });
  }

  void _showMessage(
    String message, {
    Color color = AppColors.error,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: duration,
      ));
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _checking
          ? const ColoredBox(
              color: Colors.black,
              child: Center(
                  child:
                      CircularProgressIndicator(color: AppColors.accent)),
            )
          : !_arCoreAvailable
              ? ColoredBox(
                  color: Colors.black, child: _buildArCoreMissing())
              : _buildArView(),
    );
  }

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
              'Note: Honor/Huawei devices may not support ARCore '
              'even after installation. Try another Android device '
              'if AR does not work.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArErrorOverlay() {
    final wasLive = _sessionWasLive;
    return Positioned(
      left: 24,
      right: 24,
      top: 120,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xF2262626),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: wasLive ? AppColors.warning : AppColors.error),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              wasLive ? Icons.pause_circle_outline : Icons.error_outline,
              color: wasLive ? AppColors.warning : AppColors.error,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              wasLive ? 'AR session stopped' : 'AR is not available',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              wasLive
                  ? '$_arError\n\nThe session ran and then stopped — '
                      'close the viewer and reopen it for a fresh session.'
                  : '$_arError',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 11, color: Colors.white70, height: 1.5),
            ),
            const SizedBox(height: 10),
            if (wasLive)
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Close'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
              )
            else
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
    );
  }

  Widget _buildArView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        ARView(
          onARViewCreated: _onArViewCreated,
          planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
        ),

        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: _placed.isEmpty
                        ? 'Nothing placed yet'
                        : '${_placed.length} '
                            '${_placed.length == 1 ? 'item' : 'items'} placed',
                    child: InkWell(
                      onTap: _placed.isEmpty ? null : _showPlacedSheet,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${_placed.length} placed',
                                style: GoogleFonts.poppins(
                                    fontSize: 12, color: Colors.white)),
                            if (_placed.isNotEmpty) ...[
                              const SizedBox(width: 2),
                              const Icon(Icons.expand_less,
                                  size: 14, color: Colors.white70),
                            ],
                          ],
                        ),
                      ),
                    ),
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
        ),

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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.white),
                ),
              ),
            ),
          ),
        ),

        if (_arError != null) _buildArErrorOverlay(),

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
                  Text('AR is not working on this device',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(
                    'Some Honor/Huawei devices do not fully support '
                    'Google ARCore. The camera may show but plane '
                    'detection does not work.\n\n'
                    'You can still browse and save furniture designs.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() => _arUnresponsive = false);
                          _startWatchdog();
                        },
                        child: const Text('Try Again',
                            style: TextStyle(color: AppColors.accent)),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Close'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        if (_selectedNodeName != null)
          Positioned(
            right: 16,
            bottom: _bottomBarHeight + _barOverlayInset + 24,
            child: FloatingActionButton.small(
              heroTag: 'ar-delete',
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              tooltip: 'Remove item',
              onPressed: () => _deleteNode(_selectedNodeName!),
              child: const Icon(Icons.delete_outline),
            ),
          ),

        if (_selectedNodeName != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: _bottomBarHeight + _barOverlayInset + 56,
            child: Center(child: _buildRotateControls()),
          ),

        if (_showPlacedChip && _placedChipText != null)
          Positioned(
            left: 16,
            right: 88,
            bottom: _bottomBarHeight +
                _barOverlayInset +
                (_selectedNodeName != null ? 108 : 46),
            child: Center(
              child: GestureDetector(
                onTap: _dismissProductChip,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xE6262626),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.accentLight),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.straighten,
                          size: 14, color: AppColors.accentLight),
                      const SizedBox(width: 6),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _placedChipText!,
                            maxLines: 1,
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.close,
                          size: 12, color: Colors.white54),
                    ],
                  ),
                ),
              ),
            ),
          ),

        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child:
                _roomMode ? _buildRoomBar() : _buildFurnitureBar(),
          ),
        ),

        Positioned(
          left: 0,
          right: 0,
          bottom: _bottomBarHeight + _barOverlayInset + 8,
          child: Center(child: _buildModeSwitcher()),
        ),
      ],
    );
  }

  // ─── Bottom bar (Furniture mode) ───

  BoxDecoration get _barDecoration => BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      );

  Widget _buildFurnitureBar() {
    final selected = _selectedEntry;
    return Container(
      height: _furnitureBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _barDecoration,
      child: Row(
        children: [
          Expanded(child: _buildSelectionChip(selected)),
          const SizedBox(width: 8),
          _buildOpenPickerButton(),
        ],
      ),
    );
  }

  Widget _buildSelectionChip(_BarEntry? entry) {
    if (entry == null) {
      return Text(
        'No furniture to place',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
      );
    }
    final item = entry.item;
    final product = entry.product;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _entries.length > 1 ? _openFurniturePicker : null,
      child: Container(
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accentLight, width: 1.5),
        ),
        child: Row(
          children: [
            if (item != null) ...[
              Icon(item.icon, size: 22, color: Colors.white),
            ] else if (product != null) ...[
              Icon(
                product.hasError
                    ? Icons.error_outline
                    : product.isResolved
                        ? Icons.auto_awesome
                        : Icons.hourglass_top,
                size: 20,
                color: product.hasError
                    ? AppColors.warning
                    : Colors.white,
              ),
            ],
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                  if (product != null)
                    Text(
                      product.hasError
                          ? 'Tap the picker for details'
                          : product.isResolved
                              ? product.dimsLabel
                              : 'Preparing 3D…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 9, color: Colors.white70),
                    ),
                ],
              ),
            ),
            if (_entries.length > 1) ...[
              const SizedBox(width: 6),
              const Icon(Icons.expand_less, size: 18, color: Colors.white70),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOpenPickerButton() {
    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _entries.isEmpty ? null : _openFurniturePicker,
        child: SizedBox(
          height: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.grid_view, size: 18, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  _entries.length > 1 ? 'Catalog' : 'Details',
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openFurniturePicker() async {
    if (_entries.isEmpty) return;
    final picked = await showCatalogPickerSheet<int>(
      context: context,
      title: widget.product != null ? 'This product' : 'Furniture catalog',
      subtitle: widget.product != null
          ? null
          : 'Tap an item to select it, then tap the floor to place',
      items: [for (var i = 0; i < _entries.length; i++) i],
      labelOf: (i) => _entries[i].name,
      tileBuilder: (_, i) => _buildPickerTile(_entries[i]),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedIndex = picked);
    final entry = _entries[picked];
    final product = entry.product;
    if (product != null && product.hasError && product.productError != null) {
      _showMessage(product.productError!,
          color: AppColors.warning, duration: const Duration(seconds: 6));
    }
  }

  Widget _buildPickerTile(_BarEntry entry) {
    final item = entry.item;
    if (item != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, size: 22, color: AppColors.accent),
          ),
        ],
      );
    }
    final product = entry.product!;
    if (!product.isResolved) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (product.hasError)
            const Icon(Icons.error_outline, size: 28, color: AppColors.warning)
          else
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(height: 6),
          Text(
            product.hasError ? 'Unavailable' : 'Generating…',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: product.hasError
                    ? AppColors.warning
                    : AppColors.textSecondary),
          ),
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: AppColors.accent),
            const SizedBox(width: 4),
            _SourceBadge(text: product.badgeText),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          product.dimsLabel,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
              fontSize: 9, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildModeSwitcher() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeSegment(
              'Furniture', active: !_roomMode, onTap: () => _setRoomMode(false)),
          const SizedBox(width: 2),
          _buildModeSegment(
              'Room', active: _roomMode, onTap: () => _setRoomMode(true)),
        ],
      ),
    );
  }

  Widget _buildModeSegment(String label,
      {required bool active, required VoidCallback onTap}) {
    return Semantics(
      button: true,
      selected: active,
      label: '$label mode',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 32,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Rotation controls (above the bottom panel) ───

  Widget _buildRotateControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xE6262626),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRotateButton(
            icon: Icons.rotate_left,
            tooltip: 'Rotate left — tap for 15°, hold to turn slowly',
            dirSign: 1.0,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Turn',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
          ),
          _buildRotateButton(
            icon: Icons.rotate_right,
            tooltip: 'Rotate right — tap for 15°, hold to turn slowly',
            dirSign: -1.0,
          ),
        ],
      ),
    );
  }

  Widget _buildRotateButton({
    required IconData icon,
    required String tooltip,
    required double dirSign,
  }) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _rotateSelected(dirSign * _rotateStepRad),
          onLongPressStart: (_) => _beginRotateHold(dirSign),
          onLongPressEnd: (_) => _stopRotateHold(),
          onLongPressCancel: _stopRotateHold,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }

  // ─── Bottom bar (Room mode) — floor / wall finishes ───

  Widget _buildRoomBar() {
    return Container(
      height: _roomBarHeight,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: _barDecoration,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFloorTypeRow(),
            const SizedBox(height: 2),
            _buildFloorColorRow(),
            _buildTypeCaption(
              '${RoomFinishCatalog.floorLabel(_floorType)} — '
              '${RoomFinishCatalog.floorDescription(_floorType)}',
            ),
            const SizedBox(height: 2),
            _buildFloorSizeRow(),
            const SizedBox(height: 4),
            _buildWallTypeRow(),
            const SizedBox(height: 2),
            _buildWallColorRow(),
            _buildTypeCaption(
              '${RoomFinishCatalog.wallLabel(_wallType)} — '
              '${RoomFinishCatalog.wallDescription(_wallType)}',
            ),
            const SizedBox(height: 2),
            _buildFinishHintRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeCaption(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 42, top: 2),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.poppins(
          fontSize: 9,
          fontStyle: FontStyle.italic,
          color: Colors.white54,
        ),
      ),
    );
  }

  Widget _buildFloorTypeRow() {
    return _buildFinishRow(
      label: 'Floor',
      children: [
        for (final type in RoomFinishCatalog.floorTypes.keys) ...[
          _buildChoiceChip(
            label: RoomFinishCatalog.floorLabel(type),
            selected: type == _floorType,
            onTap: () => _selectFloorType(type),
          ),
          const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _buildFloorColorRow() {
    final colors = RoomFinishCatalog.colorsForFloor(_floorType);
    return _buildFinishRow(
      label: 'Colour',
      children: [
        for (final c in colors) ...[
          _buildSwatch(
            c,
            name: RoomFinishCatalog.colorName(c.argb, colors),
            selected: c.argb == _floorColorArgb,
            onTap: () => _selectFloorColor(c.argb),
          ),
          const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _buildFloorSizeRow() {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          const SizedBox(width: 42),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final size
                      in RoomFinishCatalog.floorSizeOptionsM) ...[
                    _buildChoiceChip(
                      label: size < 0 ? 'Custom' : '${size.toStringAsFixed(0)} m',
                      selected: size < 0
                          ? !_isPresetFloorSize(_floorSizeM)
                          : size == _floorSizeM,
                      onTap: () => size < 0
                          ? _showCustomFloorSizeDialog()
                          : _selectFloorSize(size),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          _buildPlaceAction(
            label: 'Place floor',
            icon: Icons.grid_view,
            busy: _arming,
            onTap: _armFloorPlacement,
          ),
        ],
      ),
    );
  }

  bool _isPresetFloorSize(double size) {
    for (final preset in RoomFinishCatalog.floorSizeOptionsM) {
      if (preset > 0 && (preset - size).abs() < 0.01) return true;
    }
    return false;
  }

  Future<void> _showCustomFloorSizeDialog() async {
    final controller = TextEditingController(
      text: _isPresetFloorSize(_floorSizeM) ? '' : _floorSizeM.toStringAsFixed(1),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom Floor Size'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Size in meters',
            hintText: 'e.g. 2.5',
            suffixText: 'm',
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ConfirmDialogActions(
            confirmLabel: 'Apply',
            onCancel: () => Navigator.pop(ctx),
            onConfirm: () {
              final value = double.tryParse(controller.text);
              if (value != null && value > 0 && value <= 20) {
                Navigator.pop(ctx, value);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Enter a size between 0.1 and 20 meters'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      _selectFloorSize(result);
    }
  }

  Widget _buildWallTypeRow() {
    return _buildFinishRow(
      label: 'Wall',
      children: [
        for (final type in RoomFinishCatalog.wallTypes.keys) ...[
          _buildChoiceChip(
            label: RoomFinishCatalog.wallLabel(type),
            selected: type == _wallType,
            onTap: () => _selectWallType(type),
          ),
          const SizedBox(width: 6),
        ],
      ],
      trailing: _buildPlaceAction(
        label: 'Place wall',
        icon: Icons.view_agenda_outlined,
        busy: _arming,
        onTap: _armWallPlacement,
      ),
    );
  }

  Widget _buildWallColorRow() {
    final colors = RoomFinishCatalog.colorsForWall(_wallType);
    return _buildFinishRow(
      label: 'Colour',
      children: [
        for (final c in colors) ...[
          _buildSwatch(
            c,
            name: RoomFinishCatalog.colorName(c.argb, colors),
            selected: c.argb == _wallColorArgb,
            onTap: () => _selectWallColor(c.argb),
          ),
          const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _buildFinishRow({
    required String label,
    required List<Widget> children,
    Widget? trailing,
  }) {
    final style = GoogleFonts.poppins(
      fontSize: 9,
      fontWeight: FontWeight.w600,
      color: Colors.white54,
      letterSpacing: 0.4,
    );
    final content = SizedBox(
      height: 32,
      child: Row(
        children: [
          SizedBox(width: 36, child: Text(label, style: style)),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: children,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 6), trailing],
        ],
      ),
    );
    return content;
  }

  Widget _buildChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 32,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent
                : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.accentLight : Colors.white24,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwatch(
    FinishColor color, {
    required String name,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final circle = Semantics(
      button: true,
      selected: selected,
      label: '$name color',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.accentLight : Colors.white38,
              width: selected ? 2 : 1,
            ),
          ),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color(color.argb),
              border: Border.all(color: Colors.black26),
            ),
          ),
        ),
      ),
    );
    return Tooltip(message: name, child: circle);
  }

  Widget _buildPlaceAction({
    required String label,
    required IconData icon,
    required bool busy,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      enabled: !busy,
      label: busy ? '$label — generating 3D model' : label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: busy ? null : onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildFinishHintRow() {
    final pending = _pendingFinish;
    final hintStyle = GoogleFonts.poppins(
      fontSize: 9,
      color: Colors.white60,
      height: 1.35,
    );
    if (pending == null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 30),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          'Choose a finish and press Place floor or Place wall, then tap a '
          'detected surface. Tap a placed item to remove it.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: hintStyle,
        ),
      );
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.touch_app,
              size: 13, color: AppColors.accentLight),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${pending.label} ready — tap a surface to place it',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Semantics(
            button: true,
            label: 'Done — cancel placing ${pending.kindWord}',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _cancelPendingFinish,
              child: Container(
                height: 32,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Done',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(Icons.close, size: 11, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _hintText {
    if (_arError != null) return 'AR is unavailable — see message above.';
    if (_roomMode) {
      final pending = _pendingFinish;
      if (pending != null) {
        return !_planesFound
            ? 'Move your phone slowly to detect surfaces, then tap to '
                'place the ${pending.kindWord}.'
            : 'Tap where you want the ${pending.kindWord} — '
                '${pending.label}. Tap again to add more; Done (✕) stops.';
      }
      if (!_planesFound) {
        return 'Move your phone slowly to detect surfaces, then choose a '
            'finish and press Place floor or Place wall.';
      }
      return _placed.isEmpty
          ? 'Choose a finish and press Place floor or Place wall, then '
              'tap a detected surface.'
          : 'Choose a finish and press Place to add more • '
              'Tap a placed item to remove it';
    }
    final entry = _selectedEntry;
    final name = entry?.name ?? 'furniture';
    if (entry != null && !entry.placeable) {
      final p = entry.product;
      if (p != null && p.hasError) {
        return 'This product’s 3D model is not ready — tap its slot for '
            'details.';
      }
      if (p != null && _productGenerating) {
        return 'Generating 3D model… $_generationElapsed — this product '
            'places only once its model is ready.';
      }
      return 'Preparing the true-size 3D model — keep moving your phone, '
          'then tap to place once it is ready';
    }
    final placement = entry?.isProduct == true
        ? PlacementType.floor
        : entry?.item?.placement ?? PlacementType.floor;
    final surfaceHint = placement == PlacementType.wall
        ? 'a wall'
        : 'the floor';
    if (!_planesFound) {
      return 'Move your phone slowly to detect surfaces, then tap '
          '$surfaceHint to place $name';
    }
    if (_placed.isEmpty) {
      return 'Tap $surfaceHint to place $name';
    }
    return 'Tap to place $name • Drag to move • '
        'Tap a model, then use the ↺ ↻ buttons above to turn it';
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ai = text == 'AI';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: ai ? AppColors.secondaryAccent : AppColors.primaryLight,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: GoogleFonts.poppins(
            fontSize: 7,
            fontWeight: FontWeight.w700,
            color: Colors.white),
      ),
    );
  }
}
