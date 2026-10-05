import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/order.dart';
import '../../../../models/product.dart';
import '../../../../services/verification/verification_application_model.dart';
import '../../../../services/verification/verification_application_service.dart';
import '../../../auth/data/models/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

/// Supplier-scoped providers and pure helpers shared by the seller screens
/// (dashboard, products, orders, analytics, profile).
///
/// Everything here derives from the marketplace Firestore streams already
/// exposed by [marketplace_providers.dart] — no extra repository API needed.

// ─── Supplier identity ────────────────────────────────────────────────────────

/// The signed-in supplier as a [Supplier] snapshot ready to be embedded into
/// every product they create. Built from the `users/{uid}` doc so product
/// listings carry the storefront's real identity (id = uid, business name,
/// contact details and verification status).
final currentSupplierProvider = Provider<Supplier?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return supplierFromUser(user);
});

/// Maps an [AppUser] to the [Supplier] snapshot embedded in products.
Supplier supplierFromUser(AppUser user) {
  final businessName =
      (user.businessName?.trim().isNotEmpty ?? false) ? user.businessName!.trim() : user.name;
  final businessPhone = (user.businessPhone?.trim().isNotEmpty ?? false)
      ? user.businessPhone!.trim()
      : (user.phone?.trim() ?? '');
  final businessAddress = (user.businessAddress?.trim().isNotEmpty ?? false)
      ? user.businessAddress!.trim()
      : (user.address?.trim() ?? '');
  return Supplier(
    id: user.uid,
    name: businessName,
    phone: businessPhone,
    address: businessAddress,
    email: user.email,
    verificationStatus: user.verificationStatus,
  );
}

// ─── Verification application ─────────────────────────────────────────────────

/// Supplier verification pipeline (submit / watch `verification_applications`).
final verificationApplicationServiceProvider =
    Provider<VerificationApplicationService>((ref) {
  return VerificationApplicationService();
});

/// Live `verification_applications/{uid}` for the signed-in supplier —
/// `null` until one has been submitted. Profile and dashboard watch this so
/// an admin's approval/rejection lands without a manual refresh (the profile
/// field itself only refreshes with the session).
final myVerificationApplicationProvider =
    StreamProvider<VerificationApplication?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream<VerificationApplication?>.value(null);
  return ref
      .watch(verificationApplicationServiceProvider)
      .watchMyApplication(user.uid);
});

// ─── Products (owned by the current supplier) ─────────────────────────────────

/// Products owned by [supplierId] — matched by the resolved supplier id
/// (never by name matching).
///
/// Must use [Product.resolvedSupplierId], not the raw top-level `supplierId`:
/// documents written before that field existed carry the owner only in the
/// nested `supplier.id`, so comparing the raw field silently drops every
/// legacy product from the seller's list.
List<Product> productsOfSupplier(
    Iterable<Product> products, String supplierId) {
  return products
      .where((p) => p.resolvedSupplierId == supplierId)
      .toList();
}

int activeProductsCount(Iterable<Product> products, String supplierId) =>
    productsOfSupplier(products, supplierId).where((p) => p.isActive).length;

/// Products with fewer than 5 units left (out-of-stock items are excluded —
/// they surface as "out of stock" instead of restock alerts).
List<Product> lowStockProducts(Iterable<Product> products, String supplierId) {
  return productsOfSupplier(products, supplierId)
      .where((p) => p.stock > 0 && p.stock < 5)
      .toList();
}

// ─── Order helpers (per-supplier views of shared orders) ──────────────────────

/// The [OrderItem]s in [order] that belong to [supplierId].
List<OrderItem> orderItemsForSupplier(Order order, String supplierId) =>
    order.items.where((i) => i.supplierId == supplierId).toList();

/// Number of line rows belonging to [supplierId].
int myLineItemCount(Order order, String supplierId) =>
    orderItemsForSupplier(order, supplierId).length;

/// Sum of line totals for [supplierId]'s items only.
int mySubtotal(Order order, String supplierId) => orderItemsForSupplier(order, supplierId)
    .fold(0, (sum, i) => sum + i.lineTotal);

