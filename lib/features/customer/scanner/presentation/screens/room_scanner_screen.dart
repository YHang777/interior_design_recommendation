import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/native_scene_guard.dart';
import '../../../../../core/utils/user_errors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../models/product.dart';
import '../../../../../models/room_design.dart';
import '../../../../../services/material_scan_service.dart';
import '../../../../../shared/widgets/app_feedback.dart';
import '../../../../../shared/widgets/catalog_picker_sheet.dart';
import '../../../../../shared/widgets/filter_chip_bar.dart';
import '../../../../../shared/widgets/float_button.dart';
import '../../../ar/data/furniture_model_library.dart';
import '../../../ar/data/glb_generator.dart' show FloorFinish, WallFinish;
import '../../../ar/data/room_finishes.dart';
import '../../../ar/presentation/ar_viewer_args.dart';
import '../../../homeowner/presentation/providers/design_providers.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../walkthrough/presentation/plan_preview_3d.dart';
import '../../data/camera_rig.dart';
import '../../data/furniture_catalog.dart';
import '../../data/plan_scene_math.dart';
import '../../data/planner_scene_bridge.dart';
import '../../data/room_fit.dart';
import '../../data/room_shell.dart'
    show ShellGeometry, cutawaySignature, shellRing;
import '../scene3d_view.dart';

class RoomScannerScreen extends ConsumerStatefulWidget {
  const RoomScannerScreen({
    super.key,
    this.existingDesign,
    this.materialScanService,
  });
  final RoomDesign? existingDesign;
  final MaterialScanService? materialScanService;

  @override
  ConsumerState<RoomScannerScreen> createState() => _RoomScannerScreenState();
}

enum _Stage { init, scanning, plan }

enum _SceneDrag { none, move, orbit, pinch }

