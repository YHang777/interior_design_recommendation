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
import '../../../../../core/utils/user_errors.dart';
import '../../../../../models/room_design.dart';
import '../../../../../shared/widgets/app_feedback.dart';
import '../../../../../shared/widgets/catalog_picker_sheet.dart';
import '../../../../../shared/widgets/float_button.dart';
import '../../../ar/data/furniture_model_library.dart';
import '../../../homeowner/presentation/providers/design_providers.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';

class RoomScannerScreen extends ConsumerStatefulWidget {
  const RoomScannerScreen({super.key, this.existingDesign});
  final RoomDesign? existingDesign;

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
  String _roomType = 'living_room';

  late List<FurniturePlacement> _furniture;
  double _roomW = 400;
  double _roomH = 500;
  int _selectedIdx = -1;
  bool _isEditingDimensions = false;
  final _widthCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  @visibleForTesting
  List<Offset> get debugWalls => List.of(_walls);

  @visibleForTesting
  List<FurniturePlacement> get debugFurniture => List.of(_furniture);

  @visibleForTesting
  int debugAutoPlace(List<String> labels) {
    _found
      ..clear()
      ..addAll([for (final l in labels) _Found(label: l, confidence: 0.9)]);
    return _autoPlaceFound();
  }

  final List<Offset> _walls = [];
  final ValueNotifier<int> _wallsRev = ValueNotifier(0);
  bool _wallMode = false;
  int _draggingWallIdx = -1;

