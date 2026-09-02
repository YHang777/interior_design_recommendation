import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/router/route_names.dart';
import '../../../../features/ar/data/glb_generator.dart' show resolveShapeFamily;
import '../../../../models/product.dart';
import '../../../../models/product_category.dart';
import '../../../../services/model_generation/model_generation_trigger.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/product_card.dart';
import '../../../../shared/widgets/quantity_stepper.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../providers/supplier_providers.dart';

/// Full-screen create/edit form for a supplier product.
///
/// Create: `/supplier/products/new`. Edit: `/supplier/products/:id/edit`
/// (the product is resolved from the real-time product stream by id).
///
/// Structure: Photos → Details → Pricing & stock → Dimensions (for 3D & AR)
/// → Live buyer preview.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.productId});

  /// Null in create mode; the product id to edit otherwise.
  final String? productId;

  bool get isEditing => productId != null && productId!.trim().isNotEmpty;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

/// One photo slot: a picked-and-uploaded file, a bundled catalogue asset, or
/// an image already on the product (edit mode).
class _ImageEntry {
  const _ImageEntry({
    required this.id,
    required this.source,
    this.isLocalFile = false,
    this.isSessionUpload = false,
    this.progress,
  });

  final int id;

  /// Display source: http(s) URL, local temp file path, or asset path.
  final String source;
  final bool isLocalFile;

  /// Uploaded to Firebase Storage during this session (safe to delete
  /// remotely if the user removes the photo before saving).
  final bool isSessionUpload;

  /// Non-null while uploading (0..1).
  final double? progress;

  bool get isUploading => isLocalFile && progress != null;

  _ImageEntry copyWith({
    String? source,
    bool? isLocalFile,
    bool? isSessionUpload,
    double? progress,
  }) {
    return _ImageEntry(
      id: id,
      source: source ?? this.source,
      isLocalFile: isLocalFile ?? this.isLocalFile,
      isSessionUpload: isSessionUpload ?? this.isSessionUpload,
      progress: progress,
    );
  }
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  static const int _maxImages = 4;
  static const int _descriptionMinChars = 20;
  static const int _descriptionMaxChars = 500;
  static const int _nameMaxChars = 80;

  /// Bundled furniture imagery offered as a no-internet fallback when the
  /// camera/gallery/upload path fails.
  static const List<String> _catalogAssets = [
    'assets/images/furniture_sofa_modern.png',
    'assets/images/furniture_sofa_classic.png',
    'assets/images/furniture_chair_modern.png',
    'assets/images/furniture_chair_classic.png',
    'assets/images/furniture_table_coffee.png',
    'assets/images/furniture_table_dining.png',
    'assets/images/furniture_bed_modern.png',
    'assets/images/furniture_bed_classic.png',
    'assets/images/furniture_lamp_floor.png',
    'assets/images/furniture_lamp_table.png',
    'assets/images/furniture_rug_modern.png',
    'assets/images/furniture_rug_classic.png',
    'assets/images/furniture_cabinet_modern.png',
    'assets/images/furniture_cabinet_classic.png',
    'assets/images/furniture_desk_modern.png',
    'assets/images/furniture_desk_classic.png',
  ];

  final _formKey = GlobalKey<FormState>();
  final _photosSectionKey = GlobalKey();
  final _nameKey = GlobalKey<FormFieldState<String>>();
  final _categoryKey = GlobalKey<FormFieldState<String>>();
  final _styleKey = GlobalKey<FormFieldState<String>>();
  final _descriptionKey = GlobalKey<FormFieldState<String>>();
  final _priceKey = GlobalKey<FormFieldState<String>>();
  final _originalPriceKey = GlobalKey<FormFieldState<String>>();
  final _widthKey = GlobalKey<FormFieldState<String>>();
  final _heightKey = GlobalKey<FormFieldState<String>>();
  final _depthKey = GlobalKey<FormFieldState<String>>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _originalPriceCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _widthCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _depthCtrl;

  /// Whether the seller has entered 3D dimensions themselves (or they came
  /// from an existing product). While false, category/name auto-fill the
  /// dimensions with shape-typical defaults; once true the auto-fill stops
  /// so the fields never fight the seller's own values.
  bool _dimsEdited = false;

  /// ProductDimensions that pass parsing, or null while any field is empty
  /// or unparseable (the per-field validators block saving those).
  ProductDimensions? get _formDimensions {
    final w = double.tryParse(_widthCtrl.text.trim());
    final h = double.tryParse(_heightCtrl.text.trim());
    final d = double.tryParse(_depthCtrl.text.trim());
    if (w == null || h == null || d == null) return null;
    return ProductDimensions(widthM: w, heightM: h, depthM: d);
  }

