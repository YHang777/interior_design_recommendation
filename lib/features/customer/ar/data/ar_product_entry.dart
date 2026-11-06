import 'dart:io';
import 'dart:math' as math;

import '../../../../models/product.dart';
import 'glb_bounds.dart';

class ArProductEntry {
  ArProductEntry({
    required this.product,
    this.resolvedFile,
    this.productError,
  });

  GlbBounds? _cachedBounds;

  final Product product;

  final File? resolvedFile;

  final String? productError;

  bool get isResolved => resolvedFile != null;

  bool get hasError => productError != null;

  String get name => product.name;

  String get dimsLabel => product.dimensions?.label ?? '';

  bool get hasTrueDimensions => product.dimensions?.isComplete ?? false;

  double? get maxDimM {
    final d = product.dimensions;
    if (d == null || !d.isComplete) return null;
    return math.max(d.widthM, math.max(d.heightM, d.depthM));
  }

  GlbBounds get _bounds {
    final cached = _cachedBounds;
    if (cached != null) return cached;
    final file = resolvedFile;
    if (file == null) {
      throw StateError(
          'ArProductEntry.scaleToMeters: product "${product.id}" has no '
          'resolved GLB — refusing to guess a placement scale.');
    }
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
    return _cachedBounds = bounds;
  }

  // Resolved products render at GlbBounds scale (the pipeline bakes real
  // meters into the GLB), so world footprint == raw geometry bounds.
  double get scaleToMeters => _bounds.maxExtent;

  ({double widthM, double depthM, double centerX, double centerZ})?
      get worldFootprint {
    try {
      final b = _bounds;
      return (
        widthM: b.widthM,
        depthM: b.depthM,
        centerX: b.centerX,
        centerZ: b.centerZ,
      );
    } catch (_) {
      // No parseable geometry → no footprint → placement fails open (the
      // scale pipeline would refuse anyway before anything renders).
      return null;
    }
  }

  String get badgeText => 'AI';

  @override
  String toString() => 'ArProductEntry(${product.id}, $dimsLabel, '
      'resolved: $isResolved'
      '${productError == null ? '' : ', error: $productError'})';
}
