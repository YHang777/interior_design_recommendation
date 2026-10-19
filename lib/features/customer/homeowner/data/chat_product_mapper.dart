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

/// Catalogue window size. Matches the proxy's own `MAX_PRODUCTS` cap —
/// anything above 20 is silently dropped server-side, so sending more only
/// wastes bytes. Wide enough that a supplier's new listing survives a
/// non-default sort, and that a filtered browse still shows the model enough
/// to recommend from.
const int kChatProductLimit = 20;

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

/// Active listings only, newest-first, first [limit], mapped — the catalogue
/// context the assistant sees when recommending real items instead of
/// made-up ones.
///
/// Newest-first is deliberate. A listing published a minute ago has to win a
/// slot in the window even when the caller hands over a price-sorted or
/// top-rated list; otherwise "what's new?" is unanswerable and the assistant
/// only ever rehashes whatever happened to sort first. Listings with no
/// `createdAt` (legacy seed rows) keep their relative order and sort to the
/// end, where they still fill whatever slots remain.
///
/// The caller's list is the whole scope: the AI tab passes the full live
/// catalogue, the marketplace robot passes the buyer's current filtered
/// browse. A product outside that list is deliberately out of scope — the
/// filter is doing its job, and a new listing that matches the filter is
/// already in the live stream, so this sort is what surfaces it.
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
