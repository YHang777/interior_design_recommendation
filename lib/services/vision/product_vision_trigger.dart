import 'package:flutter/foundation.dart' show debugPrint;

import '../../models/product.dart';
import 'product_vision_api.dart';

Future<ProductVision?> kickOffProductVisionAnalysis(
  Product product, {
  ProductVisionApi? api,
}) async {
  final id = product.id.trim();
  if (id.isEmpty) return null;
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
    debugPrint('[vision] analysis failed for $id: $e');
    return null;
  } finally {
    _inFlight.remove(id);
  }
}

final Set<String> _inFlight = <String>{};