typedef _Cat = RoomCatalogItem;

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
  // Design identity — separate from widget.existingDesign so a walkthrough
  // round-trip can adopt a plan that was saved while walking (the widget
  // arg is final, so a create would otherwise mint a second design id).
  String? _designId;
  String? _designName;
  DateTime? _designCreatedAt;

  late List<FurniturePlacement> _furniture;
  double _roomW = 400;
  double _roomH = 500;
  int _selectedIdx = -1;
  bool _isEditingDimensions = false;
  final _widthCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  // RoomFinishCatalog names + palette argbs; the AI material scan writes
  // these and every design surface (save, snapshot, AR, walkthrough) reads
  // them back.
  String? _floorFinishType;
  int? _floorFinishColor;
  String? _wallFinishType;
  int? _wallFinishColor;
  Future<void>? _captureInFlight;

  late final MaterialScanService _materialScan =
      widget.materialScanService ?? MaterialScanService();

  @visibleForTesting
  List<Offset> get debugWalls => List.of(_walls);

  @visibleForTesting
  List<FurniturePlacement> get debugFurniture => List.of(_furniture);

  @visibleForTesting
  double get debugCameraDistanceM => _rig.distanceM;

  @visibleForTesting
  void debugAddFromCatalog(RoomCatalogItem item) => _addFromCatalog(item);

  @visibleForTesting
  int debugAutoPlace(List<String> labels) {
    _found
      ..clear()
      ..addAll([for (final l in labels) _Found(label: l, confidence: 0.9)]);
    return _autoPlaceFound();
  }

  final List<Offset> _walls = [];
  // Interior wall chains drawn in wall mode; the room itself never changes.
  final List<List<Offset>> _interior = [];
  bool _chainOpen = false;
  final ValueNotifier<int> _wallsRev = ValueNotifier(0);
  bool _wallMode = false;
  bool _sceneExpanded = false;

  // Timestamp + counter: two adds in the same microsecond used to share an
  // id, and the overlap check skips a piece's own id.
  int _pieceSeq = 0;
  String _nextPieceId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_pieceSeq++}';
  String _catalogCategory = 'All';

  // ── native 3D scene ──
  final PlannerSceneBridge _bridge = PlannerSceneBridge();
  late final OrbitRig _rig;
  final ValueNotifier<int> _sceneRev = ValueNotifier(0);
  final GlobalKey _sceneKey = GlobalKey();
  // Bumped after AR / walk-through: their camera surface can leave the
  // planner's platform view black on return, so it is rebuilt fresh (the
  // bridge re-pushes the whole room on the new view id).
  int _sceneGen = 0;

  Future<void> _rebuildSceneWhenSettled() async {
    await NativeSceneGuard.settled();
    if (mounted) setState(() => _sceneGen++);
  }
  Size _viewport = Size.zero;
  Timer? _shellThrottle;
  Timer? _furnitureThrottle;
  String? _lastCutSig;

  _SceneDrag _drag = _SceneDrag.none;
  String? _moveId;
  Offset _grabDelta = Offset.zero;
  double _lastPinch = 1;

  void _touchWalls() {
    _wallsRev.value++;
    _shellThrottle?.cancel();
    _shellThrottle = Timer(const Duration(milliseconds: 200), _syncShell);
  }

  // Orbiting the dollhouse camera can drop or raise walls; only a mask
  // crossing regenerates the shell, free camera motion inside a mask is free.
  void _touchCutaway() {
    final shell = ShellGeometry(
        ringCm: shellRing(wallsCm: _walls, roomWCm: _roomW, roomHCm: _roomH));
    final sig = cutawaySignature(shell, _cutawayCameraCm);
    if (sig == _lastCutSig) return;
    _touchWalls();
  }

  Offset get _cutawayCameraCm =>
      Offset(_rig.pose.eyeX * 100, _rig.pose.eyeZ * 100);

  void _touchFurniture() {
    _furnitureThrottle?.cancel();
    // Live drag previews must follow the finger exactly — clamping belongs
    // to the commit, not the mid-drag mirror.
    _furnitureThrottle = Timer(
        const Duration(milliseconds: 120), () => _bridge.syncFurniture(_furniture));
  }

  void _syncShell() {
    final cam = _cutawayCameraCm;
    final shell = ShellGeometry(
        ringCm: shellRing(wallsCm: _walls, roomWCm: _roomW, roomHCm: _roomH));
    _lastCutSig = cutawaySignature(shell, cam);
    _bridge.syncShell(
        wallsCm: _walls,
        roomWCm: _roomW,
        roomHCm: _roomH,
        floor: _floorFinish,
        wall: _wallFinish,
        cutawayCameraCm: cam,
        interiorWallsCm: _interior);
  }

  void _syncFurnitureNow() {
    _furniture = clampAllPlacements(_furniture,
        roomW: _roomW, roomH: _roomH, walls: _walls, interiorWalls: _interior);
    _bridge.syncFurniture(_furniture);
  }

  FloorFinish get _floorFinish {
    final sel = finishSelectionFrom(_snapshotDesign());
    return FloorFinish(
      type: sel.floorType,
      colorArgb: sel.floorColorArgb,
      sizeM: sel.floorSizeM,
    );
  }

  WallFinish get _wallFinish {
    final sel = finishSelectionFrom(_snapshotDesign());
    return WallFinish(type: sel.wallType, colorArgb: sel.wallColorArgb);
  }

  DateTime? _lastProcessedAt;
  bool _processingFrame = false;
  DateTime? _scanDeadline;
  final int _scanDurationSec = 15;

  static const _labels = {
    'sofa', 'couch', 'loveseat', 'sectional', 'settee',
    'chair', 'armchair', 'recliner', 'ottoman', 'stool', 'bench',
    'table', 'coffee table', 'dining table', 'desk',
    'bed', 'bed frame', 'mattress', 'bunk bed',
    'cabinet', 'wardrobe', 'closet', 'dresser', 'nightstand',
    'sideboard', 'cupboard', 'bookshelf', 'shelf', 'bookcase',
    'lamp', 'floor lamp', 'table lamp', 'light', 'chandelier',
    'rug', 'carpet', 'curtain', 'plant', 'flower', 'vase', 'painting',
    'picture frame', 'wall art', 'mirror', 'television', 'tv', 'monitor',
    'refrigerator', 'oven', 'microwave', 'pillow', 'cushion',
    'floor', 'wood', 'hardwood', 'tile',
  };

  // ML Kit names that have no exact catalog entry — mapped to the
  // closest catalog item before matching.
  static const _labelAliases = <String, String>{
    'couch': 'Sofa',
    'loveseat': 'Sofa',
    'sectional': 'Sofa',
    'settee': 'Sofa',
    'recliner': 'Armchair',
    'ottoman': 'Armchair',
    'stool': 'Armchair',
    'bench': 'Armchair',
    'carpet': 'Rug',
    'area rug': 'Rug',
    'bookcase': 'Bookshelf',
    'dresser': 'Cabinet',
    'chest of drawers': 'Cabinet',
    'nightstand': 'Cabinet',
    'night stand': 'Cabinet',
    'sideboard': 'Cabinet',
    'cupboard': 'Cabinet',
    'wardrobe': 'Cabinet',
    'closet': 'Cabinet',
    'mattress': 'Bed',
    'television': 'TV Stand',
    'tv': 'TV Stand',
    'monitor': 'TV Stand',
    'chandelier': 'Floor Lamp',
    'light': 'Floor Lamp',
    'table lamp': 'Floor Lamp',
    'floor lamp': 'Floor Lamp',
    'ceiling light': 'Floor Lamp',
  };

  // ─── Furniture catalog with image assets ───
  // Shared with the walkthrough so both pickers never drift apart.
  static const _catalog = roomCatalog;

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
    _walls.addAll(widget.existingDesign?.walls ?? const []);
    _interior.addAll([
      for (final c in widget.existingDesign?.interiorWalls ?? const <List<Offset>>[])
        List<Offset>.of(c),
    ]);
    if (widget.existingDesign != null) {
      _roomW = widget.existingDesign!.widthCm;
      _roomH = widget.existingDesign!.heightCm;
      _roomType = widget.existingDesign!.roomType;
      _designId = widget.existingDesign!.id;
      _designName = widget.existingDesign!.name;
      _designCreatedAt = widget.existingDesign!.createdAt;
      _floorFinishType = widget.existingDesign!.floorFinishType;
      _floorFinishColor = widget.existingDesign!.floorFinishColor;
      _wallFinishType = widget.existingDesign!.wallFinishType;
      _wallFinishColor = widget.existingDesign!.wallFinishColor;
      _found.addAll(widget.existingDesign!.detectedItems
          .map((l) => _Found(label: l, confidence: 0.9)));
      _stage = _Stage.plan;
    } else {
      _stage = _Stage.plan;
    }

    // Render clamp: legacy/round-tripped placements settle instead of
    // drawing inside a wall.
    _furniture = clampAllPlacements(_furniture,
        roomW: _roomW, roomH: _roomH, walls: _walls, interiorWalls: _interior);
    _rig = OrbitRig.frameRoom(roomWCm: _roomW, roomHCm: _roomH);
    _reframeRig();

    // Syncs issued before the platform view exists are dropped — re-push the
    // whole scene the moment it binds.
    _bridge.onBound = (_) {
      _syncShell();
      _syncFurnitureNow();
      _pushCamera();
    };

    ref.listenManual(
      pendingChatPlacementsProvider,
      (prev, next) {
        if (next.isEmpty) return;
        final placements =
            ref.read(pendingChatPlacementsProvider.notifier).drain();
        _applyChatPlacements(placements);
      },
      fireImmediately: true,
    );
  }

  void _applyChatPlacements(List<FurniturePlacement> placements) {
    if (placements.isEmpty) return;
    var slot = _furniture.length;
    final added = <FurniturePlacement>[];
    final tooBig = <String>[];
    for (final p in placements) {
      final maxX = max(1.0, _roomW - p.width);
      final maxY = max(1.0, _roomH - p.height);
      final x = (20.0 + (slot % 3) * 110.0)
          .clamp(5.0, max(5.0, maxX - 5))
          .toDouble();
      final y = (40.0 + ((slot ~/ 3) % 3) * 130.0)
          .clamp(5.0, max(5.0, maxY - 5))
          .toDouble();
      // Wall- and piece-aware: settle on clear floor; a piece bigger than
      // the room is reported instead of being parked inside a wall.
      final fitted = fitInRoom(p.copyWith(x: x, y: y),
          roomW: _roomW,
          roomH: _roomH,
          walls: _walls,
          interiorWalls: _interior,
          others: [..._furniture, ...added]);
      if (fitted == null) {
        tooBig.add(p.name);
      } else {
        added.add(fitted);
      }
      slot++;
    }
    if (!mounted) return;
    setState(() => _furniture = [..._furniture, ...added]);
    _bridge.syncFurniture(_furniture);
    if (tooBig.isNotEmpty) {
      showAppSnackbar(
          context, '${tooBig.join(', ')} is too big for this room.',
          isError: true);
    }
  }

  Future<void> _setupCam() async {
    // A scan-end capture owns the previous controller until it settles;
    // opening a second one over it fails on Android.
    await _captureInFlight;
    await _releaseCam();
    CameraController? cam;
    try {
      _cameras = await availableCameras();
      if (_cameras!.isEmpty) return;
      cam = CameraController(
        _cameras!.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
            orElse: () => _cameras!.first),
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await cam.initialize();
      if (!mounted) {
        await cam.dispose();
        return;
      }
      _cam = cam;
      setState(() {});
    } catch (_) {
      try {
        await cam?.dispose();
      } catch (_) {}
      await _releaseCam();
    }
  }

  Future<void> _releaseCam() async {
    final cam = _cam;
    _cam = null;
    if (cam == null) return;
    try {
      await cam.stopImageStream();
    } catch (_) {}
    try {
      await cam.dispose();
    } catch (_) {}
  }

  Future<void>? _camOpening;

  Future<void> _ensureCam() {
    if (_cam != null && _cam!.value.isInitialized) return Future.value();
    return _camOpening ??= _setupCam().whenComplete(() => _camOpening = null);
  }

  void _startScan() async {
    if (_cam == null || !_cam!.value.isInitialized) return;
    setState(() {
      _stage = _Stage.scanning;
      _found.clear();
      _elapsed = 0;
      _frames = 0;
      _lastProcessedAt = null;
      _scanDeadline =
          DateTime.now().add(Duration(seconds: _scanDurationSec));
    });
    try {
      await _cam!.startImageStream(_onCameraFrame);
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.plan);
      return;
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed++);
      final deadline = _scanDeadline;
      if (deadline != null && _stage == _Stage.scanning) {
        if (DateTime.now().isAfter(deadline)) {
          _stopScan();
        }
      }
    });
  }

  void _onCameraFrame(CameraImage image) {
    if (!mounted || _stage != _Stage.scanning || _processingFrame) return;
    final now = DateTime.now();
    final last = _lastProcessedAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 1000)) {
      return;
    }
    _lastProcessedAt = now;
    _processingFrame = true;
    _processFrame(image).whenComplete(() => _processingFrame = false);
  }

  Future<void> _processFrame(CameraImage image) async {
    try {
      final input = _cameraImageToInputImage(image);
      if (input == null) return;
      final labels = await _labeler.processImage(input);
      final newlyFound = <_Found>[];
      for (final l in labels) {
        final name = l.label.toLowerCase();
        if (_labels.contains(name) && !_found.any((f) => f.label == name)) {
          newlyFound.add(_Found(label: l.label, confidence: l.confidence));
        }
      }
      if (mounted && _stage == _Stage.scanning) {
        setState(() {
          _frames++;
          _found.addAll(newlyFound);
        });
      }
    } catch (_) {}
  }

  InputImage? _cameraImageToInputImage(CameraImage image) {
    try {
      final planes = image.planes;
      if (planes.length < 3) return null;
      final width = image.width;
      final height = image.height;
      final builder = BytesBuilder();

      // Pack Y tightly (drop per-row padding).
      final y = planes[0];
      if (y.bytesPerRow == width) {
        builder.add(y.bytes.sublist(0, width * height));
      } else {
        for (var row = 0; row < height; row++) {
          final start = row * y.bytesPerRow;
          builder.add(y.bytes.sublist(start, start + width));
        }
      }

      // nv21 needs chroma as interleaved [V,U,V,U,...] — the raw
      // YUV_420_888 planes are separate U and V blocks (or a shared
      // interleaved buffer starting at V when pixelStride is 2).
      final u = planes[1];
      final v = planes[2];
      final cw = width ~/ 2;
      final ch = height ~/ 2;
      if (v.bytesPerPixel == 2) {
        for (var row = 0; row < ch; row++) {
          final start = row * v.bytesPerRow;
          builder.add(v.bytes.sublist(start, start + cw * 2));
        }
      } else {
        for (var row = 0; row < ch; row++) {
          final vs = row * v.bytesPerRow;
          final us = row * u.bytesPerRow;
          final vRow = v.bytes.sublist(vs, vs + cw);
          final uRow = u.bytes.sublist(us, us + cw);
          for (var i = 0; i < cw; i++) {
            builder.addByte(vRow[i]);
            builder.addByte(uRow[i]);
          }
        }
      }

      final sensorOrientation =
          _cam?.description.sensorOrientation ?? 0;
      final rotation = switch (sensorOrientation) {
        90 => InputImageRotation.rotation90deg,
        180 => InputImageRotation.rotation180deg,
        270 => InputImageRotation.rotation270deg,
        _ => InputImageRotation.rotation0deg,
      };
      return InputImage.fromBytes(
        bytes: builder.takeBytes(),
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: width,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  void _extendScan() {
    setState(() {
      _scanDeadline =
          DateTime.now().add(Duration(seconds: _scanDurationSec));
    });
  }

  void _stopScan() {
    if (_stage != _Stage.scanning) return;
    _timer?.cancel();
    final frames = _frames;
    final added = _autoPlaceFound();
    final guessed = _designId == null ? _guessRoomType() : null;
    if (guessed != null) _roomType = guessed;
    if (mounted) setState(() => _stage = _Stage.plan);
    if (mounted) {
      if (frames == 0) {
        showAppSnackbar(
          context,
          'The scan did not read the camera. Keep scanning a little longer.',
          isError: true,
          duration: const Duration(seconds: 4),
        );
      } else if (added > 0) {
        showAppSnackbar(
          context,
          'Added $added item${added == 1 ? '' : 's'} from the scan — drag to adjust.',
          duration: const Duration(seconds: 4),
        );
      } else {
        showAppSnackbar(
          context,
          _found.isEmpty
              ? 'No furniture recognized — add items from the catalog.'
              : 'Detected items could not be placed — add from the catalog.',
          duration: const Duration(seconds: 4),
        );
      }
    }
    // The still for the material scan must be taken while the camera is
    // still alive — detach it and release only after the capture settles.
    final cam = _cam;
    _cam = null;
    _captureInFlight = _captureStillThenRelease(cam);
  }

  // The AI material scan takes one still at scan end — the camera must
  // survive the stage flip, so it is detached and released only after the
  // capture settles. Every failure here is quiet; the plan is already up.
  Future<void> _captureStillThenRelease(CameraController? cam) async {
    Uint8List? jpeg;
    if (cam != null) {
      try {
        await cam.stopImageStream();
      } catch (_) {}
      try {
        final shot = await cam.takePicture();
        jpeg = await shot.readAsBytes();
      } catch (_) {}
      try {
        await cam.dispose();
      } catch (_) {}
    }
    if (jpeg == null || jpeg.isEmpty || !mounted) return;
    await _runMaterialScan(jpeg);
  }

  Future<void> _runMaterialScan(Uint8List jpeg) async {
    try {
      final scan = await _materialScan.analyzeFrame(jpeg);
      if (scan == null || scan.isEmpty || !mounted) return;
      setState(() => _absorbMaterialScan(scan));
      final parts = [
        if (scan.floorType != null)
          '${RoomFinishCatalog.floorLabel(scan.floorType!)} floor',
        if (scan.wallType != null)
          '${RoomFinishCatalog.wallLabel(scan.wallType!)} walls',
      ];
      showAppSnackbar(
        context,
        'Scan matched: ${parts.join(', ')}.',
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      if (mounted) {
        showAppSnackbar(
          context,
          userMessage(e,
              fallback: 'Could not read room materials right now.'),
          duration: const Duration(seconds: 4),
        );
      }
    }
  }

  void _absorbMaterialScan(RoomMaterialScan scan) {
    _floorFinishType = scan.floorType?.name ?? _floorFinishType;
    _floorFinishColor = scan.floorColorArgb ?? _floorFinishColor;
    _wallFinishType = scan.wallType?.name ?? _wallFinishType;
    _wallFinishColor = scan.wallColorArgb ?? _wallFinishColor;
    _touchWalls();
  }

  @visibleForTesting
  RoomDesign debugApplyMaterialScan(RoomMaterialScan scan) {
    _absorbMaterialScan(scan);
    return _snapshotDesign();
  }

  String? _guessRoomType() {
    final labels = _found.map((f) => f.label.toLowerCase()).toSet();
    bool any(Set<String> keys) => labels.any(keys.contains);
    if (any({'bed', 'bed frame', 'mattress'})) return 'bedroom';
    if (any({'refrigerator', 'oven', 'microwave'})) return 'kitchen';
    if (any({'dining table'})) return 'dining_room';
    if (any({'desk'})) return 'home_office';
    return null;
  }

  @visibleForTesting
  String? debugGuessRoomType(List<String> labels) {
    _found
      ..clear()
      ..addAll([for (final l in labels) _Found(label: l, confidence: 0.9)]);
    return _guessRoomType();
  }

  // Scan labels ML Kit emits for surfaces/materials — never furniture.
  static const _scanJunk = {
    'floor', 'wood', 'hardwood', 'tile', 'wall', 'ceiling',
    'curtain', 'pillow', 'cushion', 'painting', 'picture frame',
    'wall art', 'mirror', 'vase', 'flower', 'light',
  };

  int _autoPlaceFound() {
    final cats = <_Cat>[];
    for (final f in _found) {
      final lower = f.label.toLowerCase();
      if (_scanJunk.contains(lower)) continue;
      final cat = _matchCatalog(f.label);
      if (cat.category == 'misc') continue; // no catalog match
      if (cats.any((c) => c.iconName == cat.iconName)) continue;
      cats.add(cat);
    }
    if (cats.isEmpty) return 0;

    // Flow left-to-right from the top-left, wrapping into a new row —
    // a tidy row-packed layout the user can then drag around.
    var cursorX = 25.0;
    var cursorY = 25.0;
    var rowH = 0.0;
    final base = DateTime.now().microsecondsSinceEpoch;
    final items = <FurniturePlacement>[];
    for (var i = 0; i < cats.length; i++) {
      final cat = cats[i];
      if (cursorX + cat.defaultWidth > _roomW - 25 && cursorX > 25) {
        cursorX = 25;
        cursorY += rowH + 25;
        rowH = 0;
      }
      var item = FurniturePlacement(
        id: '$base-$i',
        name: cat.name,
        iconName: cat.iconName,
        x: cursorX,
        y: cursorY,
        width: cat.defaultWidth,
        height: cat.defaultHeight,
        imageAsset: cat.imageAsset,
      );
      final fitted = fitInRoom(item,
          roomW: _roomW,
          roomH: _roomH,
          walls: _walls,
          interiorWalls: _interior,
          others: [..._furniture, ...items]);
      if (fitted == null) continue; // bigger than the room — never parked in a wall
      item = fitted;
      items.add(item);
      cursorX += cat.defaultWidth + 25;
      rowH = max(rowH, cat.defaultHeight);
    }
    if (!mounted) return items.length;
    setState(() => _furniture = [..._furniture, ...items]);
    return items.length;
  }

  _Cat _matchCatalog(String label) {
    final lower = label.toLowerCase().trim();
    final alias = _labelAliases[lower];
    if (alias != null) {
      for (final c in _catalog) {
        if (c.name == alias) return c;
      }
    }
    for (final c in _catalog) {
      if (c.name.toLowerCase().contains(lower) ||
          lower.contains(c.name.toLowerCase())) {
        return c;
      }
    }
    return _Cat(label, 'unknown', Icons.folder, 'misc', 80, 60, null);
  }

  // ─── Wall (room shape) geometry helpers ───
  // Thin wrappers over the shared implementation — the walkthrough walks
  // the same rules, so the truth lives in room_fit.dart.

  double _footprintW(FurniturePlacement f) => footprintW(f);
  double _footprintH(FurniturePlacement f) => footprintH(f);

  FurniturePlacement _resolveDrop(FurniturePlacement f) => resolveDrop(f,
      roomW: _roomW, roomH: _roomH, walls: _walls, interiorWalls: _interior, others: _furniture);

  FurniturePlacement? _fitInRoom(FurniturePlacement f) => fitInRoom(f,
      roomW: _roomW, roomH: _roomH, walls: _walls, interiorWalls: _interior, others: _furniture);

  String _sizeLabel(FurniturePlacement f) =>
      '${f.width.toInt()}×${f.height.toInt()} cm';

  // After the room shrinks or the outline changes: say which pieces can no
  // longer fit anywhere (once per distinct set — no snackbar spam).
  String _lastUnfitSig = '';

  void _warnUnfit() {
    final unfit = unfitPlacements(_furniture,
        roomW: _roomW, roomH: _roomH, walls: _walls, interiorWalls: _interior);
    final sig = unfit.map((f) => f.id).join(',');
    if (sig == _lastUnfitSig) return;
    _lastUnfitSig = sig;
    if (unfit.isEmpty || !mounted) return;
    final names = unfit.map((f) => f.name).toSet().join(', ');
    showAppSnackbar(
      context,
      unfit.length == 1
          ? '$names no longer fits this room. Resize or remove it.'
          : '${unfit.length} pieces no longer fit this room ($names).',
      isError: true,
    );
  }

  // ─── 3D scene interactions (screen ↔ floor plane) ───

  Rect get _roomRectCm {
    if (_walls.length >= 3) {
      var minX = _walls.first.dx;
      var minY = _walls.first.dy;
      var maxX = minX;
      var maxY = minY;
      for (final w in _walls.skip(1)) {
        minX = min(minX, w.dx);
        minY = min(minY, w.dy);
        maxX = max(maxX, w.dx);
        maxY = max(maxY, w.dy);
      }
      return Rect.fromLTRB(minX, minY, maxX, maxY);
    }
    return Rect.fromLTWH(0, 0, _roomW, _roomH);
  }

  void _reframeRig() {
    final rect = _roomRectCm;
    final diag =
        sqrt(rect.width * rect.width + rect.height * rect.height) / 100.0;
    _rig.targetXm = rect.center.dx / 100;
    _rig.targetZm = rect.center.dy / 100;
    final aspect = _viewport.height > 0 ? _viewport.width / _viewport.height : 0.0;
    _rig.distanceM = aspect > 0
        ? fitRoomDistanceM(
            roomWCm: rect.width,
            roomHCm: rect.height,
            fovDeg: _rig.fovDeg,
            aspect: aspect)
        : max(2.2, diag * 0.85);
    _rig.maxDistanceM = max(max(6.0, diag * 2.5), _rig.distanceM * 1.6);
  }

  // First real layout: reframe once for the true viewport aspect. Later size
  // changes (selection bar, fullscreen) keep the user's camera.
  bool _framedForViewport = false;

  void _frameForViewportOnce() {
    if (_framedForViewport || _viewport.isEmpty) return;
    _framedForViewport = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reframeRig();
      _pushCamera();
    });
  }

  void _pushCamera() {
    _sceneRev.value++;
    _bridge.setCamera(_rig.pose);
    _touchCutaway();
  }

  Offset _sceneLocal(Offset global) {
    final box = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null || !box.hasSize ? global : box.globalToLocal(global);
  }

  String? _pickAt(Offset local) => pickPlacementId(
        _rig.pose,
        _viewport,
        local,
        _furniture,
        heightMOf: plannerHeightMOf,
      );

  void _onSceneTap(Offset local) {
    if (_wallMode) {
      final p = floorPointAt(_rig.pose, _viewport, local);
      if (p == null) return;
      _addInteriorCorner(Offset(
        p.dx.clamp(0.0, _roomW).toDouble(),
        p.dy.clamp(0.0, _roomH).toDouble(),
      ));
      return;
    }
    final id = _pickAt(local);
    setState(() {
      _selectedIdx =
          id == null ? -1 : _furniture.indexWhere((f) => f.id == id);
    });
  }

  void _onSceneLongPress(Offset local) {
    if (_wallMode) {
      _clearInteriorWalls();
      return;
    }
    final id = _pickAt(local);
    if (id == null) return;
    _removeFurniture(_furniture.indexWhere((f) => f.id == id));
  }

  void _onScaleStart(ScaleStartDetails d) {
    if (d.pointerCount >= 2) {
      _drag = _SceneDrag.pinch;
      _lastPinch = 1;
      return;
    }
    if (_wallMode) {
      // Corner handles own wall editing; an empty-canvas drag orbits.
      _drag = _SceneDrag.orbit;
      return;
    }
    final id = _pickAt(d.localFocalPoint);
    if (id == null) {
      _drag = _SceneDrag.orbit;
      return;
    }
    final idx = _furniture.indexWhere((e) => e.id == id);
    final f = _furniture[idx];
    final p = floorPointAt(_rig.pose, _viewport, d.localFocalPoint);
    _drag = _SceneDrag.move;
    _moveId = id;
    _grabDelta = p == null ? Offset.zero : Offset(f.x - p.dx, f.y - p.dy);
    if (idx != _selectedIdx) setState(() => _selectedIdx = idx);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    switch (_drag) {
      case _SceneDrag.move:
        final id = _moveId;
        if (id == null) return;
        final idx = _furniture.indexWhere((e) => e.id == id);
        if (idx < 0) return;
        final p = floorPointAt(_rig.pose, _viewport, d.localFocalPoint);
        if (p == null) return;
        final f = _furniture[idx];
        final nx = (p.dx + _grabDelta.dx)
            .clamp(0.0, max(0.0, _roomW - _footprintW(f)))
            .toDouble();
        final ny = (p.dy + _grabDelta.dy)
            .clamp(0.0, max(0.0, _roomH - _footprintH(f)))
            .toDouble();
        setState(() => _furniture[idx] = f.copyWith(x: nx, y: ny));
        _touchFurniture();
      case _SceneDrag.orbit:
        _rig.orbit(-d.focalPointDelta.dx * 0.008, d.focalPointDelta.dy * 0.006);
        _pushCamera();
      case _SceneDrag.pinch:
        if (d.scale > 0) {
          _rig.dolly(_lastPinch / d.scale);
          _lastPinch = d.scale;
          _pushCamera();
        }
      case _SceneDrag.none:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final id = _moveId;
    if (_drag == _SceneDrag.move && id != null) {
      final idx = _furniture.indexWhere((e) => e.id == id);
      if (idx >= 0) _commitFurniture(_furniture[idx]);
    }
    _drag = _SceneDrag.none;
    _moveId = null;
  }

  // Wall-mode corner handles: projected chips, draggable in place. Wall
  // editing lives behind wall mode so a furniture drag can never grab one.
  List<Widget> _wallHandles() {
    if (!_wallMode) return const [];
    final pose = _rig.pose;
    return [
      for (var c = 0; c < _interior.length; c++)
        for (var i = 0; i < _interior[c].length; i++)
          Builder(builder: (ctx) {
            final pt = _interior[c][i];
            final pos =
                projectWorldPoint(pose, _viewport, pt.dx / 100, 0, pt.dy / 100);
            if (pos == null) return const SizedBox.shrink();
            return Positioned(
              left: pos.dx - 14,
              top: pos.dy - 14,
              child: GestureDetector(
                key: ValueKey('interior-handle-$c-$i'),
                onPanUpdate: (d) {
                  final p = floorPointAt(
                      _rig.pose, _viewport, _sceneLocal(d.globalPosition));
                  if (p == null) return;
                  setState(() {
                    _interior[c][i] = Offset(
                      p.dx.clamp(0.0, _roomW).toDouble(),
                      p.dy.clamp(0.0, _roomH).toDouble(),
                    );
                  });
                  _touchWalls();
                },
                onPanEnd: (_) => _syncFurnitureNow(),
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.accent, width: 3),
                    ),
                  ),
                ),
              ),
            );
          }),
      if (_walls.length >= 3) ...[
      for (var i = 0; i < _walls.length; i++)
        Builder(
          builder: (ctx) {
            final pos = projectWorldPoint(
                pose, _viewport, _walls[i].dx / 100, 0, _walls[i].dy / 100);
            if (pos == null) return const SizedBox.shrink();
            return Positioned(
              left: pos.dx - 14,
              top: pos.dy - 14,
              child: GestureDetector(
                key: ValueKey('wall-handle-$i'),
                onPanUpdate: (d) {
                  final p = floorPointAt(
                      _rig.pose, _viewport, _sceneLocal(d.globalPosition));
                  if (p == null) return;
                  setState(() {
                    _walls[i] = Offset(
                      p.dx.clamp(0.0, _roomW).toDouble(),
                      p.dy.clamp(0.0, _roomH).toDouble(),
                    );
                  });
                  _touchWalls();
                },
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    ];
  }

  List<Widget> _dimOverlay() {
    final rect = _roomRectCm;
    final pose = _rig.pose;
    final top = projectWorldPoint(
        pose, _viewport, rect.center.dx / 100, 0.15, rect.top / 100);
    final left = projectWorldPoint(
        pose, _viewport, rect.left / 100, 0.15, rect.center.dy / 100);
    return [
      if (top != null)
        _dimLabel('${_roomW.toInt()} cm', top: top.dy - 22, left: top.dx - 30),
      if (left != null)
        _dimLabel('${_roomH.toInt()} cm',
            left: left.dx - 12, top: left.dy - 10, vertical: true),
    ];
  }

  @visibleForTesting
  Offset? debugFloorToScreen(Offset planCm) => projectWorldPoint(
      _rig.pose, _viewport, planCm.dx / 100, 0, planCm.dy / 100);

  @visibleForTesting
  Offset? debugFloorAt(Offset sceneLocal) =>
      floorPointAt(_rig.pose, _viewport, sceneLocal);

  // Screen position of the piece's box center (mid-height) — the natural
  // press point for select/drag.
  @visibleForTesting
  Offset? debugPieceToScreen(FurniturePlacement f) => projectWorldPoint(
        _rig.pose,
        _viewport,
        (f.x + _footprintW(f) / 2) / 100,
        plannerHeightMOf(f) / 2,
        (f.y + _footprintH(f) / 2) / 100,
      );

  // Each tap extends the open chain with a real wall (the first tap of a
  // chain is a post); "Finish wall" closes it so the next tap starts a new,
  // separate wall. Pieces the new wall cuts through settle beside it.
  void _addInteriorCorner(Offset p) {
    if (_chainOpen && _interior.isNotEmpty) {
      final chain = _interior.last;
      if ((chain.last - p).distance < 12) return;
      setState(() => chain.add(p));
    } else {
      setState(() {
        _interior.add([p]);
        _chainOpen = true;
      });
    }
    _touchWalls();
    _syncFurnitureNow();
  }

  void _finishInteriorWall() {
    if (!_chainOpen) return;
    setState(() {
      _chainOpen = false;
      // A chain that never got a second corner is a stray post - drop it.
      if (_interior.isNotEmpty && _interior.last.length < 2) {
        _interior.removeLast();
      }
    });
    _touchWalls();
  }

  void _clearInteriorWalls() {
    if (_interior.isEmpty) return;
    final snapshot = [for (final c in _interior) List<Offset>.of(c)];
    setState(() {
      _interior.clear();
      _chainOpen = false;
    });
    _touchWalls();
    if (!mounted) return;
    showAppSnackbar(
      context,
      'Interior walls cleared',
      duration: const Duration(seconds: 4),
      actionLabel: 'Undo',
      onAction: () {
        if (!mounted || _interior.isNotEmpty) return;
        setState(() => _interior.addAll(snapshot));
        _touchWalls();
        _syncFurnitureNow();
      },
    );
  }

  @visibleForTesting
  List<List<Offset>> get debugInteriorWalls =>
      [for (final c in _interior) List.of(c)];

  // ─── Furniture actions ───

  void _removeFurniture(int idx) {
    if (idx < 0 || idx >= _furniture.length) return;
    final removed = _furniture[idx];
    final wasSelected = _selectedIdx == idx;
    setState(() {
      _furniture.removeAt(idx);
      if (wasSelected) {
        _selectedIdx = -1;
      } else if (_selectedIdx > idx) {
        _selectedIdx--;
      }
    });
    _bridge.syncFurniture(_furniture);
    showAppSnackbar(
      context,
      '${removed.name} removed',
      duration: const Duration(seconds: 4),
      actionLabel: 'Undo',
      onAction: () {
        if (!mounted || idx > _furniture.length) return;
        setState(() => _furniture.insert(idx, removed));
        _bridge.syncFurniture(_furniture);
      },
    );
  }

  Future<void> _confirmClearAll() async {
    if (_furniture.isEmpty && _walls.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear the plan?'),
        content: Text(_furniture.isEmpty
            ? 'This removes the wall outline from the plan.'
            : 'This removes all ${_furniture.length} placed items'
                '${_walls.isEmpty ? '' : ' and the wall outline'} from the plan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final furniture = _furniture.toList();
    final walls = List<Offset>.of(_walls);
    final interior = [for (final c in _interior) List<Offset>.of(c)];
    setState(() {
      _furniture.clear();
      _walls.clear();
      _interior.clear();
      _chainOpen = false;
      _selectedIdx = -1;
    });
    _bridge.syncFurniture(_furniture);
    if (walls.isNotEmpty || interior.isNotEmpty) _touchWalls();
    showAppSnackbar(
      context,
      'Plan cleared',
      duration: const Duration(seconds: 4),
      actionLabel: 'Undo',
      onAction: () {
        if (!mounted) return;
        setState(() {
          _furniture = furniture;
          _walls.addAll(walls);
          _interior.addAll(interior);
        });
        _bridge.syncFurniture(_furniture);
        if (walls.isNotEmpty || interior.isNotEmpty) _touchWalls();
      },
    );
  }

  void _rotateSelected() {
    if (_selectedIdx < 0 || _selectedIdx >= _furniture.length) return;
    final f = _furniture[_selectedIdx];
    // Swapping the footprint can push the piece into a wall — settle, and
    // refuse the turn when the turned piece fits nowhere.
    final turned =
        _resolveDrop(f.copyWith(rotation: (f.rotation + 90) % 360));
    if (!placementFits(turned,
        roomW: _roomW, roomH: _roomH, walls: _walls, interiorWalls: _interior)) {
      showAppSnackbar(context, 'No room to turn ${f.name} here.',
          isError: true);
      return;
    }
    setState(() => _furniture[_selectedIdx] = turned);
    _bridge.syncFurniture(_furniture);
  }

  // Shared by the scene drag commit and the size dialog.
  void _commitFurniture(FurniturePlacement moved) {
    setState(() {
      final idx = _furniture.indexWhere((e) => e.id == moved.id);
      if (idx < 0) return;
      _furniture[idx] = _resolveDrop(moved);
    });
    _bridge.syncFurniture(_furniture);
  }

  _Cat? _catFor(String iconName) {
    for (final c in _catalog) {
      if (c.iconName == iconName) return c;
    }
    return null;
  }

  Future<void> _openSizeDialog() async {
    if (_selectedIdx < 0 || _selectedIdx >= _furniture.length) return;
    final item = _furniture[_selectedIdx];
    final result = await showDialog<({double w, double h})>(
      context: context,
      builder: (_) => _SizeDialog(item: item, cat: _catFor(item.iconName)),
    );
    if (result == null || !mounted) return;
    if (_selectedIdx < 0 || _selectedIdx >= _furniture.length) return;
    final resized =
        _furniture[_selectedIdx].copyWith(width: result.w, height: result.h);
    final fitted = _fitInRoom(resized);
    if (fitted == null) {
      showAppSnackbar(
          context,
          '${resized.name} at ${_sizeLabel(resized)} is bigger than this '
          'room (${_roomW.toInt()}×${_roomH.toInt()} cm).',
          isError: true);
      return;
    }
    setState(() => _furniture[_selectedIdx] = fitted);
    _bridge.syncFurniture(_furniture);
  }

  void _openDimensionEdit() {
    _widthCtrl.text = _roomW.toInt().toString();
    _heightCtrl.text = _roomH.toInt().toString();
    setState(() => _isEditingDimensions = true);
  }

  void _finishDimensionEdit() {
    final w = double.tryParse(_widthCtrl.text.trim());
    final h = double.tryParse(_heightCtrl.text.trim());
    setState(() {
      if (w != null && w > 50) _roomW = w;
      if (h != null && h > 50) _roomH = h;
      _isEditingDimensions = false;
    });
    _warnUnfit();
    _touchWalls();
    _syncFurnitureNow();
    _reframeRig();
    _pushCamera();
  }

  // ─── Room size presets ────────────────────────────────────────────────

  static const _roomPresets = [
    ('Small', 300, 300),
    ('Medium', 400, 400),
    ('Large', 500, 400),
    ('Long', 600, 300),
  ];

  void _addFromCatalog(_Cat cat) {
    final id =
        _nextPieceId('cat');
    final maxX = max(1, (_roomW - cat.defaultWidth).toInt());
    final maxY = max(1, (_roomH - cat.defaultHeight).toInt());
    var x = ((20 + _furniture.length * 30) % maxX)
        .toDouble()
        .clamp(5, max(5.0, _roomW - cat.defaultWidth - 5))
        .toDouble();
    var y = ((15 + _furniture.length * 35) % maxY)
        .toDouble()
        .clamp(5, max(5.0, _roomH - cat.defaultHeight - 5))
        .toDouble();
    var item = FurniturePlacement(
      id: id,
      name: cat.name,
      iconName: cat.iconName,
      x: x,
      y: y,
      width: cat.defaultWidth,
      height: cat.defaultHeight,
      imageAsset: cat.imageAsset,
    );
    // Refuse pieces bigger than the room (either way round) instead of
    // parking them through a wall; otherwise land on clear floor and select
    // the new piece so it is easy to spot.
    final fitted = _fitInRoom(item);
    if (fitted == null) {
      showAppSnackbar(
          context,
          '${item.name} (${_sizeLabel(item)}) is bigger than this room '
          '(${_roomW.toInt()}×${_roomH.toInt()} cm).',
          isError: true);
      return;
    }
    setState(() {
      _furniture.add(fitted);
      _selectedIdx = _furniture.length - 1;
    });
    _bridge.syncFurniture(_furniture);
  }

  Future<void> _openFurniturePicker() async {
    final picked = await showCatalogPickerSheet<_Cat>(
      context: context,
      title: 'Add furniture',
      subtitle: 'Tap an item to place it on the plan',
      items: _catalog,
      labelOf: (c) => c.name,
      categoryOf: (c) => c.category,
      tileBuilder: (_, cat) => _CatalogThumb(cat: cat),
    );
    if (picked == null || !mounted) return;
    _addFromCatalog(picked);
  }

  // In-memory copy of the current plan for the walkthrough; id stays empty
  // until something has been saved, so its Save knows create vs update.
  RoomDesign _snapshotDesign() => RoomDesign(
        id: _designId ?? '',
        name: _designName ?? 'My $_roomTypeLabel Design',
        roomType: _roomType,
        widthCm: _roomW,
        heightCm: _roomH,
        furniture: List.of(_furniture),
        walls: List.of(_walls),
        interiorWalls: [for (final c in _interior) List.of(c)],
        detectedItems: _found.map((f) => f.label).toList(),
        floorFinishType: _floorFinishType,
        floorFinishColor: _floorFinishColor,
        wallFinishType: _wallFinishType,
        wallFinishColor: _wallFinishColor,
        createdAt: _designCreatedAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        userId: widget.existingDesign?.userId ?? '',
      );

  // Pull a walkthrough result back into the editor — adopted fields make
  // the next save update the same design instead of minting a duplicate.
  void _adoptDesign(RoomDesign d) {
    setState(() {
      _designId = d.id;
      _designName = d.name;
      _designCreatedAt = d.createdAt;
      _roomW = d.widthCm;
      _roomH = d.heightCm;
      _roomType = d.roomType;
      _walls
        ..clear()
        ..addAll(d.walls);
      _interior
        ..clear()
        ..addAll([for (final c in d.interiorWalls) List.of(c)]);
      _chainOpen = false;
      // Render clamp: round-tripped placements settle instead of drawing
      // inside a wall.
      _furniture = clampAllPlacements(List.of(d.furniture),
          roomW: _roomW, roomH: _roomH, walls: _walls, interiorWalls: _interior);
      _floorFinishType = d.floorFinishType;
      _floorFinishColor = d.floorFinishColor;
      _wallFinishType = d.wallFinishType;
      _wallFinishColor = d.wallFinishColor;
      _selectedIdx = -1;
    });
    _touchWalls();
    _bridge.syncFurniture(_furniture);
    _reframeRig();
    _pushCamera();
  }

  Future<void> _saveDesign() async {
    final user = ref.read(currentUserProvider);
    if (user == null) {
      if (mounted) {
        showAppSnackbar(context, 'Please sign in to save designs',
            isError: true);
      }
      return;
    }

    final nameCtrl = TextEditingController(
        text: _designName ?? 'My $_roomTypeLabel Design');

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

    if (name == null || name.isEmpty) return;

    final ds = ref.read(roomDesignDatasourceProvider);
    final now = DateTime.now();
    final designId =
        _designId ?? 'design-${now.millisecondsSinceEpoch}';

    final design = RoomDesign(
      id: designId,
      name: name,
      roomType: _roomType,
      widthCm: _roomW,
      heightCm: _roomH,
      furniture: _furniture,
      walls: List.of(_walls),
      interiorWalls: [for (final c in _interior) List.of(c)],
      detectedItems: _found.map((f) => f.label).toList(),
      floorFinishType: _floorFinishType,
      floorFinishColor: _floorFinishColor,
      wallFinishType: _wallFinishType,
      wallFinishColor: _wallFinishColor,
      userId: user.uid,
      createdAt: _designCreatedAt ?? now,
      updatedAt: now,
    );

    try {
      if (_designId != null) {
        await ds.updateDesign(designId, design.toJson());
      } else {
        await ds.createDesign(
            designId: designId, data: design.toJson());
      }
      _designId = designId;
      _designName = name;
      _designCreatedAt = design.createdAt;
      if (mounted) {
        showAppSnackbar(
          context,
          'Design "$name" saved!',
          duration: const Duration(seconds: 3),
        );
        Navigator.pop(context, true);
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

  String get _roomTypeLabel {
    for (final rt in _roomTypes) {
      if (rt.$1 == _roomType) return rt.$2;
    }
    return _roomType;
  }

  Future<void> _pickRoomType() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Room type'),
        children: [
          for (final rt in _roomTypes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, rt.$1),
              child: Row(
                children: [
                  Icon(rt.$3, size: 20),
                  const SizedBox(width: 10),
                  Text(rt.$2),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _roomType = picked);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shellThrottle?.cancel();
    _furnitureThrottle?.cancel();
    try {
      _cam?.stopImageStream();
    } catch (_) {}
    _labeler.close();
    try {
      _cam?.dispose();
    } catch (_) {}
    _wallsRev.dispose();
    _sceneRev.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _stage != _Stage.plan;
    final bgColor = isDark ? Colors.black : AppColors.background;
    final fgColor = isDark ? Colors.white : AppColors.textPrimary;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: bgColor,
        body: Column(
          children: [
            // ── Page controls (no AppBar band) ──
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
                child: Row(
                  children: [
                    if (Navigator.of(context).canPop()) ...[
                      FloatingBackButton(
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                    ] else
                      const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        switch (_stage) {
                          _Stage.init || _Stage.scanning => 'Room Scanner',
                          _Stage.plan => _designId != null
                              ? 'Edit: ${_designName ?? 'Design'}'
                              : 'Room Planner',
                        },
                        style: isDark
                            ? GoogleFonts.poppins(
                                color: fgColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 20,
                              )
                            : GoogleFonts.poppins(
                                color: fgColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 24,
                                letterSpacing: -0.3,
                                height: 1.2,
                              ),
                      ),
                    ),
                    if (_stage == _Stage.plan) ...[
                      IconButton(
                        icon: Icon(Icons.camera_alt, color: fgColor),
                        tooltip: 'Scan Room',
                        onPressed: () async {
                          await _ensureCam();
                          if (!context.mounted) return;
                          if (_cam != null && _cam!.value.isInitialized) {
                            _startScan();
                          } else {
                            showAppSnackbar(context, 'Camera not available',
                                isError: true);
                          }
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.view_in_ar, color: fgColor),
                        tooltip: 'View in AR',
                        onPressed: () async {
                          // Same round-trip as Walk Through: capture a
                          // scanned outline in AR and adopt it back here.
                          final updated =
                              await context.push<RoomDesign>(
                            '/ar-viewer',
                            extra: ArViewerArgs(
                              items: ArFurnitureLibrary.fromIconNames(
                                  _furniture.map((f) => f.iconName).toList()),
                              design: _snapshotDesign(),
                            ),
                          );
                          if (!mounted) return;
                          if (updated != null) _adoptDesign(updated);
                          _rebuildSceneWhenSettled();
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.directions_walk, color: fgColor),
                        tooltip: 'Walk Through',
                        onPressed: () async {
                          final saved = await context.push<RoomDesign>(
                            '/walkthrough',
                            extra: _snapshotDesign(),
                          );
                          if (!mounted) return;
                          if (saved != null) _adoptDesign(saved);
                          _rebuildSceneWhenSettled();
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.save, color: fgColor),
                        tooltip: 'Save Design',
                        onPressed: _saveDesign,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          // ── Body ──
          Expanded(
            child: switch (_stage) {
              _Stage.init => _initView(),
              _Stage.scanning => _scanView(),
              _Stage.plan => _planEditor(),
            },
          ),
        ],
        ),
      ),
    );
  }

  // ─── Init view (camera preview) ───
  Widget _camPreview() {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) {
      return const ColoredBox(
          color: Colors.black,
          child: Center(
              child:
                  Icon(Icons.camera_alt, size: 64, color: Colors.white38)));
    }
    return CameraPreview(cam);
  }

  Widget _initView() {
    final ready = _cam != null && _cam!.value.isInitialized;
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
              borderRadius: BorderRadius.circular(16), child: _camPreview()),
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
    final duration = _scanDurationSec;
    final progress = (_elapsed / duration).clamp(0.0, 1.0);
    final remaining = max(0, duration - _elapsed);
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _camPreview()),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('${_found.length} items found',
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.accent)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Scanning… $remaining s left — move slowly around the room',
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: Colors.white),
                    ),
                  ),
                  Text('$_frames frames',
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: Colors.white54)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.white12,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        SizedBox(
          height: 40,
          child: _found.isEmpty
              ? Center(
                  child: Text('Point the camera at furniture, walls and floor',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.white54)),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _found.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.success
                              .withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle,
                            size: 14, color: AppColors.success),
                        const SizedBox(width: 5),
                        Text(_found[i].label,
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 8),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _extendScan,
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Keep Scanning'),
              style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white38)),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _stopScan,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Done'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                minimumSize: Size.zero,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─── Floor plan editor ───
  Widget _planEditor() {
    // Short screens (or large text) can't fit the fixed panels plus a usable
    // 3D view. The scene always keeps the leftover space (and its gestures —
    // a scrolling page stole wall-handle drags); only the bottom panels
    // scroll, capped at half the height, and the preset chips step aside.
    return LayoutBuilder(builder: (context, constraints) {
      final ts = MediaQuery.textScalerOf(context).scale(1);
      final compact = !_sceneExpanded &&
          constraints.maxHeight.isFinite &&
          constraints.maxHeight < 600 * ts;
      return _planEditorColumn(
          compact: compact,
          bottomMax: constraints.maxHeight.isFinite
              ? constraints.maxHeight * 0.5
              : double.infinity);
    });
  }

  Widget _planEditorColumn({required bool compact, required double bottomMax}) {
    final bottomClearance = MediaQuery.paddingOf(context).bottom + 8;
    return Column(
      children: [
        if (!compact &&
            !_sceneExpanded &&
            _furniture.isEmpty &&
            widget.existingDesign == null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.crop_square, size: 16, color: AppColors.accent),
                    const SizedBox(width: 6),
                    Text('Room Size',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('— then add furniture from the catalog below',
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: AppColors.textHint)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _roomPresets.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final p = _roomPresets[i];
                      final isSelected = _roomW == p.$2.toDouble() && _roomH == p.$3.toDouble();
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _roomW = p.$2.toDouble();
                            _roomH = p.$3.toDouble();
                          });
                          _warnUnfit();
                          _touchWalls();
                          _syncFurnitureNow();
                          _reframeRig();
                          _pushCamera();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.accent : AppColors.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? AppColors.accent : AppColors.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(p.$1,
                                  style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected ? Colors.white : AppColors.textPrimary)),
                              const SizedBox(width: 6),
                              Text('${p.$2}×${p.$3}cm',
                                  style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      color: isSelected ? Colors.white70 : AppColors.textHint)),
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

        Expanded(
          child: Padding(
            padding: _sceneExpanded
                ? const EdgeInsets.fromLTRB(6, 4, 6, 6)
                : const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                _viewport = constraints.biggest;
                _frameForViewportOnce();
                return Stack(
                  key: _sceneKey,
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Scene3DView(
                          key: ValueKey('planner-scene3d-$_sceneGen'),
                          controller: _bridge.controller,
                          onTap: _onSceneTap,
                          onLongPress: _onSceneLongPress,
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          onScaleEnd: _onScaleEnd,
                          fallback: _fallbackPreview(),
                        ),
                      ),
                    ),
                    // Projected overlays: re-project on every camera move.
                    // The inner Stack is hit-transparent except for the
                    // wall handles, so scene gestures pass through.
                    ValueListenableBuilder<int>(
                      valueListenable: _sceneRev,
                      builder: (_, __, ___) => Stack(
                        children: [
                          if (_selectedIdx >= 0 &&
                              _selectedIdx < _furniture.length)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _SelectionBoxPainter(
                                    pose: _rig.pose,
                                    viewport: _viewport,
                                    item: _furniture[_selectedIdx],
                                    heightM: plannerHeightMOf(
                                        _furniture[_selectedIdx]),
                                  ),
                                ),
                              ),
                            ),
                          ..._dimOverlay(),
                          ..._wallHandles(),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 6,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: GestureDetector(
                          onTap: _pickRoomType,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _roomTypeLabel,
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_drop_down,
                                    size: 14, color: Colors.white),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _cameraResetButton(),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: _zoomControls(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        _BottomPanels(
          compact: compact,
          maxHeight: bottomMax,
          children: [
        if (_selectedIdx >= 0 &&
            _selectedIdx < _furniture.length)
          Container(
            key: const ValueKey('planner-selection-bar'),
            padding: const EdgeInsets.fromLTRB(
                16, 4, 8, 2),
            color: AppColors.surface,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: _selectionThumb(_furniture[_selectedIdx]),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.touch_app,
                    size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_furniture[_selectedIdx].name} · '
                    '${_furniture[_selectedIdx].width.toInt()}×'
                    '${_furniture[_selectedIdx].height.toInt()} cm',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ),
                if (_furniture[_selectedIdx].rotation % 360 != 0)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.rotate_90_degrees_cw,
                        key: ValueKey('rotation-badge'),
                        size: 14,
                        color: AppColors.accent),
                  ),
                TextButton.icon(
                  onPressed: _openSizeDialog,
                  icon: const Icon(Icons.aspect_ratio, size: 15),
                  label: const Text('Size'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8),
                    minimumSize: Size.zero,
                    visualDensity:
                        VisualDensity.compact,
                  ),
                ),
                TextButton.icon(
                  onPressed: _rotateSelected,
                  icon: const Icon(
                      Icons.rotate_90_degrees_cw,
                      size: 15),
                  label: const Text('Rotate'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8),
                    minimumSize: Size.zero,
                    visualDensity:
                        VisualDensity.compact,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: AppColors.error),
                  onPressed: () =>
                      _removeFurniture(_selectedIdx),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

        if (!_sceneExpanded) _catalogPanel(),

        if (!_sceneExpanded)
        Container(
          padding:
              const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border:
                Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isEditingDimensions) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _widthCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Width (cm)',
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
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _heightCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Height (cm)',
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
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check, size: 20),
                      onPressed: _finishDimensionEdit,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ] else ...[
                GestureDetector(
                  onTap: _openDimensionEdit,
                  child: Row(
                    children: [
                      const Icon(Icons.crop_free,
                          size: 18,
                          color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                              'Room: ${_roomW.toInt()} × ${_roomH.toInt()} cm'
                              '${_walls.length >= 3 ? '  •  ${_walls.length}-wall shape' : ''}',
                              maxLines: 1,
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: AppColors.textSecondary)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit,
                          size: 14, color: AppColors.textHint),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              // Wrap keeps every label whole: a squeeze-Row truncated the
              // button text ("+Add furnitur…") on narrow planner panels.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _openFurniturePicker,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(
                      _furniture.isEmpty
                          ? 'Add furniture'
                          : 'Add furniture · ${_furniture.length} placed',
                      maxLines: 1,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  GestureDetector(
                    onLongPress:
                        _interior.isEmpty ? null : _clearInteriorWalls,
                    child: OutlinedButton.icon(
                      key: const ValueKey('planner-walls-toggle'),
                      onPressed: () {
                        if (_wallMode) _finishInteriorWall();
                        setState(() => _wallMode = !_wallMode);
                      },
                      icon: Icon(
                        _wallMode ? Icons.check : Icons.polyline_outlined,
                        size: 18,
                      ),
                      label: Text(_wallMode ? 'Done' : 'Walls'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 12),
                        minimumSize: Size.zero,
                        foregroundColor: _wallMode
                            ? AppColors.accent
                            : AppColors.textPrimary,
                        side: BorderSide(
                            color: _wallMode
                                ? AppColors.accent
                                : AppColors.border),
                      ),
                    ),
                  ),
                  if (_wallMode && _chainOpen)
                    FilledButton.tonalIcon(
                      key: const ValueKey('planner-finish-wall'),
                      onPressed: _finishInteriorWall,
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text('Finish wall'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 12),
                        minimumSize: Size.zero,
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: (_furniture.isEmpty &&
                            _walls.isEmpty &&
                            _interior.isEmpty)
                        ? null
                        : _confirmClearAll,
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Clear'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 12),
                      minimumSize: Size.zero,
                    ),
                  ),
                ],
              ),
              if (_wallMode) ...[
                const SizedBox(height: 6),
                Text(
                  _chainOpen
                      ? 'Tap to continue this wall · Finish wall to start another · drag a corner to adjust'
                      : 'Tap the floor to start an interior wall — each tap adds a corner. Long-press to clear walls.',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: AppColors.accent),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: bottomClearance),
          ],
        ),
      ],
    );
  }

  Widget _dimLabel(String text,
      {double? top, double? left, bool vertical = false}) {
    final child = IgnorePointer(
      child: Container(
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
      ),
    );
    return Positioned(
      top: top,
      left: left,
      child: vertical
          ? RotatedBox(quarterTurns: 3, child: child)
          : child,
    );
  }

  // ─── Static 3D fallback (unsupported platforms) ───
  // Never spins — the planner room must not auto-rotate.

  Widget _fallbackPreview() => PlanPreview3D(
        design: _snapshotDesign(),
        finishes: _previewFinishes,
        spin: false,
      );

  // Zoom = dolly the orbit camera toward / away from the room center; the
  // expand toggle gives the 3D view the whole screen.
  void _zoomBy(double factor) {
    _rig.dolly(factor);
    _pushCamera();
  }

  Widget _roundSceneButton({
    required Key key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.92),
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          key: key,
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, size: 20, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }

  Widget _zoomControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _roundSceneButton(
          key: const ValueKey('planner-expand'),
          icon: _sceneExpanded ? Icons.fullscreen_exit : Icons.fullscreen,
          tooltip: _sceneExpanded ? 'Exit full view' : 'Full view',
          onTap: () => setState(() => _sceneExpanded = !_sceneExpanded),
        ),
        const SizedBox(height: 10),
        _roundSceneButton(
          key: const ValueKey('planner-zoom-in'),
          icon: Icons.add,
          tooltip: 'Zoom in',
          onTap: () => _zoomBy(0.8),
        ),
        const SizedBox(height: 8),
        _roundSceneButton(
          key: const ValueKey('planner-zoom-out'),
          icon: Icons.remove,
          tooltip: 'Zoom out',
          onTap: () => _zoomBy(1.25),
        ),
      ],
    );
  }

  Widget _cameraResetButton() {
    return GestureDetector(
      key: const ValueKey('planner-camera-reset'),
      onTap: () {
        _reframeRig();
        _pushCamera();
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(Icons.filter_center_focus,
            size: 16, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _selectionThumb(FurniturePlacement item) {
    final path = _imagePathOf(item);
    final fallback = Container(
      color: AppColors.accent.withValues(alpha: 0.08),
      child: Icon(_iconFor(item.iconName), size: 18, color: AppColors.accent),
    );
    final url = item.imageUrl;
    if (url != null && url.startsWith('http')) {
      return Image.network(url,
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback);
    }
    if (path == null) return fallback;
    return Image.asset(
      path,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  FinishSelection? get _previewFinishes {
    if (_floorFinishType == null && _wallFinishType == null) return null;
    return finishSelectionFrom(_snapshotDesign());
  }

  // ─── Photo catalogue panel (Homestyler-style) ───

  String _catLabel(String category) => category == 'All'
      ? 'All'
      : category[0].toUpperCase() + category.substring(1);

  static const _marketCategory = 'Marketplace';

  // Live marketplace products with a ready 3D model sit first under "All" and
  // in their own tab; they place at the seller's size with their own GLB.
  Widget _catalogPanel() {
    final market = ref.watch(marketplace3dProductsProvider);
    final categories = <String>[
      'All',
      if (market.isNotEmpty) _marketCategory,
      ...{for (final c in _catalog) c.category},
    ];
    if (!categories.contains(_catalogCategory)) _catalogCategory = 'All';
    final tiles = <Widget>[
      if (_catalogCategory == 'All' || _catalogCategory == _marketCategory)
        for (final p in market) _productTile(p),
      if (_catalogCategory != _marketCategory)
        for (final c in _catalog)
          if (_catalogCategory == 'All' || c.category == _catalogCategory)
            _photoTile(c),
    ];
    return Container(
      key: const ValueKey('planner-catalog-panel'),
      padding: const EdgeInsets.fromLTRB(16, 6, 0, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilterChipBar<String>(
            options: categories,
            selected: _catalogCategory,
            labelBuilder: _catLabel,
            onSelected: (c) => setState(() => _catalogCategory = c),
          ),
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 16),
              itemCount: tiles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => tiles[i],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoTile(_Cat cat) {
    return GestureDetector(
      key: ValueKey('catalog-tile-${cat.iconName}'),
      onTap: () => _addFromCatalog(cat),
      child: SizedBox(
        width: 84,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _CatalogThumb(cat: cat),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              cat.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _productTile(Product p) {
    final dims = p.dimensions;
    return GestureDetector(
      key: ValueKey('catalog-product-${p.id}'),
      onTap: () => _addFromProduct(p),
      child: SizedBox(
        width: 84,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.accent),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: p.image.isEmpty
                          ? Icon(_iconFor(iconNameForProduct(p)),
                              color: AppColors.accent)
                          : Image.network(
                              p.image,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                  _iconFor(iconNameForProduct(p)),
                                  color: AppColors.accent),
                            ),
                    ),
                  ),
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.view_in_ar,
                          size: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              p.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            Text(
              dims == null
                  ? Formatters.myr(p.price)
                  : '${Formatters.myr(p.price)} · ${(dims.widthM * 100).round()}×${(dims.depthM * 100).round()}',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 9, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  void _addFromProduct(Product product) {
    final item = placementForProduct(product,
            id: _nextPieceId('market-${product.id}'))
        .copyWith(x: 20, y: 15);
    final fitted = _fitInRoom(item);
    if (fitted == null) {
      showAppSnackbar(
          context,
          '${item.name} (${_sizeLabel(item)}) is bigger than this room '
          '(${_roomW.toInt()}×${_roomH.toInt()} cm).',
          isError: true);
      return;
    }
    setState(() {
      _furniture.add(fitted);
      _selectedIdx = _furniture.length - 1;
    });
    _bridge.syncFurniture(_furniture);
  }

  @visibleForTesting
  void debugAddFromProduct(Product p) => _addFromProduct(p);

  // ─── Icon lookup ───
}

IconData _iconFor(String iconName) {
  for (final c in _RoomScannerScreenState._catalog) {
    if (c.iconName == iconName) return c.icon;
  }
  return Icons.folder;
}

String? _imagePathOf(FurniturePlacement item) {
  final direct = item.imageAsset;
  if (direct != null && direct.isNotEmpty) return direct;
  for (final c in _RoomScannerScreenState._catalog) {
    if (c.iconName == item.iconName && c.imageAsset != null) {
      return c.imageAsset;
    }
  }
  return null;
}

// ─── Precise furniture size dialog ───
// Owns its controllers so the exit animation can still rebuild the fields;
// disposing them the moment the future completes would crash that rebuild.
class _SizeDialog extends StatefulWidget {
  const _SizeDialog({required this.item, required this.cat});

  final FurniturePlacement item;
  final _Cat? cat;

  @override
  State<_SizeDialog> createState() => _SizeDialogState();
}

class _SizeDialogState extends State<_SizeDialog> {
  late final TextEditingController _wCtrl;
  late final TextEditingController _hCtrl;
  String _error = '';

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : '$v';

  @override
  void initState() {
    super.initState();
    _wCtrl = TextEditingController(text: _fmt(widget.item.width));
    _hCtrl = TextEditingController(text: _fmt(widget.item.height));
  }

  @override
  void dispose() {
    _wCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  void _apply() {
    final w = double.tryParse(_wCtrl.text.trim());
    final h = double.tryParse(_hCtrl.text.trim());
    if (w == null || h == null || w < 20 || h < 20 || w > 500 || h > 500) {
      setState(() => _error = 'Must be 20–500 cm');
      return;
    }
    Navigator.pop(context, (w: w, h: h));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Size — ${widget.item.name}'),
      content: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _wCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Width (cm)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _hCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Height (cm)',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: widget.cat == null
                    ? null
                    : () {
                        setState(() {
                          _wCtrl.text = _fmt(widget.cat!.defaultWidth);
                          _hCtrl.text = _fmt(widget.cat!.defaultHeight);
                          _error = '';
                        });
                      },
                child: const Text('Catalog default'),
              ),
            ),
            if (_error.isNotEmpty)
              Text(
                _error,
                style:
                    GoogleFonts.poppins(fontSize: 12, color: AppColors.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _apply,
          style: ElevatedButton.styleFrom(minimumSize: Size.zero),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

// ─── Catalog item ───
class _CatalogThumb extends StatelessWidget {
  const _CatalogThumb({required this.cat});

  final _Cat cat;

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

// ─── Selected piece wireframe ───
class _SelectionBoxPainter extends CustomPainter {
  _SelectionBoxPainter({
    required this.pose,
    required this.viewport,
    required this.item,
    required this.heightM,
  });

  final ScenePose pose;
  final Size viewport;
  final FurniturePlacement item;
  final double heightM;

  @override
  void paint(Canvas canvas, Size size) {
    final fw = footprintW(item) / 100;
    final fh = footprintH(item) / 100;
    final x0 = item.x / 100;
    final z0 = item.y / 100;
    final base = (item.elevationCm ?? 0) / 100;
    final pts = <Offset?>[
      for (final y in [base, base + heightM])
        for (final xz in [
          [x0, z0],
          [x0 + fw, z0],
          [x0 + fw, z0 + fh],
          [x0, z0 + fh],
        ])
          projectWorldPoint(pose, viewport, xz[0], y, xz[1]),
    ];
    final paint = Paint()
      ..color = const Color(0xFF2D6CDF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    void edge(int a, int b) {
      final p1 = pts[a];
      final p2 = pts[b];
      if (p1 != null && p2 != null) canvas.drawLine(p1, p2, paint);
    }

    for (var i = 0; i < 4; i++) {
      edge(i, (i + 1) % 4);
      edge(4 + i, 4 + (i + 1) % 4);
      edge(i, 4 + i);
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionBoxPainter old) =>
      old.item != item ||
      old.heightM != heightM ||
      old.viewport != viewport ||
      old.pose.eyeX != pose.eyeX ||
      old.pose.eyeY != pose.eyeY ||
      old.pose.eyeZ != pose.eyeZ ||
      old.pose.targetX != pose.targetX ||
      old.pose.targetY != pose.targetY ||
      old.pose.targetZ != pose.targetZ ||
      old.pose.fovDeg != pose.fovDeg;
}

// ─── Data classes ───
class _Found {
  final String label;
  final double confidence;
  const _Found({required this.label, required this.confidence});
}

// Selection bar + catalogue + toolbar. Normally they lay out at natural
// height; on short screens they scroll inside a capped box so the 3D scene
// above keeps a usable height and its own gestures.
class _BottomPanels extends StatelessWidget {
  const _BottomPanels(
      {required this.compact, required this.maxHeight, required this.children});

  final bool compact;
  final double maxHeight;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final column = Column(mainAxisSize: MainAxisSize.min, children: children);
    if (!compact) return column;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(child: column),
    );
  }
}
