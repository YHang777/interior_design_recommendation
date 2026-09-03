import 'dart:async';
import 'dart:math' as math;

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
import '../../../../core/constants/app_colors.dart';
import '../../../../models/product.dart';
import '../../../../services/model_generation/model_glb_resolver.dart';
import '../../data/ar_product_entry.dart';
import '../../data/furniture_model_library.dart';
import '../../data/glb_bounds.dart';
import '../../data/glb_file_saver.dart';
import '../../data/glb_generator.dart';
import '../../data/room_finishes.dart';

/// A furniture item placed in the AR scene, tracked for cleanup/removal.
class _PlacedItem {
  const _PlacedItem(this.label, this.node, this.anchor);

  /// Display name of the placed model (product name or library item name).
  final String label;
  final ARNode node;
  final ARAnchor anchor;
}

/// A floor / wall finish armed for placement (Room mode): the GLB is
/// generated and saved the moment the user presses "Place floor/wall", so
/// every following surface tap can place it instantly without regenerating.
class _PendingFinish {
  const _PendingFinish({
    required this.kindWord,
    required this.label,
    required this.nodeName,
    required this.filePath,
    required this.scaleMeters,
  });

  /// Lower-case surface word for hints: 'floor' or 'wall'.
  final String kindWord;

  /// Display label, e.g. 'Oak Wood Floor' or 'Navy Paint Wall'.
  final String label;

  /// ARNode name ('floor_typecolor' shape, e.g. floor_woodplanks_ffb08d6b),
  /// used by tap-to-remove matching.
  final String nodeName;

  /// Absolute path of the generated finish GLB (already on disk).
  final String filePath;

  /// Plugin scale-to-unit-cube: the model's MAX extent in meters (floor side
  /// length for floors, panel height 2.7 for walls) so the mesh renders 1:1.
  final double scaleMeters;
}

/// One slot of the catalog bar: either a bundled library model or — when
/// the screen was opened for a [Product] — that product's true-size 3D
/// model. A product slot's [ArProductEntry] starts without a file and gains
/// one once background resolution materializes the GLB on disk.
class _BarEntry {
  _BarEntry.library(this.item) : product = null;

  _BarEntry.product(this.product) : item = null;

  final ArFurnitureItem? item;

  /// Null while the entry is a plain library model; the product entry's
  /// [ArProductEntry.resolvedFile] appears once its GLB is ready.
  ArProductEntry? product;

  bool get isProduct => product != null;

  String get name => isProduct ? product!.name : item!.name;

  /// Whether this slot can currently be placed: library models always can;
  /// a product slot only once its true-size GLB has been resolved.
  bool get placeable => !isProduct || product!.isResolved;
}

/// Real AR furniture viewer.
///
/// Renders the live camera feed with ARCore (SceneView/Filament on Android),
/// detects surfaces, and lets the user tap to place 3D furniture models.
/// Placed models can be dragged (pan), rotated (two-finger twist) and
/// removed. The catalog bar at the bottom lists the models for the design /
/// product this screen was opened from.
///
/// Two entry modes:
///  * [product] mode (marketplace) — resolves the product's own true-size
///    GLB (via [ModelGlbResolver]) into the leading catalog slot and places
///    it at its real W×H×D dimensions. When no true-size model exists it
///    falls back to the bundled category model (old behavior) or, if the
///    product has no category, to the plain catalog.
///  * [items] / plain mode (room plans, scanner) — the bundled library
///    models, exactly as before.
///
/// Before showing the AR view, the screen checks that Google Play Services
/// for AR (ARCore) is installed on the device — otherwise the user gets a
/// helpful install screen instead of a frozen camera image.
class ArViewerScreen extends StatefulWidget {
  const ArViewerScreen({
    super.key,
    this.items,
    this.product,
    this.title = 'AR Preview',
  });

  /// Furniture catalog to offer. When null or empty, the full library is
  /// shown (a [product] slot, when present, is prepended).
  final List<ArFurnitureItem>? items;

  /// Optional product whose own true-size 3D model this viewer was opened
  /// for. When present its slot leads the catalog bar.
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

  /// Catalog bar entries, front to back. Built once in [initState]; the
  /// product slot (when present, at index 0) is updated in place when its
  /// GLB resolves, and on resolution failure the list is rebuilt to the
  /// fallback catalog.
  late final List<_BarEntry> _entries = _buildCatalog();