/// [supplierId]'s delivery-charge share on this order — derived from the
/// product-level shipping settings recorded at checkout
/// (`Order.shippingShareFor`; 0 for orders/sellers that charge none).
int myShipping(Order order, String supplierId) =>
    order.shippingShareFor(supplierId);

/// Whether [order] contains anything fulfilled by [supplierId].
bool orderInvolvesSupplier(Order order, String supplierId) =>
    order.items.any((i) => i.supplierId == supplierId) ||
    order.resolvedSupplierIds.contains(supplierId);

// ─── Revenue semantics ────────────────────────────────────────────────────────
//
// Revenue = the supplier's item sales + their own shipping share (what the
// buyer actually paid them for fulfilment — never the whole order's fee on
// a shared order). Orders whose status is NOT cancelled count (pending,
// confirmed, shipped and delivered are all "sold"; a cancelled order is
// refunded and restocks, so it never contributes revenue). This single rule
// keeps the dashboard, analytics and top-product figures consistent.

/// Orders that count toward revenue for [supplierId].
Iterable<Order> revenueOrders(Iterable<Order> orders, String supplierId) =>
    orders.where((o) => orderInvolvesSupplier(o, supplierId) && o.status != OrderStatus.cancelled);

/// All-time revenue for [supplierId] (their items + their shipping share).
int totalRevenue(Iterable<Order> orders, String supplierId) =>
    revenueOrders(orders, supplierId)
        .fold(0, (sum, o) => sum + mySubtotal(o, supplierId) + myShipping(o, supplierId));

/// Revenue generated in the calendar month starting at [month].
int revenueInMonth(Iterable<Order> orders, String supplierId, DateTime month) {
  return revenueOrders(orders, supplierId)
      .where((o) =>
          o.createdAt.year == month.year && o.createdAt.month == month.month)
      .fold(0,
          (sum, o) => sum + mySubtotal(o, supplierId) + myShipping(o, supplierId));
}

// ─── Sales report metrics (pure — consumed by the sales report screen + PDF) ──

/// Units/revenue tally for one product across revenue-relevant orders.
class ProductTally {
  const ProductTally({
    required this.productId,
    required this.name,
    required this.image,
    required this.units,
    required this.revenue,
  });

  final String productId;
  final String name;
  final String image;

  /// Σ quantity of this supplier's line items for the product.
  final int units;

  /// Σ lineTotal of those items (items only — no shipping share).
  final int revenue;
}

/// Top [limit] products by units sold (ties broken by revenue, then taken),
/// over [revenueOrders] only — a cancelled order restocks and never counts.
List<ProductTally> topProductsByUnits(Iterable<Order> orders, String supplierId,
    {int limit = 5}) {
  final units = <String, int>{};
  final revenue = <String, int>{};
  final names = <String, String>{};
  final images = <String, String>{};
  for (final order in revenueOrders(orders, supplierId)) {
    for (final item in orderItemsForSupplier(order, supplierId)) {
      units[item.productId] = (units[item.productId] ?? 0) + item.quantity;
      revenue[item.productId] = (revenue[item.productId] ?? 0) + item.lineTotal;
      names.putIfAbsent(item.productId, () => item.name);
      images.putIfAbsent(item.productId, () => item.image);
    }
  }
  final tallies = [
    for (final id in units.keys)
      ProductTally(
        productId: id,
        name: names[id] ?? '',
        image: images[id] ?? '',
        units: units[id]!,
        revenue: revenue[id] ?? 0,
      ),
  ]..sort((a, b) {
      final byUnits = b.units.compareTo(a.units);
      return byUnits != 0 ? byUnits : b.revenue.compareTo(a.revenue);
    });
  return tallies.take(limit).toList();
}