  Product? _existing;
  bool _seeded = false;
  bool _attemptedSubmit = false;
  bool _saving = false;
  bool _dirty = false;
  bool _saved = false;
  int _stock = 0;
  bool _isEco = false;
  bool _isActive = true;
  String? _category;
  String? _style;
  List<_ImageEntry> _images = [];
  int _nextImageId = 0;

  /// Stock the product had when the edit form was opened (create mode: 0).
  /// The save passes `stock − _originalStock` so the repository applies the
  /// seller's intended CHANGE on top of the live document stock instead of
  /// overwriting sales that land mid-edit.
  int _originalStock = 0;

  /// Pre-existing network image URLs the seller removed from the gallery —
  /// handed to [MarketplaceRepository.updateProduct] on save so the orphaned
  /// Storage blobs are deleted once the doc write succeeds.
  final Set<String> _removedOriginalUrls = {};

  bool get _isEditing => widget.isEditing;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _priceCtrl = TextEditingController();
    _originalPriceCtrl = TextEditingController();
    _descriptionCtrl = TextEditingController();
    _widthCtrl = TextEditingController();
    _heightCtrl = TextEditingController();
    _depthCtrl = TextEditingController();

    // Edit from the product list: the product is usually already cached in
    // the real-time stream, so seed immediately to avoid a flash.
    final cached = ref
        .read(marketplaceProductsProvider)
        .valueOrNull;
    if (_isEditing) {
      final product =
          cached?.where((p) => p.id == widget.productId).firstOrNull;
      if (product != null) _adoptProduct(product);
    }
  }

  void _adoptProduct(Product p) {
    _existing = p;
    _nameCtrl.text = p.name;
    _priceCtrl.text = p.price.toString();
    _originalPriceCtrl.text = p.originalPrice?.toString() ?? '';
    _descriptionCtrl.text = p.description;
    _category = p.category;
    _style = p.designStyle;
    _stock = p.stock;
    _originalStock = p.stock;
    _isEco = p.isEcoFriendly;
    _isActive = p.isActive;
    _removedOriginalUrls.clear();
    _images = p.resolvedImages.map((url) {
      return _ImageEntry(
        id: ++_nextImageId,
        source: url,
        // Pre-existing photos are never deleted remotely from the form —
        // removing one only drops it from the list (the DB overwrite on save
        // is what actually detaches it).
        isSessionUpload: false,
      );
    }).toList();
    final dims = p.dimensions;
    if (dims != null && (dims.widthM > 0 || dims.heightM > 0 || dims.depthM > 0)) {
      // Existing dimensions are the seller's own data — prefill them and
      // lock the fields so a category change cannot stomp them.
      _widthCtrl.text = _dimText(dims.widthM);
      _heightCtrl.text = _dimText(dims.heightM);
      _depthCtrl.text = _dimText(dims.depthM);
      _dimsEdited = true;
    } else {
      // Legacy product without dimensions — propose shape-typical defaults
      // (still editable; category/name changes keep refining them).
      _maybeAutoFillDims();
    }
    _seeded = true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _originalPriceCtrl.dispose();
    _descriptionCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _depthCtrl.dispose();
    // Discarded, never-published uploads would otherwise linger in Storage.
    if (!_saved) _cleanupSessionUploads();
    super.dispose();
  }

  // ── Dirty / change helpers ─────────────────────────────────────────────

  void _onAnyChange() {
    if (_dirty) return;
    setState(() => _dirty = true);
  }

  void _setImageList(List<_ImageEntry> next) {
    if (!_dirty) _dirty = true;
    setState(() => _images = next);
  }

  // ── 3D dimensions auto-fill ────────────────────────────────────────────

  /// Decimal without trailing zeros, e.g. 2.20 → '2.2', 1.00 → '1.0'.
  static String _dimText(double v) {
    var s = v.toStringAsFixed(2);
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = '${s}0';
    return s;
  }

  /// Typical W×H×D (m) per shape family. The family comes from the ONE
  /// classifier shared with the GLB generator ([resolveShapeFamily]), so the
  /// form and the generator can never disagree about what a product name
  /// means ('Table Lamp' is a lamp here and in the generator, 'Bedside
  /// Table' a cabinet).
  ///
  /// Only families with genuinely typical sizes carry a guess. A product
  /// whose name no classifier keyword matches ([resolveShapeFamily] returns
  /// 'default') has NO entry here and its fields are left EMPTY — never
  /// fabricate a generic cuboid for a shape nobody recognized.
  static const Map<String, ProductDimensions> _familyDefaultDims = {
    'table': ProductDimensions(widthM: 1.0, heightM: 0.75, depthM: 0.6),
    'sofa': ProductDimensions(widthM: 2.2, heightM: 0.85, depthM: 0.9),
    'chair': ProductDimensions(widthM: 0.6, heightM: 0.9, depthM: 0.6),
    'armchair':
        ProductDimensions(widthM: 0.9, heightM: 0.95, depthM: 0.85),
    'bed': ProductDimensions(widthM: 1.6, heightM: 1.2, depthM: 2.0),
    'cabinet': ProductDimensions(widthM: 1.0, heightM: 1.8, depthM: 0.4),
    'lamp': ProductDimensions(widthM: 0.4, heightM: 1.4, depthM: 0.4),
    'rug': ProductDimensions(widthM: 1.8, heightM: 0.1, depthM: 2.4),
    'vase': ProductDimensions(widthM: 0.3, heightM: 0.45, depthM: 0.3),
    'mirror': ProductDimensions(widthM: 0.9, heightM: 1.2, depthM: 0.1),
    'cushion': ProductDimensions(widthM: 0.45, heightM: 0.15, depthM: 0.45),
  };

  /// Guess shape-typical dimensions from the current name + category, or
  /// null when nothing suggests a shape yet (the fields then stay EMPTY and
  /// just show their 'e.g. 1.0' placeholders).
  ProductDimensions? _guessDefaultDims() {
    final name = _nameCtrl.text.trim();
    // Name-only overrides the generic family table cannot express: a
    // bedside table is a small 'cabinet' — 0.45 × 0.6 × 0.4 m, not a
    // 1.8 m tall wardrobe.
    final lower = name.toLowerCase();
    if (lower.contains('bedside') || lower.contains('nightstand')) {
      return const ProductDimensions(widthM: 0.45, heightM: 0.6, depthM: 0.4);
    }
    final family = resolveShapeFamily(category: _category ?? '', name: name);
    return _familyDefaultDims[family];
  }

  /// Fills the dimension fields from a name/category hint, but only while
  /// the seller has not typed their own values (or inherited them from an
  /// existing product). Called on category changes and name edits.
  void _maybeAutoFillDims() {
    if (_dimsEdited) return;
    final dims = _guessDefaultDims();
    if (dims == null) return;
    final w = _dimText(dims.widthM);
    final h = _dimText(dims.heightM);
    final d = _dimText(dims.depthM);
    if (_widthCtrl.text.trim() == w &&
        _heightCtrl.text.trim() == h &&
        _depthCtrl.text.trim() == d) {
      return; // already showing these defaults
    }
    _widthCtrl.text = w;
    _heightCtrl.text = h;
    _depthCtrl.text = d;
  }

  void _onNameChanged() {
    _onAnyChange();
    _maybeAutoFillDims();
  }

  void _onDimChanged() {
    _dimsEdited = true;
    _onAnyChange();
  }

  /// Required + numeric + 0.1–10.0 m with inline error messages.
  String? _validateDim(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Required';
    final value = double.tryParse(t);
    if (value == null) return 'Enter a number';
    if (value < 0.1) return 'Min 0.1 m';
    if (value > 10.0) return 'Max 10 m';
    return null;
  }

  // ── Image picking / uploading ──────────────────────────────────────────

  Future<void> _showPickSource() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              'Add photo',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.accent),
              title: Text('Camera',
                  style: GoogleFonts.poppins(
                      color: AppColors.textPrimary, fontSize: 14)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.accent),
              title: Text('Choose from gallery',
                  style: GoogleFonts.poppins(
                      color: AppColors.textPrimary, fontSize: 14)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    await _pickAndUpload(source);
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1200,
      );
    } catch (e) {
      debugPrint('[product form] pickImage failed: $e');
    }
    if (file == null || !mounted) return;
    await _startUpload(file.path);
  }

  Future<void> _startUpload(String localPath) async {
    if (_images.length >= _maxImages) return;
    final supplier = ref.read(currentSupplierProvider);
    if (supplier == null) return;

    final entryId = ++_nextImageId;
    final uid = supplier.id;
    // NOTE: path lives under `images/` because storage.rules grants
    // authenticated writes only inside that prefix.
    final millis = DateTime.now().millisecondsSinceEpoch;
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('images/product_images/$uid/${millis}_$entryId.jpg');

    final entry = _ImageEntry(
      id: entryId,
      source: localPath,
      isLocalFile: true,
      progress: 0,
    );
    _setImageList([..._images, entry]);

    final uploadTask = storageRef.putFile(File(localPath));
    final progressSub = uploadTask.snapshotEvents.listen((event) {
      if (!mounted) return;
      final total = event.totalBytes;
      _updateEntry(entryId, (e) => e.copyWith(
          progress: total == 0 ? 0 : event.bytesTransferred / total));
    });

    try {
      await uploadTask;
      final url = await storageRef.getDownloadURL();
      if (!mounted) return;
      final stillListed = _updateEntry(
        entryId,
        (e) => e.copyWith(
          source: url,
          isLocalFile: false,
          isSessionUpload: true,
          progress: null,
        ),
      );
      if (!stillListed) {
        // The user removed the thumbnail mid-upload — drop the orphan file.
        unawaited(_deleteRemote(url));
      }
    } catch (e) {
      debugPrint('[product form] upload failed: $e');
      if (!mounted) return;
      _updateEntry(entryId, (_) => null); // remove failed entry
      showAppSnackbar(
        context,
        'Photo upload failed. Please try again.',
        isError: true,
        duration: const Duration(seconds: 3),
        actionLabel: 'Pick from catalog',
        onAction: () => _openCatalogPicker(),
      );
    } finally {
      progressSub.cancel();
    }
  }

  void _openCatalogPicker() {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final remaining = _maxImages - _images.length;
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    'Pick from catalog',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    remaining > 0
                        ? 'Bundle imagery shipped with the app '
                            '(no upload needed) — $remaining more allowed'
                        : 'Photo limit reached (4)',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: _catalogAssets.length,
                    itemBuilder: (ctx, index) {
                      final asset = _catalogAssets[index];
                      return GestureDetector(
                        onTap: () {
                          if (_images.length < _maxImages) {
                            _setImageList([
                              ..._images,
                              _ImageEntry(
                                  id: ++_nextImageId, source: asset),
                            ]);
                          }
                          Navigator.pop(ctx);
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            asset,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.divider,
                              child: const Icon(Icons.image,
                                  color: AppColors.textHint),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Applies [update] to the entry with [id]. Returns false when the entry is
  /// no longer in the list (removed while uploading).
  bool _updateEntry(int id, _ImageEntry? Function(_ImageEntry) update) {
    var found = false;
    final next = <_ImageEntry>[];
    for (final e in _images) {
      if (e.id == id) {
        found = true;
        final updated = update(e);
        if (updated != null) next.add(updated);
      } else {
        next.add(e);
      }
    }
    if (!found) return false;
    _setImageList(next);
    return true;
  }

  void _removeImage(int id) {
    final entry = _images.where((e) => e.id == id).firstOrNull;
    if (entry == null) return;
    _setImageList(_images.where((e) => e.id != id).toList());
    // Photos uploaded during THIS session are safe to delete remotely right
    // away. Pre-existing product photos are instead tracked so the SAVE
    // deletes their Storage blobs (only after the doc write succeeds — the
    // user might otherwise hit back and keep the photo on the product).
    if (entry.isSessionUpload) {
      unawaited(_deleteRemote(entry.source));
    } else if (entry.source.startsWith('http')) {
      _removedOriginalUrls.add(entry.source);
    }
  }

  Future<void> _deleteRemote(String url) async {
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (_) {
      // Already gone or not deletable — orphan cleanup is best effort.
    }
  }

  void _cleanupSessionUploads() {
    for (final e in _images) {
      if (e.isSessionUpload) unawaited(_deleteRemote(e.source));
    }
  }

  // ── Validation & submit ────────────────────────────────────────────────

  int? get _discountPercent {
    final price = int.tryParse(_priceCtrl.text.trim());
    final original = int.tryParse(_originalPriceCtrl.text.trim());
    if (price == null || price <= 0) return null;
    if (original == null || original <= price) return null;
    return ((original - price) / original * 100).round();
  }

  bool get _hasPendingUploads =>
      _images.any((e) => e.isLocalFile && e.progress != null);

  Product _buildProduct(Supplier supplier) {
    final first = _images.isNotEmpty ? _images.first.source : '';
    final all = _images.map((e) => e.source).toList();
    return Product(
      id: _isEditing ? widget.productId! : '',
      name: _nameCtrl.text.trim(),
      price: int.tryParse(_priceCtrl.text.trim()) ?? 0,
      stock: _stock,
      image: first,
      images: all.length > 1 ? all : [if (first.isNotEmpty) first],
      description: _descriptionCtrl.text.trim(),
      designStyle: _style!,
      category: _category!,
      supplier: supplier,
      supplierId: supplier.id,
      isActive: _isActive,
      isEcoFriendly: _isEco,
      // Preserve rolling ratings on edits; never fabricate on create.
      rating: _existing?.rating ?? 0.0,
      ratingCount: _existing?.ratingCount ?? 0,
      originalPrice: _discountPercent != null
          ? int.tryParse(_originalPriceCtrl.text.trim())
          : null,
      dimensions: _formDimensions,
      // Editing must never erase the product's auto-3D state — carry the
      // existing record forward so a form save cannot reset a ready /
      // generating / failed model back to 'none' (the repository additionally
      // re-merges ar3d from the live document inside its update transaction).
      ar3d: _existing?.ar3d,
      createdAt: _existing?.createdAt,
    );
  }

  bool _validate() {
    // Photo requirement is validated manually (not a FormField).
    if (_images.isEmpty) {
      final photoCtx = _photosSectionKey.currentContext;
      if (photoCtx != null) {
        unawaited(Scrollable.ensureVisible(
          photoCtx,
          duration: const Duration(milliseconds: 250),
          alignment: 0.1,
        ));
      }
      return false;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    return true;
  }

  void _scrollToFirstError() {
    final keys = [
      _nameKey,
      _categoryKey,
      _styleKey,
      _descriptionKey,
      _priceKey,
      _originalPriceKey,
      _widthKey,
      _heightKey,
      _depthKey,
    ];
    for (final key in keys) {
      final state = key.currentState;
      if (state != null && state.hasError) {
        final fieldCtx = state.context;
        if (fieldCtx.mounted) {
          unawaited(Scrollable.ensureVisible(
            fieldCtx,
            duration: const Duration(milliseconds: 250),
            alignment: 0.15,
          ));
        }
        return;
      }
    }
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_saving) return;
    setState(() => _attemptedSubmit = true);
    if (!_validate()) {
      _scrollToFirstError();
      return;
    }

    final supplier = ref.read(currentSupplierProvider);
    if (supplier == null) {
      showAppSnackbar(
        context,
        'You must be signed in to publish products.',
        isError: true,
      );
      return;
    }

    setState(() => _saving = true);
    final repo = ref.read(marketplaceRepositoryProvider);
    // The messenger/error snackbars below may fire AFTER the form pops
    // itself, so capture them while this context is still live.
    final messenger = ScaffoldMessenger.of(context);
    try {
      final product = _buildProduct(supplier);
      final Product saved;
      if (_isEditing) {
        saved = await repo.updateProduct(
          product,
          originalStock: _originalStock,
          removedImageUrls: _removedOriginalUrls.toList(),
        );
      } else {
        saved = await repo.createProduct(product);
      }
      _saved = true;
      _dirty = false;
      // Auto-3D pipeline, fire-and-forget, BEFORE popping: the saved product
      // (with its real doc id) decides — procedural-ready when dims exist,
      // a Tripo AI task when configured + network image, else ar3d 'none'.
      // Status shows up in the management list's chip when the seller
      // returns to it.
      kickOffProduct3DGeneration(saved);
      if (!mounted) return;
      // Capture the router while this context is still live — the snackbar
      // action below fires after the form has popped itself.
      final goRouter = GoRouter.of(context);
      context.pop();
      // The live Firestore streams refresh the seller lists automatically.

      final label = _isEditing ? 'Changes saved' : 'Product published';
      showAppSnackbarOn(
        messenger,
        label,
        color: AppColors.success,
        duration: const Duration(seconds: 3),
        actionLabel: product.isActive && !_isEditing ? 'View in store' : null,
        onAction: product.isActive && !_isEditing
            ? () {
                // Suppliers are allowed to browse the storefront (Loop 3):
                // /marketplace and product detail pages are whitelisted in
                // the router redirect. `go` (rather than `push`) avoids
                // stacking a duplicate shell.
                messenger.hideCurrentSnackBar();
                goRouter.goNamed(RouteNames.homeownerMarketplace);
              }
            : null,
      );
    } catch (e) {
      if (mounted) {
        showAppSnackbar(
          context,
          _isEditing
              ? 'Could not save changes'
              : 'Could not publish product',
          detail: e.toString(),
          isError: true,
          duration: const Duration(seconds: 4),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Discard guard ──────────────────────────────────────────────────────

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Discard changes?',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          _isEditing
              ? 'Your edits to this product will be lost.'
              : 'Your draft product will be lost.',
          style: GoogleFonts.poppins(
            fontSize: 13.5,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Keep editing',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.textOnDark,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      _dirty = false;
      context.pop();
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Always watch — used to resolve the product being edited (the seeded
    // snapshot from initState covers the common list → edit path).
    final productsAsync = ref.watch(marketplaceProductsProvider);
    if (!_seeded && _isEditing) {
      final found =
          productsAsync.valueOrNull?.where((p) => p.id == widget.productId).firstOrNull;
      if (found != null) _adoptProduct(found);
    }
    if (_isEditing && !_seeded) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Edit Product')),
        body: productsAsync.isLoading
            ? const Center(child: CircularProgressIndicator())
            : EmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Product not found',
                subtitle: 'It may have been deleted.',
                actionLabel: 'Go back',
                onAction: () => context.pop(),
              ),
      );
    }

    final categoriesAsync = ref.watch(categoriesProvider);
    final stylesAsync = ref.watch(stylesProvider);
    final preview = _previewProduct();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Product' : 'New Product'),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Form(
          key: _formKey,
          autovalidateMode: _attemptedSubmit
              ? AutovalidateMode.always
              : AutovalidateMode.disabled,
          child: PopScope(
            canPop: !_dirty || _saved,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop || _saved) return;
              await _confirmDiscard();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                _buildPhotosSection(),
                const SizedBox(height: 14),
                _buildDetailsSection(categoriesAsync, stylesAsync),
                const SizedBox(height: 14),
                _buildPricingSection(),
                const SizedBox(height: 14),
                _buildDimensionsSection(),
                const SizedBox(height: 14),
                _buildPreviewSection(preview),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildSubmitBar(),
    );
  }

  Product _previewProduct() {
    final supplier = ref.watch(currentSupplierProvider);
    final price = int.tryParse(_priceCtrl.text.trim()) ?? 0;
    final original = _discountPercent == null
        ? null
        : int.tryParse(_originalPriceCtrl.text.trim());
    return Product(
      id: _existing?.id ?? '',
      name: _nameCtrl.text.trim().isEmpty
          ? 'Your product name'
          : _nameCtrl.text.trim(),
      price: price,
      stock: _stock,
      image: _images.isNotEmpty ? _images.first.source : '',
      description: _descriptionCtrl.text.trim(),
      designStyle: _style ?? 'Modern',
      category: _category ?? 'Furniture',
      supplier: supplier ??
          const Supplier(
            id: '',
            name: 'Your store',
            phone: '',
            address: '',
            email: '',
          ),
      supplierId: supplier?.id ?? '',
      isActive: _isActive,
      isEcoFriendly: _isEco,
      rating: _existing?.rating ?? 0.0,
      ratingCount: _existing?.ratingCount ?? 0,
      originalPrice: original,
      dimensions: _formDimensions,
    );
  }

  // ── Section 1: Photos ──────────────────────────────────────────────────

  Widget _buildPhotosSection() {
    final photoError = _attemptedSubmit && _images.isEmpty;
    return _SectionCard(
      sectionKey: _photosSectionKey,
      title: 'Photos',
      subtitle: 'First photo is your cover • up to $_maxImages',
      trailing: _images.isNotEmpty
          ? Text(
              '${_images.length}/$_maxImages',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length + (_images.length < _maxImages ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (index >= _images.length) return _buildAddTile();
                return _buildThumbnail(_images[index], index);
              },
            ),
          ),
          if (photoError) ...[
            const SizedBox(height: 8),
            Text(
              'Add at least one photo so buyers can see your product',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: AppColors.error,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddTile() {
    return GestureDetector(
      onTap: _hasPendingUploads ? null : _showPickSource,
      child: Container(
        width: 82,
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: AppColors.background,
        ),
        child: CustomPaint(
          painter: _DashedBorderPainter(color: AppColors.textHint),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _hasPendingUploads
                    ? Icons.hourglass_top
                    : Icons.add_a_photo_outlined,
                color: AppColors.textHint,
                size: 26,
              ),
              const SizedBox(height: 4),
              Text(
                _hasPendingUploads ? 'Uploading…' : 'Add',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(_ImageEntry entry, int index) {
    return SizedBox(
      width: 82,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _entryImage(entry),
          ),
          // Cover badge — first image is the marketplace cover.
          if (index == 0)
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Cover',
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textOnDark,
                  ),
                ),
              ),
            ),
          // Remove button — ~36px tap target with tooltip + semantics.
          Positioned(
            top: 0,
            right: 0,
            child: Semantics(
              button: true,
              label: 'Remove photo',
              child: Tooltip(
                message: 'Remove photo',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _removeImage(entry.id),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 36,
                      height: 36,
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          size: 17, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Upload progress ring.
          if (entry.isUploading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      value: entry.progress,
                      strokeWidth: 2.5,
                      color: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _entryImage(_ImageEntry entry) {
    final url = entry.source;
    if (entry.isLocalFile) {
      return Image.file(
        File(url),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _ThumbPlaceholder(),
      );
    }
    if (url.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => const _ThumbPlaceholder(),
        errorWidget: (_, __, ___) => const _ThumbPlaceholder(),
      );
    }
    return Image.asset(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const _ThumbPlaceholder(),
    );
  }

  // ── Section 2: Details ─────────────────────────────────────────────────

  Widget _buildDetailsSection(
    AsyncValue<List<ProductCategory>> categoriesAsync,
    AsyncValue<List<String>> stylesAsync,
  ) {
    return _SectionCard(
      title: 'Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AppInput(
            label: 'Product name',
            hint: 'e.g. Oslo 3-Seater Fabric Sofa',
            icon: Icons.text_fields,
            controller: _nameCtrl,
            fieldKey: _nameKey,
            maxLength: _nameMaxChars,
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) return 'Product name is required';
              if (t.length < 3) {
                return 'Name must be at least 3 characters';
              }
              return null;
            },
            onChanged: _onNameChanged,
          ),
          const SizedBox(height: 14),
          categoriesAsync.when(
            data: (cats) => DropdownButtonFormField<String>(
              key: _categoryKey,
              value: cats.any((c) => c.name == _category) ? _category : null,
              decoration: _dropdownDecoration(
                'Category',
                Icons.category_outlined,
              ),
              items: [
                for (final c in cats)
                  DropdownMenuItem(value: c.name, child: Text(c.name)),
              ],
              onChanged: (v) {
                _onAnyChange();
                setState(() => _category = v);
                // Suggest shape-typical 3D dims for the new category unless
                // the seller already entered their own.
                _maybeAutoFillDims();
              },
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Choose a category' : null,
              borderRadius: BorderRadius.circular(12),
            ),
            loading: () => const _DropdownPlaceholder(label: 'Category'),
            error: (_, __) => Text(
              'Categories could not be loaded',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: AppColors.error),
            ),
          ),
          const SizedBox(height: 14),
          stylesAsync.when(
            data: (styles) => DropdownButtonFormField<String>(
              key: _styleKey,
              value: styles.contains(_style) ? _style : null,
              decoration: _dropdownDecoration('Design style', Icons.palette_outlined),
              items: [
                for (final s in styles)
                  DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: (v) {
                _onAnyChange();
                setState(() => _style = v);
              },
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Choose a design style' : null,
              borderRadius: BorderRadius.circular(12),
            ),
            loading: () => const _DropdownPlaceholder(label: 'Design style'),
            error: (_, __) => Text(
              'Styles could not be loaded',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: AppColors.error),
            ),
          ),
          const SizedBox(height: 14),
          _AppInput(
            label: 'Description',
            icon: Icons.notes,
            controller: _descriptionCtrl,
            fieldKey: _descriptionKey,
            maxLength: _descriptionMaxChars,
            maxLines: 4,
            minLines: 3,
            hint: 'Materials, dimensions, care — what makes it special?',
            helperText:
                'Minimum $_descriptionMinChars characters so buyers get real detail',
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) return 'Description is required';
              if (t.length < _descriptionMinChars) {
                return 'Add at least $_descriptionMinChars characters '
                    '(${t.length}/$_descriptionMinChars)';
              }
              return null;
            },
            onChanged: _onAnyChange,
          ),
        ],
      ),
    );
  }

  // ── Section 3: Pricing & stock ─────────────────────────────────────────

  Widget _buildPricingSection() {
    final discount = _discountPercent;
    return _SectionCard(
      title: 'Pricing & stock',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AppInput(
            label: 'Price (RM)',
            icon: Icons.sell_outlined,
            controller: _priceCtrl,
            fieldKey: _priceKey,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            hint: 'e.g. 1299',
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) return 'Price is required';
              final value = int.tryParse(t);
              if (value == null) return 'Enter a whole number (RM)';
              if (value <= 0) return 'Price must be above RM 0';
              return null;
            },
            onChanged: _onAnyChange,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _AppInput(
                  label: 'Original price (optional)',
                  icon: Icons.sell_outlined,
                  controller: _originalPriceCtrl,
                  fieldKey: _originalPriceKey,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  hint: 'For markdowns',
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return null;
                    final original = int.tryParse(t);
                    if (original == null) return 'Enter a whole number (RM)';
                    final price = int.tryParse(_priceCtrl.text.trim());
                    if (price == null || original <= price) {
                      return 'Must be higher than price';
                    }
                    return null;
                  },
                  onChanged: _onAnyChange,
                ),
              ),
              if (discount != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '-$discount%',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stock',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Units available for sale',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
                QuantityStepper(
                  value: _stock,
                  min: 0,
                  max: 9999,
                  onChanged: (v) {
                    _onAnyChange();
                    setState(() => _stock = v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isEco,
            onChanged: (v) {
              _onAnyChange();
              setState(() => _isEco = v);
            },
            activeTrackColor: AppColors.accent,
            title: Text(
              'Eco-friendly',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              'Made from sustainable materials',
              style: GoogleFonts.poppins(
                  fontSize: 11, color: AppColors.textHint),
            ),
            secondary: const Icon(Icons.eco_outlined,
                color: AppColors.success),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isActive,
            onChanged: (v) {
              _onAnyChange();
              setState(() => _isActive = v);
            },
            activeTrackColor: AppColors.accent,
            title: Text(
              'Active',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              _isActive
                  ? 'Listing is live on the marketplace'
                  : 'Paused — buyers will not see this product',
              style: GoogleFonts.poppins(
                  fontSize: 11, color: AppColors.textHint),
            ),
            secondary: const Icon(Icons.visibility_outlined,
                color: AppColors.secondaryAccent),
          ),
        ],
      ),
    );
  }

  // ── Section 4: Dimensions (for 3D & AR) ────────────────────────────────

  Widget _buildDimensionsSection() {
    return _SectionCard(
      title: 'Dimensions (for 3D & AR)',
      subtitle: 'Real-world size of the product, in meters',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _AppInput(
                  label: 'Width (m)',
                  icon: Icons.straighten,
                  controller: _widthCtrl,
                  fieldKey: _widthKey,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  hint: 'e.g. 1.0',
                  validator: _validateDim,
                  onChanged: _onDimChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AppInput(
                  label: 'Height (m)',
                  icon: Icons.straighten,
                  controller: _heightCtrl,
                  fieldKey: _heightKey,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  hint: 'e.g. 1.0',
                  validator: _validateDim,
                  onChanged: _onDimChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AppInput(
                  label: 'Depth (m)',
                  icon: Icons.straighten,
                  controller: _depthCtrl,
                  fieldKey: _depthKey,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  hint: 'e.g. 1.0',
                  validator: _validateDim,
                  onChanged: _onDimChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Shown while the fields carry the shape-typical auto-fill (and
          // disappears the moment the seller types their own values): the
          // guess comes from the product name, so it needs a human check.
          if (!_dimsEdited &&
              _widthCtrl.text.trim().isNotEmpty &&
              _heightCtrl.text.trim().isNotEmpty &&
              _depthCtrl.text.trim().isNotEmpty)
            Text(
              'Suggested from product name — check before publishing',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: AppColors.secondaryAccent,
              ),
            ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.view_in_ar_outlined,
                    size: 20, color: AppColors.secondaryAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Used to auto-generate the 3D model at true size in AR.',
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section 5: Live buyer preview ──────────────────────────────────────

  Widget _buildPreviewSection(Product preview) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 12) / 2;
        final cardHeight = cardWidth / 0.68; // matches buyer grid tiles
        return _SectionCard(
          title: 'Buyer preview',
          subtitle: 'How buyers see this product in the marketplace',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: ProductCard(
                  product: preview,
                  compact: false,
                  onTap: () {
                    // Nothing to open yet — the preview is illustrative.
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubmitBar() {
    final busy = _saving;
    final uploading = _hasPendingUploads;
    final label = busy
        ? 'Posting product…'
        : uploading
            ? 'Uploading photos…'
            : _isEditing
                ? 'Save changes'
                : 'Publish product';
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (busy || uploading) ? null : _submit,
              child: busy
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(label),
                      ],
                    )
                  : Text(label),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _dropdownDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}

/// Dashed rounded-rect border used by the "add photo" tile.
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    const dashWidth = 5.0;
    const dashSpace = 3.5;
    const radius = Radius.circular(12);
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      radius,
    );
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    for (final metric in metrics) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.divider,
      child: const Center(
        child: Icon(Icons.image_outlined, color: AppColors.textHint, size: 22),
      ),
    );
  }
}

class _DropdownPlaceholder extends StatelessWidget {
  const _DropdownPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        'Loading $label…',
        style: GoogleFonts.poppins(
            fontSize: 13, color: AppColors.textHint),
      ),
    );
  }
}