  int _selectedIndex = 0;

  final List<_PlacedItem> _placed = [];
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

  /// True while the true-size product / finish chip floats above the bottom
  /// bar (shown after a product model or a finish is placed; auto-dismissed
  /// after 8 s).
  bool _showPlacedChip = false;
  Timer? _chipTimer;

  /// Text shown in that chip. Null after a product placement (the product
  /// chip is then derived from the widget's product); non-null after a
  /// finish placement ('Placed …').
  String? _finishChipText;

  /// True once the AR session demonstrably RAN (planes detected, a node
  /// placed or tapped). Splits the AR-error overlay between "the session
  /// STOPPED — offer Close" and "AR never came up — offer the install CTA".
  bool _sessionWasLive = false;

  // ─── Room mode (floor / wall finishes) ───

  /// True when the bottom panel shows the Room (finish) panel instead of
  /// the furniture catalog.
  bool _roomMode = false;

  /// The full finish selection — the single Room state field. Every change
  /// flows through a [FinishSelection] select* transition (immutable value
  /// semantics, per-type color memory inside the model), and ANY change
  /// clears an armed [_pendingFinish] whose GLB would no longer match what
  /// the user has just picked.
  FinishSelection _selection = const FinishSelection();

  // Read-throughs so the panel rows read the selection uniformly.
  FloorFinishType get _floorType => _selection.floorType;
  WallFinishType get _wallType => _selection.wallType;
  double get _floorSizeM => _selection.floorSizeM;
  int get _floorColorArgb => _selection.floorColorArgb;
  int get _wallColorArgb => _selection.wallColorArgb;

  /// Finish armed for placement ('Place floor/wall' pressed). While set, the
  /// next surface tap places it; it stays active so the user can place
  /// several copies of the same finish, until the panel's Done (✕) clears it.
  _PendingFinish? _pendingFinish;

  /// True while a pressed Place action is generating + saving its GLB — ONE
  /// flag for floor and wall: only one finish can be armed at a time, and
  /// the two buttons never run concurrently.
  bool _arming = false;

  /// Moment the last "choose a finish first" snackbar was shown — surface
  /// taps repeat while nothing is armed, so the hint is throttled.
  DateTime? _lastNoFinishHintAt;

  /// Bottom panel height (furniture catalog vs Room finish panel). The
  /// floating overlays (delete button, chip, mode switcher) are anchored to
  /// it, so they keep clearing the bar in both modes.
  static const double _furnitureBarHeight = 108;
  // Room panel content (finish strips + captions + hint) is ~172 px tall at
  // the default text scale; the panel body scrolls vertically when system
  // text scaling pushes it beyond this fixed height.
  static const double _roomBarHeight = 184;
  double get _bottomBarHeight =>
      _roomMode ? _roomBarHeight : _furnitureBarHeight;

  _BarEntry? get _selectedEntry => (_entries.isEmpty ||
          _selectedIndex >= _entries.length)
      ? null
      : _entries[_selectedIndex];

