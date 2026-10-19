import '../../../../core/utils/formatters.dart';
import '../../../../models/chat_session.dart';
import '../../../../models/product.dart';
import 'datasources/chat_datasource.dart';

const int kChatStyleClip = 120;
const int kChatDescriptionClip = 200;
const int kChatLabelLimit = 8;
const int kChatSummaryClip = 240;

const int kChatProductLimit = 20;

String _clip(String text, int max) =>
    text.length <= max ? text : text.substring(0, max);

String productFactsLine(Product product) {
  final segments = <String>[];
  if (product.isOutOfStock) {
    segments.add('Out of stock');
  } else if (product.isLowStock) {
    segments.add('Only ${product.stock} left');
  } else {
    segments.add('In stock');
  }
  final dims = product.dimensions;
  if (dims != null && dims.isComplete) {
    segments.add('Dimensions ${dims.label}');
  }
  if (product.shippingCharge > 0) {
    segments.add('Delivery ${Formatters.myr(product.shippingCharge)}');
    if (product.shippingLongDistanceNotice) {
      segments.add(Product.longDistanceNotice);
    }
  } else {
    segments.add('Free delivery');
  }
  if (product.supplier.isVerified) segments.add('Verified seller');
  if (product.isEcoFriendly) segments.add('Eco-friendly');
  final discount = product.discountPercent;
  if (discount != null) segments.add('$discount% off');
  return segments.join('. ');
}

ChatProduct productToChatProduct(Product product) {
  final vision = product.vision;
  final verified = vision != null && vision.isOk;
  final facts = productFactsLine(product);
  final sellerCopy = product.description.trim();
  final description =
      sellerCopy.isEmpty ? '$facts.' : '$facts. $sellerCopy';
  return ChatProduct(
    id: product.id,
    name: product.name,
    price: product.price,
    category: product.category,
    designStyle: _clip(product.designStyle, kChatStyleClip),
    description: _clip(description, kChatDescriptionClip),
    photoLabels: verified
        ? vision.labels.take(kChatLabelLimit).toList(growable: false)
        : const [],
    photoSummary: verified ? _clip(vision.summary, kChatSummaryClip) : null,
    photoMismatch: verified && vision.mismatchFlagged,
  );
}

List<ChatProduct> productsToChatContext(
  Iterable<Product> products, {
  int limit = kChatProductLimit,
}) {
  final active = products.where((p) => p.isActive).toList();
  active.sort((a, b) {
    final at = a.createdAt;
    final bt = b.createdAt;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });
  return active.take(limit).map(productToChatProduct).toList();
}

List<ChatSuggestionSnapshot> hydrateChatSuggestions(
  List<ChatSuggestionRef> refs,
  List<Product> liveProducts,
) {
  if (refs.isEmpty) return const [];
  final byId = {for (final p in liveProducts) p.id: p};
  final out = <ChatSuggestionSnapshot>[];
  for (final s in refs) {
    final product = byId[s.productId];
    if (product == null) continue;
    out.add(ChatSuggestionSnapshot(
      productId: s.productId,
      name: product.name,
      price: product.price,
      image: product.image,
      reason: s.reason,
    ));
  }
  return out;
}