/// Text field with the app's "filled" treatment: a soft fill that brightens
/// and an accent border that appears on focus or when the field has content.
class _AppInput extends StatefulWidget {
  const _AppInput({
    required this.label,
    required this.controller,
    this.icon,
    this.hint,
    this.helperText,
    this.fieldKey,
    this.validator,
    this.keyboardType,
    this.inputFormatters,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final IconData? icon;
  final String? hint;
  final String? helperText;
  final Key? fieldKey;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final int maxLines;
  final int? minLines;
  final VoidCallback? onChanged;

  @override
  State<_AppInput> createState() => _AppInputState();
}

class _AppInputState extends State<_AppInput> {
  late final FocusNode _focusNode;
  bool _focused = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()
      ..addListener(() {
        final focused = _focusNode.hasFocus;
        if (focused != _focused) setState(() => _focused = focused);
      });
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_syncHasText);
  }

  void _syncHasText() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncHasText);
    _focusNode.dispose();
    super.dispose();
  }

  InputDecoration _decoration() {
    // Subtle state shift: soft grey fill → white once focused or filled;
    // the focused border (accent, 2px) comes from the app input theme.
    final hasState = _focused || _hasText;
    return InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      helperText: widget.helperText,
      prefixIcon: widget.icon == null
          ? null
          : Icon(widget.icon, color: AppColors.textSecondary, size: 20),
      filled: true,
      fillColor: hasState ? AppColors.surface : AppColors.background,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: widget.maxLines > 1 ? 14 : 18,
      ),
      counterText: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: widget.fieldKey,
      controller: widget.controller,
      focusNode: _focusNode,
      validator: widget.validator,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      maxLength: widget.maxLength,
      textCapitalization: TextCapitalization.sentences,
      style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
      onChanged: (v) {
        _syncHasText();
        widget.onChanged?.call();
      },
      decoration: _decoration(),
      // Custom counter ('n/max') in the hint color.
      buildCounter: (context,
          {required currentLength,
          required isFocused,
          required maxLength}) {
        if (maxLength == null) return null;
        return Text(
          '$currentLength/$maxLength',
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: AppColors.textHint,
          ),
        );
      },
    );
  }
}

/// White card container for a form section, with a heading + optional caption.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    this.sectionKey,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  final Key? sectionKey;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: sectionKey,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                color: AppColors.textHint,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
