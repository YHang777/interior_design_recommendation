import 'dart:io';
import 'dart:math' as math;

import '../../../models/product.dart';
import 'furniture_model_library.dart';
import 'glb_bounds.dart';

/// A product's slot in the AR viewer catalog bar, backed by its TRUE-SIZE
/// GLB (the product's own auto-generated 3D model, resolved to a local
/// file by [ModelGlbResolver]).
///
/// Pure Dart (no Flutter / AR-plugin / Firebase imports) so the catalog
/// model and its display helpers are unit-testable headlessly.
class ArProductEntry {
  ArProductEntry({
    required this.product,
    this.resolvedFile,
    this.procedural = true,
  });

  /// Parsed-once scale cache: reading + parsing a multi-MB GLB on the UI
  /// thread per placement tap would hitch the frame; the file is immutable
  /// per entry instance, so the extent is deterministic and safe to memoize.
  double? _cachedScaleToMeters;

  /// The product whose real-world dimensions drive the 3D model.
  final Product product;

  /// Absolute path of the product's GLB on disk. Null while the model is
  /// still being prepared (or once resolution failed and the screen fell
  /// back to a bundled catalog model — then this entry is discarded).
  final File? resolvedFile;

  /// Whether the RESOLVED file's bytes came from the deterministic built-in
  /// generator (true) or a downloaded AI (Tripo) model (false). Decided by
  /// the resolver from the cache key the bytes were stored under — never
  /// from the product's current `ar3d` record, which may describe a ready
  /// Tripo model whose download failed and fell back to procedural. Only
  /// meaningful when [resolvedFile] is non-null.
  final bool procedural;

  /// True once the true-size GLB exists and can be placed.
  bool get isResolved => resolvedFile != null;

  /// Catalog slot name — the product's own name.
  String get name => product.name;

  /// Human-readable size shown under the name, e.g. "W 1.0 × H 1.5 × D 0.6 m".
  /// Empty when the product carries no dimensions at all.
  String get dimsLabel => product.dimensions?.label ?? '';

  /// True when all three real-world dimensions are known (> 0) — only then
  /// can a model be generated / rescaled and placed at a true size.
  bool get hasTrueDimensions => product.dimensions?.isComplete ?? false;

  /// Max(W, H, D) in meters.
  ///
  /// Our generated and rescaled GLBs are authored IN METERS with their max
  /// extent exactly equal to this value, and the AR plugin normalizes a
  /// node's MAX extent to `node.scale.x` meters (scale-to-unit-cube). The
  /// model therefore renders at true size when the node scale equals
  /// [maxDimM] (the internal normalization factor becomes 1.0).
  double? get maxDimM {
    final d = product.dimensions;
    if (d == null || !d.isComplete) return null;
    return math.max(d.widthM, math.max(d.heightM, d.depthM));
  }

  /// Node scale (meters on the model's max axis) to pass when placing the
  /// resolved GLB.
  ///
  /// The AUTHORITATIVE source is the resolved file itself: the scale equals
  /// the parsed GLB's true max extent in meters, so the plugin renders the
  /// node at exactly the geometry's real-world size whatever the product
  /// record claims. Falls back to the product's max(W, H, D) when the file
  /// is not resolvable yet, and to a nominal 1.0 when the product has no
  /// dimensions at all (no better scale is knowable).
  double get scaleToMeters {
    final cached = _cachedScaleToMeters;
    if (cached != null) return cached;
    final file = resolvedFile;
    if (file != null) {
      try {
        final bounds = GlbBounds.fromGlbBytes(file.readAsBytesSync());
        if (bounds.maxExtent.isFinite && bounds.maxExtent > 0) {
          return _cachedScaleToMeters = bounds.maxExtent;
        }
      } catch (_) {
        // Unreadable / corrupt cache file — fall through to the dims.
      }
    }
    return maxDimM ?? 1.0;
  }

  /// Badge text for the catalog slot: 'AI' when the model actually came from
  /// Tripo, 'Auto' when it came from our deterministic procedural generator.
  ///
  /// For a RESOLVED entry this follows the provenance of the resolved bytes
  /// ([procedural]); while resolution is pending it follows the product's
  /// `ar3d.source` as intent.
  String get badgeText {
    final aiModel = resolvedFile != null
        ? !procedural
        : (product.ar3d?.source == 'tripo');
    return aiModel ? 'AI' : 'Auto';
  }

  @override
  String toString() => 'ArProductEntry(${product.id}, $dimsLabel, '
      'resolved: $isResolved)';
}

/// Best bundled-catalog fallback for a product whose true-size 3D model
/// could not be resolved ([Product] lacks dimensions and has no ready AI
/// model). Mirrors the pre-Loop-3 behavior of mapping the product's
/// category onto a bundled .glb.
///
/// Returns null only when the product has no category to look up — the
/// caller then shows the plain catalog with an explanatory message instead.
ArFurnitureItem? fallbackFor(Product product) {
  final category = product.category.trim();
  if (category.isEmpty) return null;
  return ArFurnitureLibrary.forCategory(category);
}