/// Customer-side summary of a supplier's sold orders — every figure derived
/// from [revenueOrders] (cancelled excluded) so it can never disagree with
/// the revenue numbers shown next to it. Rates are 0–1 doubles; the UI/PDF
/// formats them as percentages. Nullable rates stay null (shown as '—')
/// rather than reporting a misleading 0%.
class CustomerInsights {
  const CustomerInsights({
    required this.uniqueCustomers,
    required this.repeatCustomers,
    required this.newCustomers,
    this.retentionRate,
    this.repeatPurchaseRate,
    this.avgOrderValue,
  });

  /// Distinct customers with at least one sold order.
  final int uniqueCustomers;

  /// Customers with >= 2 sold orders.
  final int repeatCustomers;

  /// Customers whose earliest sold order falls inside the lookback window.
  final int newCustomers;

  /// repeatCustomers / uniqueCustomers — null when there are no customers.
  final double? retentionRate;

  /// Orders placed by repeat customers / all sold orders — null when none.
  final double? repeatPurchaseRate;

  /// totalRevenue / sold.length (whole ringgit) — null when there are none.
  final int? avgOrderValue;
}

/// Builds [CustomerInsights] for [supplierId]. "New" means the customer's
/// earliest sold order was placed within the last [windowMonths] calendar
/// months counting the current month (first day of that month onward).
CustomerInsights customerInsights(Iterable<Order> orders, String supplierId,
    {DateTime? now, int windowMonths = 6}) {
  final nowAt = now ?? DateTime.now();
  final sold = revenueOrders(orders, supplierId).toList();
  final byCustomer = <String, List<Order>>{};
  for (final order in sold) {
    byCustomer.putIfAbsent(order.customerId, () => <Order>[]).add(order);
  }

  final unique = byCustomer.length;
  final repeatLists =
      byCustomer.values.where((list) => list.length >= 2).toList();
  final repeat = repeatLists.length;
  final repeatOrders = repeatLists.fold<int>(0, (sum, list) => sum + list.length);

  // Window start = first day of the month [windowMonths - 1] months ago, so
  // a 6-month window covers the current month plus the 5 before it.
  final windowStart = DateTime(nowAt.year, nowAt.month - (windowMonths - 1), 1);
  var newCustomers = 0;
  for (final list in byCustomer.values) {
    final earliest =
        list.map((o) => o.createdAt).reduce((a, b) => a.isBefore(b) ? a : b);
    if (!earliest.isBefore(windowStart)) newCustomers++;
  }

  return CustomerInsights(
    uniqueCustomers: unique,
    repeatCustomers: repeat,
    newCustomers: newCustomers,
    retentionRate: unique == 0 ? null : repeat / unique,
    repeatPurchaseRate: sold.isEmpty ? null : repeatOrders / sold.length,
    avgOrderValue:
        sold.isEmpty ? null : totalRevenue(orders, supplierId) ~/ sold.length,
  );
}

/// ratingCount-weighted average rating Σ(rating × ratingCount)/Σ(ratingCount)
/// across [supplierId]'s listings — null when nothing has been rated yet
/// (never 0.0, which would read as "one star").
double? averageProductRating(Iterable<Product> products, String supplierId) {
  var weighted = 0.0;
  var count = 0;
  for (final product in productsOfSupplier(products, supplierId)) {
    if (product.ratingCount <= 0) continue;
    weighted += product.rating * product.ratingCount;
    count += product.ratingCount;
  }
  if (count == 0) return null;
  return weighted / count;
}

/// Orders involving [supplierId] that reached delivered.
int deliveredCount(Iterable<Order> orders, String supplierId) => orders
    .where((o) =>
        orderInvolvesSupplier(o, supplierId) && o.status == OrderStatus.delivered)
    .length;

/// Delivered ÷ all orders involving [supplierId] (cancelled orders stay in
/// the denominator — they were real orders that fell through). Null when the
/// supplier has no orders at all. This is a fulfilment rate, not an ad/click
/// funnel: there is no click funnel in this app and the UI must never imply
/// one.
double? conversionRate(Iterable<Order> orders, String supplierId) {
  final all = orders.where((o) => orderInvolvesSupplier(o, supplierId)).length;
  if (all == 0) return null;
  return deliveredCount(orders, supplierId) / all;
}