  /// Catalog to offer. When [ArViewerScreen.items] is null or empty the full
  /// bundled library is used; a product (if any) always leads.
  List<_BarEntry> _buildCatalog() {
    final result = <_BarEntry>[];
    final product = widget.product;
    if (product != null) {
      result.add(_BarEntry.product(ArProductEntry(product: product)));
    }
    final items = (widget.items == null || widget.items!.isEmpty)
        ? ArFurnitureLibrary.all
        : widget.items!;
    for (final item in items) {
      result.add(_BarEntry.library(item));
    }
    return result;
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

  // ─── Product true-size mode ───

  /// Resolves the opened product's true-size GLB in the background (download
  /// + rescale, procedural generation, or a cache hit) and swaps it into the
  /// leading catalog slot once ready.
  ///
  /// On [No3dAvailableException] the screen falls back to the bundled
  /// category model — the pre-Loop-3 experience — and to the plain catalog
  /// (plus an explanatory message) when the product has no category either.
  Future<void> _resolveProductModel() async {
    final product = widget.product;
    if (product == null) return;

    final resolver = ModelGlbResolver();
    ResolvedGlb? resolved;
    try {
      resolved = await resolver.resolveProductGlb(product);
    } on No3dAvailableException {
      // Expected — the fallback paths below take over.
    } catch (_) {
      // Not expected (I/O trouble while writing the cache, …) — treat the
      // same as "no model available"; the screen still works with the
      // bundled catalog.
    } finally {
      resolver.dispose();
    }
    if (!mounted) return;

    final file = resolved?.file;
    if (file != null) {
      // The model is ready — swap the prepared slot for the real entry.
      setState(() {
        for (final entry in _entries) {
          if (entry.isProduct) {
            entry.product = ArProductEntry(
                product: product,
                resolvedFile: file,
                procedural: resolved?.procedural ?? true);
          }
        }
      });
      return;
    }

    // True-size 3D is unavailable. Prefer the bundled category model (the
    // exact catalog the marketplace passed before Loop 3)…
    final fallback = fallbackFor(product);
    if (fallback != null) {
      setState(() {
        _entries
          ..clear()
          ..add(_BarEntry.library(fallback));
        _selectedIndex = 0;
      });
      _showMessage('True-size 3D unavailable — showing a catalog model',
          color: AppColors.warning);
      return;
    }

    // …and when the product has no category either, keep the plain catalog.
    setState(() {
      _entries.removeWhere((e) => e.isProduct);
      if (_selectedIndex >= _entries.length) _selectedIndex = 0;
    });
    _showMessage(
      'No 3D model is available for this product yet. Add its real-world '
      'dimensions (or wait for the AI model) to view it in AR at true size.',
      color: AppColors.warning,
      duration: const Duration(seconds: 6),
    );
  }

  /// Floats the "placed at true size" / "placed finish" chip above the
  /// bottom bar for 8 s (dismissible by tapping it).
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

  /// Chip copy: a placed finish's "Placed …" text, or — in product mode —
  /// "Product Name · W 1.0 × H 1.5 × D 0.6 m" (name only when the product
  /// carries no dimensions). Null when there is nothing chip-worthy.
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
          _sessionWasLive = true;
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

  /// Places the selected furniture — or the armed finish, when one is
  /// pending (Room mode) — where the user tapped.
  /// Prefers a hit on a detected plane; falls back to a feature-point hit so
  /// furniture can still be placed while surface detection is warming up.
  Future<void> _onPlaneOrPointTap(List<ARHitTestResult> hits) async {
    if (_busy || hits.isEmpty) return;

    // With the AR session stopped the taps can never resolve to a real
    // surface — say so instead of silently doing nothing.
    if (_arError != null) {
      _showMessage('AR session stopped — close and reopen the viewer.',
          color: AppColors.warning);
      return;
    }

    // Room mode with an armed finish: the tap places that finish. Kept
    // active afterwards so multiple copies can be placed from one press.
    final pending = _pendingFinish;
    if (pending != null) {
      await _placePendingFinish(pending, hits);
      return;
    }
    // Room mode without an armed finish: nothing to place — the catalog
    // behind the panel is not what the user is interacting with. Say what
    // to do (throttled: surface taps repeat while nothing is armed).
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
      _showMessage('The 3D model is still preparing — try again in a moment.',
          color: AppColors.primaryLight);
      return;
    }

    _busy = true;
    try {
      final node = _buildNode(entry);
      final placed = await _placeNodeAtTap(
        hits,
        node,
        entry.name,
        failureMessage: 'Could not load the 3D model for ${entry.name}.',
      );
      if (placed == null) return;
      if (!mounted) return;
      setState(() {
        _placed.add(placed);
        _sessionWasLive = true;
        // The last placed thing names the chip: a product placement (or
        // another furniture item) supersedes an earlier finish chip.
        _finishChipText = null;
      });
      if (entry.isProduct) _showProductChip();
    } finally {
      _busy = false;
    }
  }

