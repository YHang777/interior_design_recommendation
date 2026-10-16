import '../../../../core/utils/formatters.dart';
import '../../../../models/chat_session.dart';
import '../../../../models/product.dart';
import 'datasources/chat_datasource.dart';

// Proxy per-field limits — keep identical to the AI screen's historical
// clips so a long listing can never 400 the request.
const int kChatStyleClip = 120;
const int kChatDescriptionClip = 200;
const int kChatLabelLimit = 8;
const int kChatSummaryClip = 240;
const int kChatProductLimit = 12;

String _clip(String text, int max) =>
    text.length <= max ? text : text.substring(0, max);

/// Compact factual summary of a listing — stock, size, delivery, seller
/// verification, eco, sale — joined into one sentence.
///
/// `ChatProduct` has no fields for these facts, so they travel inside
/// [ChatProduct.description] where the model reads them alongside the
/// seller's copy. Fact-dense on purpose: the quick-question chips ask
/// exactly about these lines.
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

/// Maps one listing to what the chat proxy can carry.
///
/// Each entry includes the server's photo verdict alongside the seller's
/// own words — the model gets to see what the photo shows, not just the
/// description a seller typed. The [productFactsLine] summary is prepended
/// to [ChatProduct.description] (and hard-clipped) so the facts survive
/// the 200-char limit even for fact-dense products.
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

/// Active listings only, first [limit], mapped — the catalogue context the
/// assistant sees when recommending real items instead of made-up ones.
List<ChatProduct> productsToChatContext(
  Iterable<Product> products, {
  int limit = kChatProductLimit,
}) =>
    products.where((p) => p.isActive).take(limit).map(productToChatProduct).toList();

/// Turns the reply's ids into self-contained card snapshots (name, price,
/// photo) taken now, while the catalogue is loaded. Ids with no live
/// product are dropped — there is nothing to render or add.
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
