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

  double? _cachedScaleToMeters;

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

  double get scaleToMeters {
    final cached = _cachedScaleToMeters;
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
    return _cachedScaleToMeters = extent;
  }

  String get badgeText => 'AI';

  @override
  String toString() => 'ArProductEntry(${product.id}, $dimsLabel, '
      'resolved: $isResolved'
      '${productError == null ? '' : ', error: $productError'})';
}
