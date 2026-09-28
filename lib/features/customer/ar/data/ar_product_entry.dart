import 'dart:io';
import 'dart:math' as math;

import '../../../../models/product.dart';
import 'glb_bounds.dart';

/// A product's slot in the AR viewer catalog bar, backed by its TRUE-SIZE
/// GLB (the product's own Tripo AI model, rescaled to the seller's declared
/// dimensions and resolved to a local file by `ModelGlbResolver`).
///
/// There is exactly one model source: a Tripo generation. No procedural
/// generation and no bundled-catalog fallback exists for products — if the
/// GLB cannot be resolved, the slot reports the failure instead of
/// substituting another model.
///
/// Pure Dart (no Flutter / AR-plugin / Firebase imports) so the catalog
/// model and its display helpers are unit-testable headlessly.
class ArProductEntry {
  ArProductEntry({
    required this.product,
    this.resolvedFile,
    this.productError,
  });

  /// Parsed-once scale cache: reading + parsing a multi-MB GLB on the UI
  /// thread per placement tap would hitch the frame; the file is immutable
  /// per entry instance, so the extent is deterministic and safe to memoize.
  double? _cachedScaleToMeters;

  /// The product whose real-world dimensions drive the 3D model.
  final Product product;

  /// Absolute path of the product's Tripo GLB (already rescaled to the
  /// seller's size and grounded at y = 0) on disk. Null while the model is
  /// still being prepared or when resolution failed — see [productError].
  final File? resolvedFile;

  /// Why the model could not be resolved — a specific, actionable reason
  /// (missing seller dimensions, Tripo not configured, generation failed, …).
  /// Null while resolution is still in flight or succeeded.
  final String? productError;

  /// True once the true-size GLB exists and can be placed.
  bool get isResolved => resolvedFile != null;

  /// True when resolution failed and [productError] explains why.
  bool get hasError => productError != null;

  /// Catalog slot name — the product's own name.
  String get name => product.name;

  /// Human-readable size shown under the name, e.g. "W 1.0 × H 1.5 × D 0.6 m".
  /// Empty when the product carries no dimensions at all.
  String get dimsLabel => product.dimensions?.label ?? '';

  /// True when all three real-world dimensions are known (> 0) — only then
  /// is the rescale per-axis (true size); with just some of them the rescale
  /// stays uniform, and with none the model is refused entirely.
  bool get hasTrueDimensions => product.dimensions?.isComplete ?? false;

  /// Max(W, H, D) in meters of the SELLER's declared dimensions, or null
  /// when they are incomplete. Informational (UI copy); never used to size a
  /// model — sizing comes from the resolved GLB itself.
  double? get maxDimM {
    final d = product.dimensions;
    if (d == null || !d.isComplete) return null;
    return math.max(d.widthM, math.max(d.heightM, d.depthM));
  }

  /// Node scale (meters on the model's max axis) to pass when placing the
  /// resolved GLB.
  ///
  /// The only source is the resolved file itself: the scale equals the
  /// parsed GLB's true max extent in meters (the bytes were already
  /// rescaled to the seller's size), so the plugin renders the node at
  /// exactly the geometry's real-world size.
  ///
  /// Throws [StateError] when there is no resolved file or it cannot be
  /// parsed — placement must never fall back to a guessed scale.
  double get scaleToMeters {
    final cached = _cachedScaleToMeters;
    if (cached != null) return cached;
    final file = resolvedFile;
    if (file == null) {
      throw StateError(
          'ArProductEntry.scaleToMeters: product "${product.id}" has no '
          'resolved GLB — refusing to guess a placement scale.');
    }
    // A corrupt / truncated file must fail like a missing one (StateError,
    // per the doc contract) rather than leak GlbParseException to callers —
    // either way placement refuses instead of guessing a scale.
    final GlbBounds bounds;
    try {
      bounds = GlbBounds.fromGlbBytes(file.readAsBytesSync());
    } on GlbParseException catch (e) {
      throw StateError(
          'ArProductEntry.scaleToMeters: resolved GLB for "${product.id}" '
          'is not a parseable GLB ($e).');
    }
    final extent = bounds.maxExtent;
    if (!extent.isFinite || extent <= 0) {
      throw StateError(
          'ArProductEntry.scaleToMeters: resolved GLB for "${product.id}" '
          'has degenerate bounds (${bounds.widthM} × ${bounds.heightM} × '
          '${bounds.depthM} m).');
    }
    return _cachedScaleToMeters = extent;
  }

  /// Badge text for the catalog slot. Tripo is the only model source, so
  /// every resolved product model is an 'AI' model; the badge is kept as a
  /// stable UI affordance.
  String get badgeText => 'AI';

  @override
  String toString() => 'ArProductEntry(${product.id}, $dimsLabel, '
      'resolved: $isResolved'
      '${productError == null ? '' : ', error: $productError'})';
}