  /// SHARED anchor + node placement for every flow (furniture and finishes,
  /// fix 22): picks a plane hit (falling back to the first feature point),
  /// creates the anchor, adds the node and cleans up on failure. Returns the
  /// placed item — the caller records it in its own (mounted-guarded)
  /// setState, since only the caller knows the chip/label semantics.
  Future<_PlacedItem?> _placeNodeAtTap(
    List<ARHitTestResult> hits,
    ARNode node,
    String label, {
    String failureMessage = 'Could not place the item.',
  }) async {
    ARHitTestResult? hit;
    for (final h in hits) {
      if (h.type == ARHitTestResultType.plane) {
        hit = h;
        break;
      }
    }
    hit ??= hits.first;

    final anchor = ARPlaneAnchor(transformation: hit.worldTransform);
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

  /// Builds the [ARNode] for [entry] honoring the plugin's scale contract:
  /// `node.scale.x` is read as the scene's scale-to-unit-cube — the model's
  /// MAX extent is normalized to scale.x meters.
  ///
  ///  * Bundled library models are authored in arbitrary units — their
  ///    catalog `widthMeters` is passed as today.
  ///  * Product GLBs are authored/rescaled IN METERS with their max extent
  ///    equal to max(W,H,D) — passing that value as the scale makes the
  ///    internal factor 1.0, i.e. the model renders at its TRUE size.
  ///
  /// Geometry is pre-scaled and grounded (base on the tapped plane) — never
  /// per-axis scale or offsets here.
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
      );
    }
    final item = entry.item!;
    return ARNode(
      type: NodeType.localGLTF2,
      uri: item.uri,
      scale: Vector3.all(item.widthMeters),
      position: position,
      rotation: rotation,
    );
  }

  // ─── Room mode: floor / wall finish placement ───

  // ── FinishSelection behavior methods (fix 24): every selection change
  //    runs through the model's immutable select* transition, and any change
  //    invalidates an armed [_pendingFinish] — its GLB was generated for the
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
      // A pending finish belongs to the Room panel; leaving it while armed
      // would place finishes on later furniture taps.
      if (!room) _pendingFinish = null;
    });
  }

  void _cancelPendingFinish() {
    if (_pendingFinish == null) return;
    setState(() => _pendingFinish = null);
  }

  /// 'Place floor' — generates + saves the selected floor finish's GLB and
  /// arms it so the next surface tap places it.
  Future<void> _armFloorPlacement() =>
      _prepareFinishPlacement(isFloor: true);

  /// 'Place wall' — counterpart for the selected wall finish.
  Future<void> _armWallPlacement() => _prepareFinishPlacement(isFloor: false);

  /// Generates the GLB for the CURRENT finish selection (deterministic — the
  /// file name encodes type + color + size, so repeats overwrite the same
  /// cache file), saves it under app documents and arms [_pendingFinish].
  ///
  /// Generation + save happen here (on the button press) rather than on the
  /// AR tap, so placing several copies later is instant. Failures surface as
  /// a snackbar and nothing gets armed. ONE [_arming] flag covers floor and
  /// wall — the two Place buttons never run concurrently.
  ///
  /// Arming is GUARDED on completion (fix 9/10): the async save may outlive
  /// its context — if the screen was popped, the user left Room mode, or the
  /// selection changed while the file was being written, nothing is armed
  /// (later furniture taps must never place a finish the user no longer sees
  /// selected).
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

      // Scale contract: node scale.x = the mesh's MAX extent in meters. The
      // generator authors floors to sizeM and walls to wallHeightM, so the
      // parsed bounds equal those — parse to be robust, fall back to the
      // authored nominal value if parsing ever fails.
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
          'finish. $e');
    } finally {
      if (mounted) setState(() => _arming = false);
    }
  }

  /// Parses [bytes] and returns the mesh's max extent in meters, or null
  /// when the file cannot be parsed (bytes come from our own generator, so
  /// null is a defensive fallback only).
  double? _maxExtentMeters(Uint8List bytes) {
    try {
      final b = GlbBounds.fromGlbBytes(bytes);
      final m = math.max(b.widthM, math.max(b.heightM, b.depthM));
      return m.isFinite && m > 0 ? m : null;
    } catch (_) {
      return null;
    }
  }

  /// 'ffb08d6b'-style hex of [argb] for file/node names.
  static String _hexColor(int argb) => argb.toRadixString(16).padLeft(8, '0');

  /// '2' / '3' / '4' style size token (options are whole meters today).
  static String _sizeToken(double meters) =>
      meters == meters.roundToDouble()
          ? '${meters.round()}'
          : meters.toStringAsFixed(1);

  /// Places the armed finish at the tapped surface — through the shared
  /// [_placeNodeAtTap]. [_pendingFinish] stays active afterwards so several
  /// copies of the same finish can be placed; Done (✕) clears it.
  Future<void> _placePendingFinish(
      _PendingFinish pending, List<ARHitTestResult> hits) async {
    _busy = true;
    try {
      final node = ARNode(
        type: NodeType.fileSystemAppFolderGLB,
        uri: Uri.file(pending.filePath).toString(),
        scale: Vector3.all(pending.scaleMeters),
        name: pending.nodeName,
      );
      final placed = await _placeNodeAtTap(
        hits,
        node,
        pending.label,
        failureMessage: 'Could not load the ${pending.kindWord} finish.',
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
    setState(() {
      _selectedNodeName = nodeNames.first;
      _sessionWasLive = true;
    });
  }

  Future<void> _deleteNode(String name) async {
    // Correlate the tapped name with a placed item. The plugin's Android
    // side reports the tapped node's ANCHOR name (it walks the hit node up
    // to its anchor); the node's own name is kept for symmetry — finishes
    // carry explicit names, anchors are auto-generated UniqueKeys.
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

  /// Opens the placed-items sheet: every item with a per-item Remove. The AR
  /// scene stays live behind the sheet, so removals apply instantly and the
  /// sheet refreshes in place.
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

  /// Removes one placed item from the AR scene and the list; refreshes the
  /// open sheet so the row disappears in place.
  Future<void> _removePlaced(
      _PlacedItem item, BuildContext sheetContext, StateSetter refreshSheet) {
    return _deletePlaced(item).then((_) {
      if (sheetContext.mounted) refreshSheet(() {});
    });
  }

  /// Core node+anchor removal shared by tap-to-delete and the sheet.
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

  /// AR-error overlay, split by whether the session ever RAN (fix 21):
  ///  - the session demonstrably ran (planes detected / a node placed or
  ///    tapped) then errored → "AR session stopped" with a CLOSE action (an
  ///    install CTA would be nonsense — ARCore worked);
  ///  - it never came up → the install CTA.
  /// While the overlay is shown, surface taps are answered with a snackbar
  /// (see [_onPlaneOrPointTap]) instead of silently doing nothing.
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ),
                // "N placed" counter — tapping it lists the placed items
                // with per-item Remove (fix 20).
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.white),
                ),
              ),
            ),
          ),
        ),

        // AR error overlay (e.g. session failed to start / stopped mid-run)
        if (_arError != null) _buildArErrorOverlay(),

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

        // Delete button for the tapped node (furniture or finish)
        if (_selectedNodeName != null)
          Positioned(
            right: 16,
            bottom: _bottomBarHeight + 24,
            child: FloatingActionButton.small(
              heroTag: 'ar-delete',
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              tooltip: 'Remove item',
              onPressed: () => _deleteNode(_selectedNodeName!),
              child: const Icon(Icons.delete_outline),
            ),
          ),

        // "Placed at true size" / "Placed finish" chip — floats above the
        // bottom bar (clear of the mode switcher) until tapped or after 8 s.
        if (_showPlacedChip && _placedChipText != null)
          Positioned(
            left: 16,
            right: 88,
            bottom: _bottomBarHeight + 46,
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
                        child: Text(
                          _placedChipText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white),
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

        // Bottom bar: the furniture catalog (Furniture mode) or the Room
        // finish panel.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child:
                _roomMode ? _buildRoomBar() : _buildFurnitureBar(),
          ),
        ),

        // Furniture | Room mode switcher, floating just above the bar.
        Positioned(
          left: 0,
          right: 0,
          bottom: _bottomBarHeight + 8,
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

  /// The catalog bar shown in Furniture mode — unchanged behavior.
  Widget _buildFurnitureBar() {
    return Container(
      height: _furnitureBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: _barDecoration,
      child: _entries.isEmpty
          ? const SizedBox.shrink()
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _buildCatalogSlot(i),
            ),
    );
  }

  /// Compact segmented Furniture | Room switch floating above the bar.
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

  // ─── Bottom bar (Room mode) — floor / wall finishes ───

  Widget _buildRoomBar() {
    return Container(
      height: _roomBarHeight,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: _barDecoration,
      child: SingleChildScrollView(
        // The panel scrolls vertically when system text scaling makes the
        // finish rows taller than the fixed bar — no clipped controls.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFloorTypeRow(),
            _buildTypeCaption(
              '${RoomFinishCatalog.floorLabel(_floorType)} — '
              '${RoomFinishCatalog.floorDescription(_floorType)}',
            ),
            const SizedBox(height: 2),
            _buildFloorSizeRow(),
            const SizedBox(height: 4),
            _buildWallTypeRow(),
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

  /// One-line ellipsized description of the currently selected floor / wall
  /// type, rendered under its type strip ("Wood — warm plank boards …").
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

  /// "Floor" row: type chips (Wood/Cement/Ceramic/Parquet) then the swatch
  /// circles of the selected type — one horizontal scroll strip. The selected
  /// type's one-line description renders as a caption under the strip (in
  /// [_buildRoomBar]).
  Widget _buildFloorTypeRow() {
    final colors = RoomFinishCatalog.colorsForFloor(_floorType);
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

  /// "Floor" size chips (2 m / 3 m / 4 m) + the Place floor action.
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
                      label: '${size.toStringAsFixed(0)} m',
                      selected: size == _floorSizeM,
                      onTap: () => _selectFloorSize(size),
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

  /// "Wall" row: type chips (Paint/Wood Panel/Brick) + swatches, with the
  /// Place wall action pinned at the row's end (outside the scroll strip).
  Widget _buildWallTypeRow() {
    final colors = RoomFinishCatalog.colorsForWall(_wallType);
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
      trailing: _buildPlaceAction(
        label: 'Place wall',
        icon: Icons.view_agenda_outlined,
        busy: _arming,
        onTap: _armWallPlacement,
      ),
    );
  }

  /// Label + horizontally scrollable content strip, optionally with a
  /// pinned trailing action (e.g. Place wall) outside the scroll area.
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

  /// Compact selectable chip (type or size). Exposes a labeled button with a
  /// selected state to assistive tech; minimum 32 px tall tap target.
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

  /// Circular color swatch — ringed when selected. 32 px target with the
  /// color's name exposed as a Tooltip and to assistive tech.
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

  /// Primary "Place …" pill. Shows a small spinner while the finish GLB is
  /// being generated/saved. Minimum 32 px tall tap target.
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

  /// Bottom line of the Room panel: the interaction hint, or — while a
  /// finish is armed — its status + the Done (✕) that clears it.
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

  // ─── Catalog bar slots ───

  Widget _buildCatalogSlot(int index) {
    final entry = _entries[index];
    final selected = index == _selectedIndex;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        width: entry.isProduct ? 96 : 76,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.accent : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: AppColors.accentLight, width: 2)
              : Border.all(color: Colors.white24),
        ),
        child: entry.isProduct
            ? _buildProductSlot(entry.product!)
            : _buildLibrarySlot(entry.item!),
      ),
    );
  }

  /// Bundled library tile — unchanged visual language (icon + name).
  Widget _buildLibrarySlot(ArFurnitureItem item) {
    return Column(
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
    );
  }

  /// Product tile: source badge + name + dimensions while the true-size GLB
  /// is ready; a small spinner with "Preparing 3D…" while it loads.
  Widget _buildProductSlot(ArProductEntry entry) {
    if (!entry.isResolved) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white70),
          ),
          const SizedBox(height: 5),
          Text(
            'Preparing 3D…',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
                fontSize: 7.5,
                fontWeight: FontWeight.w500,
                color: Colors.white70),
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
            const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            _SourceBadge(text: entry.badgeText),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            entry.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white),
          ),
        ),
        const SizedBox(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                entry.dimsLabel,
                maxLines: 1,
                style: GoogleFonts.poppins(
                    fontSize: 7, color: Colors.white70),
              ),
            ),
          ),
        ),
      ],
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
      return 'Preparing the true-size 3D model — keep moving your phone, '
          'then tap to place once it is ready';
    }
    if (!_planesFound) {
      return 'Move your phone slowly to detect surfaces, then tap to place '
          '$name';
    }
    if (_placed.isEmpty) {
      return 'Tap a detected surface to place $name';
    }
    return 'Tap to place $name • '
        'Drag to move • Twist to rotate • Tap model to remove';
  }
}

/// Tiny colored chip for the product slot's source ('AI' / 'Auto').
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
