import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/product.dart';
import 'product_vision_api.dart';

/// Fire-and-forget entry point of the upload-time photo analysis — call it
/// with the product returned by a create/update save (the product form's
/// `_submit`). Mirrors `kickOffProduct3DGeneration`: never throws, and a
/// failure can never block publishing.
///
/// Returns the verdict so the form can show a mismatch warning
/// (`vision.mismatchFlagged`), or null when there is nothing to analyze
/// (no network photo) or the call failed.
///
/// Re-entrancy: one analysis per product id at a time — a second kick-off
/// while one is in flight returns null instead of paying for a duplicate
/// vision call.
Future<ProductVision?> kickOffProductVisionAnalysis(
  Product product, {
  ProductVisionApi? api,
}) async {
  final id = product.id.trim();
  if (id.isEmpty) return null;
  // Asset/local photos cannot be fetched by the server — nothing to analyze.
  if (!product.hasNetworkImage) return null;
  if (!_inFlight.add(id)) {
    debugPrint('[vision] analysis already in flight for $id — skipping');
    return null;
  }
  try {
    final vision = await (api ?? ProductVisionApi()).analyze(productId: id);
    debugPrint('[vision] "${product.name}" ($id): ${vision.status}'
        '${vision.mismatchFlagged ? ' — MISMATCH: ${vision.mismatchReason}' : ''}');
    return vision;
  } catch (e) {
    // Save already succeeded — a quiet failure keeps the old behavior and
    // the admin flag queue stays the safety net.
    debugPrint('[vision] analysis failed for $id: $e');
    return null;
  } finally {
    _inFlight.remove(id);
  }
}

final Set<String> _inFlight = <String>{};