  void _touchWalls() => _wallsRev.value++;

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
    _walls.addAll(widget.existingDesign?.walls ?? const []);
    if (widget.existingDesign != null) {
      _roomW = widget.existingDesign!.widthCm;
      _roomH = widget.existingDesign!.heightCm;
      _roomType = widget.existingDesign!.roomType;
      _found.addAll(widget.existingDesign!.detectedItems
          .map((l) => _Found(label: l, confidence: 0.9)));
      _stage = _Stage.plan;
    } else {
      _stage = _Stage.plan;
    }

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
    for (final p in placements) {
      final maxX = max(1.0, _roomW - p.width);
      final maxY = max(1.0, _roomH - p.height);
      final x = (20.0 + (slot % 3) * 110.0)
          .clamp(5.0, max(5.0, maxX - 5))
          .toDouble();
      final y = (40.0 + ((slot ~/ 3) % 3) * 130.0)
          .clamp(5.0, max(5.0, maxY - 5))
          .toDouble();
      added.add(p.copyWith(x: x, y: y));
      slot++;
    }
    if (!mounted) return;
    setState(() => _furniture = [..._furniture, ...added]);
  }

  Future<void> _setupCam() async {
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
    final guessed =
        widget.existingDesign == null ? _guessRoomType() : null;
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
    WidgetsBinding.instance.endOfFrame.whenComplete(_releaseCam);
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
      item = _resolveDrop(item);
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

  double _footprintW(FurniturePlacement f) =>
      f.rotation % 180 == 90 ? f.height : f.width;
  double _footprintH(FurniturePlacement f) =>
      f.rotation % 180 == 90 ? f.width : f.height;

  bool _pointInPolygon(Offset p) {
    if (_walls.length < 3) return true;
    // Boundary counts as inside — pure ray-casting reports points
    // exactly on a wall as outside, which would ban flush placement.
    for (int i = 0, j = _walls.length - 1; i < _walls.length; j = i++) {
      if (_distToSegment(p, _walls[i], _walls[j]) < 0.5) return true;
    }
    var inside = false;
    for (int i = 0, j = _walls.length - 1; i < _walls.length; j = i++) {
      final a = _walls[i];
      final b = _walls[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2)
        .clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
    return (p - proj).distance;
  }

  // ─── Drop resolution ───
  // A drop is valid when the footprint sits inside the room rectangle and,
  // if walls outline a polygon, fully inside it (all four corners in the
  // polygon AND no wall edge slicing through the footprint — the corner
  // test alone fails for concave outlines).

  bool _fitsAt(FurniturePlacement f, Offset tl) {
    final fw = _footprintW(f);
    final fh = _footprintH(f);
    if (tl.dx < 0 || tl.dy < 0) return false;
    if (tl.dx + fw > _roomW || tl.dy + fh > _roomH) return false;
    if (_walls.length < 3) return true;

    final corners = [
      tl,
      tl + Offset(fw, 0),
      tl + Offset(0, fh),
      tl + Offset(fw, fh),
    ];
    for (final c in corners) {
      if (!_pointInPolygon(c)) return false;
    }
    for (var i = 0; i < _walls.length; i++) {
      final a1 = _walls[i];
      final a2 = _walls[(i + 1) % _walls.length];
      if (_segmentsCross(a1, a2, corners[0], corners[1]) ||
          _segmentsCross(a1, a2, corners[1], corners[3]) ||
          _segmentsCross(a1, a2, corners[3], corners[2]) ||
          _segmentsCross(a1, a2, corners[2], corners[0])) {
        return false;
      }
    }
    return true;
  }

  bool _segmentsCross(Offset p1, Offset p2, Offset q1, Offset q2) {
    double cross(Offset a, Offset b, Offset c) =>
        (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
    final d1 = cross(q1, q2, p1);
    final d2 = cross(q1, q2, p2);
    final d3 = cross(p1, p2, q1);
    final d4 = cross(p1, p2, q2);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }

  FurniturePlacement _resolveDrop(FurniturePlacement f) {
    if (_fitsAt(f, Offset(f.x, f.y))) return f;
    final fw = _footprintW(f);
    final fh = _footprintH(f);
    final maxX = max(0.0, _roomW - fw);
    final maxY = max(0.0, _roomH - fh);

    // Walk rings outward from the drop point (5 cm steps, 16 angles)
    // and take the first spot that fits — the piece settles next to
    // where the finger left it, never teleports to the room center.
    final maxR = sqrt(_roomW * _roomW + _roomH * _roomH);
    for (var r = 5.0; r <= maxR; r += 5.0) {
      final steps = 16;
      for (var i = 0; i < steps; i++) {
        final a = 2 * pi * i / steps;
        final cand = Offset(
          (f.x + cos(a) * r).clamp(0.0, maxX).toDouble(),
          (f.y + sin(a) * r).clamp(0.0, maxY).toDouble(),
        );
        if (_fitsAt(f, cand)) return f.copyWith(x: cand.dx, y: cand.dy);
      }
    }
    return f;
  }

  // ─── Raw pointer interactions (canvas pixels → room cm) ───

  bool _pointerMoved = false;
  bool _pointerOnTile = false;

  Timer? _wallHoldTimer;
  Offset? _wallHoldOrigin;

  void _startWallHold(Offset globalPos) {
    _wallHoldTimer?.cancel();
    _wallHoldOrigin = globalPos;
    _wallHoldTimer = Timer(const Duration(milliseconds: 550), () {
      _wallHoldTimer = null;
      _wallHoldOrigin = null;
      if (!mounted || _walls.isEmpty) return;
      // Block the tap-up that follows — otherwise a wall-mode tap
      // would drop a corner right where the outline was cleared.
      _pointerMoved = true;
      _clearWalls();
    });
  }

  void _cancelWallHold() {
    _wallHoldTimer?.cancel();
    _wallHoldTimer = null;
    _wallHoldOrigin = null;
  }

  void _onPointerDown(PointerDownEvent e, double s) {
    _pointerMoved = false;
    _pointerOnTile = false;

    final p = Offset(e.localPosition.dx / s, e.localPosition.dy / s);

    for (final f in _furniture) {
      final fw = _footprintW(f);
      final fh = _footprintH(f);
      if (p.dx >= f.x &&
          p.dx <= f.x + fw &&
          p.dy >= f.y &&
          p.dy <= f.y + fh) {
        _pointerOnTile = true;
        break;
      }
    }

    _draggingWallIdx = -1;
    // Never grab a wall corner when the press started on furniture —
    // otherwise the corner chases the tile and the piece looks glued
    // to the wall no matter how far it is dragged.
    if (!_pointerOnTile && _walls.isNotEmpty) {
      int? best;
      var bestDist = double.infinity;
      for (var i = 0; i < _walls.length; i++) {
        final d = (_walls[i] - p).distance;
        if (d < bestDist) {
          bestDist = d;
          best = i;
        }
      }
      final grabRadius = 28 / s;
      if (best != null && bestDist <= grabRadius) {
        _draggingWallIdx = best;
        _startWallHold(e.position);
        return;
      }
      // Long-press anywhere on the outline itself clears it.
      for (var i = 0; i < _walls.length; i++) {
        final a = _walls[i];
        final b = _walls[(i + 1) % _walls.length];
        if (_distToSegment(p, a, b) < 8 / s) {
          _startWallHold(e.position);
          break;
        }
      }
    }
  }

  void _onPointerMove(PointerMoveEvent e, double s) {
    _pointerMoved = true;

    final holdOrigin = _wallHoldOrigin;
    if (holdOrigin != null && (e.position - holdOrigin).distance > 8) {
      _cancelWallHold();
    }

    if (_draggingWallIdx >= 0 && _draggingWallIdx < _walls.length) {
      final p = Offset(
        (e.localPosition.dx / s).clamp(0.0, _roomW).toDouble(),
        (e.localPosition.dy / s).clamp(0.0, _roomH).toDouble(),
      );
      _walls[_draggingWallIdx] = p;
      _touchWalls();
    }
  }

  void _onPointerUp(PointerUpEvent e, double s) {
    _cancelWallHold();
    if (!_pointerMoved && _draggingWallIdx < 0 && !_pointerOnTile) {
      final p = Offset(
        (e.localPosition.dx / s).clamp(0.0, _roomW).toDouble(),
        (e.localPosition.dy / s).clamp(0.0, _roomH).toDouble(),
      );
      if (_wallMode) {
        final tooClose = _walls.any((w) => (w - p).distance < 12);
        if (!tooClose) {
          setState(() => _walls.add(p));
          _touchWalls();
        }
      } else {
        setState(() => _selectedIdx = -1);
      }
    }
    _draggingWallIdx = -1;
    _pointerOnTile = false;
  }

  void _clearWalls() {
    if (_walls.isEmpty) return;
    final snapshot = List<Offset>.of(_walls);
    setState(() {
      _walls.clear();
      _draggingWallIdx = -1;
    });
    _touchWalls();
    if (!mounted) return;
    showAppSnackbar(
      context,
      'Walls cleared',
      duration: const Duration(seconds: 4),
      actionLabel: 'Undo',
      onAction: () {
        if (!mounted || _walls.isNotEmpty) return;
        setState(() => _walls.addAll(snapshot));
        _touchWalls();
      },
    );
  }

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
    showAppSnackbar(
      context,
      '${removed.name} removed',
      duration: const Duration(seconds: 4),
      actionLabel: 'Undo',
      onAction: () {
        if (!mounted || idx > _furniture.length) return;
        setState(() => _furniture.insert(idx, removed));
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
    setState(() {
      _furniture.clear();
      _walls.clear();
      _selectedIdx = -1;
      _draggingWallIdx = -1;
    });
    if (walls.isNotEmpty) _touchWalls();
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
        });
        if (walls.isNotEmpty) _touchWalls();
      },
    );
  }

  void _rotateSelected() {
    if (_selectedIdx < 0 || _selectedIdx >= _furniture.length) return;
    setState(() {
      final f = _furniture[_selectedIdx];
      _furniture[_selectedIdx] =
          f.copyWith(rotation: (f.rotation + 90) % 360);
    });
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
        DateTime.now().microsecondsSinceEpoch.toString();
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
    item = _resolveDrop(item);
    setState(() => _furniture.add(item));
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
        text: widget.existingDesign?.name ?? 'My $_roomTypeLabel Design');

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
    final designId = widget.existingDesign?.id ??
        'design-${now.millisecondsSinceEpoch}';

    final design = RoomDesign(
      id: designId,
      name: name,
      roomType: _roomType,
      widthCm: _roomW,
      heightCm: _roomH,
      furniture: _furniture,
      walls: List.of(_walls),
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
    _wallHoldTimer?.cancel();
    try {
      _cam?.stopImageStream();
    } catch (_) {}
    _labeler.close();
    try {
      _cam?.dispose();
    } catch (_) {}
    _wallsRev.dispose();
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
                          _Stage.plan => widget.existingDesign != null
                              ? 'Edit: ${widget.existingDesign!.name}'
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
                        onPressed: () => context.push(
                          '/ar-viewer',
                          extra: ArFurnitureLibrary.fromIconNames(
                              _furniture.map((f) => f.iconName).toList()),
                        ),
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
    final bottomClearance = MediaQuery.paddingOf(context).bottom + 8;
    return Column(
      children: [
        if (_furniture.isEmpty && widget.existingDesign == null)
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
                        onTap: () => setState(() {
                          _roomW = p.$2.toDouble();
                          _roomH = p.$3.toDouble();
                        }),
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
            padding: const EdgeInsets.all(16),
            child: Center(
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  const border = 3.0;
                  final maxW = constraints.maxWidth - border * 2;
                  final maxH = constraints.maxHeight - border * 2;
                  final roomAspect = _roomW / _roomH;
                  double canvasW, canvasH;
                  if (maxW / maxH > roomAspect) {
                    canvasH = maxH;
                    canvasW = canvasH * roomAspect;
                  } else {
                    canvasW = maxW;
                    canvasH = canvasW / roomAspect;
                  }
                  final s = min(canvasW / _roomW, canvasH / _roomH);
                  return SizedBox(
                    width: canvasW + border * 2,
                    height: canvasH + border * 2,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBF5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: AppColors.primary, width: border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (e) => _onPointerDown(e, s),
                        onPointerMove: (e) => _onPointerMove(e, s),
                        onPointerUp: (e) => _onPointerUp(e, s),
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            RepaintBoundary(
                              child: CustomPaint(
                                painter:
                                    _FloorPlanGridPainter(
                                        s, _roomW, _roomH),
                                size: Size.infinite,
                              ),
                            ),
                            RepaintBoundary(
                              child: ValueListenableBuilder<int>(
                                valueListenable: _wallsRev,
                                builder: (_, __, ___) => CustomPaint(
                                  painter: _RoomShapePainter(s, _walls,
                                      _wallMode, _wallsRev.value),
                                  size: Size.infinite,
                                ),
                              ),
                            ),
                          _dimLabel('${_roomW.toInt()} cm',
                              top: 4,
                              left: canvasW / 2 - 30),
                          _dimLabel('${_roomH.toInt()} cm',
                              left: 4,
                              top: canvasH / 2 - 10,
                              vertical: true),
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
                                    color: AppColors.primary
                                        .withValues(alpha: 0.75),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _roomTypeLabel,
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                          Icons.arrow_drop_down,
                                          size: 14,
                                          color: Colors.white),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          for (var i = 0; i < _furniture.length; i++)
                            _FurnitureTile(
                              key: ValueKey(_furniture[i].id),
                              item: _furniture[i],
                              selected: i == _selectedIdx,
                              scale: s,
                              roomW: _roomW,
                              roomH: _roomH,
                              onTap: () =>
                                  setState(() => _selectedIdx = i),
                              onLongPress: () => _removeFurniture(i),
                              onCommit: (moved) {
                                setState(() {
                                  final idx = _furniture
                                      .indexWhere((e) => e.id == moved.id);
                                  if (idx < 0) return;
                                  _furniture[idx] = _resolveDrop(moved);
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        if (_selectedIdx >= 0 &&
            _selectedIdx < _furniture.length)
          Container(
            key: const ValueKey('planner-selection-bar'),
            padding: const EdgeInsets.fromLTRB(
                16, 6, 8, 2),
            color: AppColors.surface,
            child: Row(
              children: [
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
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _openFurniturePicker,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(
                        _furniture.isEmpty
                            ? 'Add furniture'
                            : 'Add furniture · ${_furniture.length} placed',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onLongPress: _walls.isEmpty ? null : _clearWalls,
                    child: OutlinedButton.icon(
                      onPressed: () => setState(
                          () => _wallMode = !_wallMode),
                      icon: Icon(
                        _wallMode ? Icons.polyline : Icons.polyline_outlined,
                        size: 18,
                      ),
                      label: Text(_wallMode ? 'Add Corners' : 'Walls'),
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
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: (_furniture.isEmpty && _walls.isEmpty)
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
                  _walls.length < 3
                      ? 'Tap the plan to add wall corners — at least 3 outline your room.'
                      : 'Tap to add corners · drag a corner to adjust · long-press the outline to clear',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: AppColors.accent),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: bottomClearance),
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
}

IconData _iconFor(String iconName) {
  for (final c in _RoomScannerScreenState._catalog) {
    if (c.iconName == iconName) return c.icon;
  }
  return Icons.folder;
}

// ─── Draggable furniture tile ───
class _FurnitureTile extends StatefulWidget {
  const _FurnitureTile({
    super.key,
    required this.item,
    required this.selected,
    required this.scale,
    required this.roomW,
    required this.roomH,
    required this.onTap,
    required this.onLongPress,
    required this.onCommit,
  });

  final FurniturePlacement item;
  final bool selected;
  final double scale;
  final double roomW;
  final double roomH;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  final ValueChanged<FurniturePlacement> onCommit;

  @override
  State<_FurnitureTile> createState() => _FurnitureTileState();
}

class _FurnitureTileState extends State<_FurnitureTile> {
  Offset? _live;

  Offset get _pos => _live ?? Offset(widget.item.x, widget.item.y);

  bool get _swapped => widget.item.rotation % 180 == 90;
  double get _boxW => _swapped ? widget.item.height : widget.item.width;
  double get _boxH => _swapped ? widget.item.width : widget.item.height;

  double get _maxX => widget.roomW - _boxW;
  double get _maxY => widget.roomH - _boxH;

  void _onPanStart(DragStartDetails _) {
    setState(() => _live = Offset(widget.item.x, widget.item.y));
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final s = widget.scale;
    final p = _pos;
    setState(() {
      _live = Offset(
        (p.dx + d.delta.dx / s).clamp(0.0, _maxX).toDouble(),
        (p.dy + d.delta.dy / s).clamp(0.0, _maxY).toDouble(),
      );
    });
  }

  void _onPanEnd(DragEndDetails _) {
    final p = _pos;
    setState(() => _live = null);
    widget.onCommit(widget.item.copyWith(x: p.dx, y: p.dy));
  }

  void _onPanCancel() {
    final p = _pos;
    setState(() => _live = null);
    widget.onCommit(widget.item.copyWith(x: p.dx, y: p.dy));
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final s = widget.scale;
    final p = _pos;
    final boxW = _boxW * s;
    final boxH = _boxH * s;
    final itemW = item.width * s;
    final itemH = item.height * s;
    final isSelected = widget.selected;
    final icon = _iconFor(item.iconName);

    return Positioned(
      left: p.dx * s,
      top: p.dy * s,
      child: RepaintBoundary(
        child: SizedBox(
          width: boxW,
          height: boxH,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            onPanCancel: _onPanCancel,
            child: Center(
              child: Transform.rotate(
                angle: item.rotation * pi / 180,
                child: Container(
                  width: itemW,
                  height: itemH,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.accent.withValues(alpha: 0.3)
                        : AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.accent
                          : AppColors.primary.withValues(alpha: 0.4),
                      width: isSelected ? 2.5 : 1.2,
                    ),
                  ),
                  child: itemW > 40 && itemH > 30
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              size: min(itemW * 0.35, 20),
                              color: isSelected
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                            ),
                            if (itemW > 55)
                              SizedBox(
                                width: itemW - 4,
                                child: Text(
                                  item.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontSize: min(itemW * 0.1, 10)
                                        .clamp(6, 10)
                                        .toDouble(),
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
                            icon,
                            size: min(itemW * 0.5, 14),
                            color: isSelected
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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

class _CatalogThumb extends StatelessWidget {
  const _CatalogThumb({required this.cat});

  final _Cat cat;

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

// ─── Room shape (walls) painter ───
class _RoomShapePainter extends CustomPainter {
  _RoomShapePainter(this.scale, this.walls, this.wallMode, this.revision);

  final double scale;
  final List<Offset> walls;
  final bool wallMode;

  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    Path path() {
      final p = Path()
        ..moveTo(walls.first.dx * scale, walls.first.dy * scale);
      for (final w in walls.skip(1)) {
        p.lineTo(w.dx * scale, w.dy * scale);
      }
      p.close();
      return p;
    }

    if (walls.length >= 3) {
      final shape = path();
      canvas.drawPath(
          shape, Paint()..color = const Color(0xFFF5EDDE));
      // Dim everything outside the outline — the drop zone reads at a glance.
      final outside = Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        shape,
      );
      canvas.drawPath(
          outside,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.07));
      canvas.drawPath(
          shape,
          Paint()
            ..color = const Color(0xFF8D6E63)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.round);
    } else if (wallMode && walls.length >= 2) {
      final line = Path()
        ..moveTo(walls.first.dx * scale, walls.first.dy * scale);
      for (final w in walls.skip(1)) {
        line.lineTo(w.dx * scale, w.dy * scale);
      }
      canvas.drawPath(
          line,
          Paint()
            ..color = AppColors.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round);
    }

    if (wallMode) {
      for (final w in walls) {
        canvas.drawCircle(Offset(w.dx * scale, w.dy * scale), 6,
            Paint()..color = AppColors.accent);
        canvas.drawCircle(Offset(w.dx * scale, w.dy * scale), 2.5,
            Paint()..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoomShapePainter old) =>
      old.scale != scale ||
      old.wallMode != wallMode ||
      old.revision != revision;
}

// ─── Floor plan grid painter ───
class _FloorPlanGridPainter extends CustomPainter {
  _FloorPlanGridPainter(this.scale, this.roomW, this.roomH);
  final double scale;
  final double roomW;
  final double roomH;

  @override
  void paint(Canvas canvas, Size size) {
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
