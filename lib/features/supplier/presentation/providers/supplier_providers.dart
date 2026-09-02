import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/order.dart';
import '../../../../models/product.dart';
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

// ─── Products (owned by the current supplier) ─────────────────────────────────

/// Products owned by [supplierId] — matched by the top-level `supplierId`
/// field (never by name matching).
List<Product> productsOfSupplier(
    Iterable<Product> products, String supplierId) {
  return products.where((p) => p.supplierId == supplierId).toList();
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

/// Whether [order] contains anything fulfilled by [supplierId].
bool orderInvolvesSupplier(Order order, String supplierId) =>
    order.items.any((i) => i.supplierId == supplierId) ||
    order.resolvedSupplierIds.contains(supplierId);

// ─── Revenue semantics ────────────────────────────────────────────────────────
//
// Revenue helpers count orders whose status is NOT cancelled (pending,
// confirmed, shipped and delivered are all "sold"; a cancelled order is
// refunded and restocks, so it never contributes revenue). This single rule
// keeps the dashboard, analytics and top-product figures consistent.

/// Orders that count toward revenue for [supplierId].
Iterable<Order> revenueOrders(Iterable<Order> orders, String supplierId) =>
    orders.where((o) => orderInvolvesSupplier(o, supplierId) && o.status != OrderStatus.cancelled);

/// All-time revenue for [supplierId] (their items only).
int totalRevenue(Iterable<Order> orders, String supplierId) =>
    revenueOrders(orders, supplierId).fold(0, (sum, o) => sum + mySubtotal(o, supplierId));

/// Revenue generated in the calendar month starting at [month].
int revenueInMonth(Iterable<Order> orders, String supplierId, DateTime month) {
  return revenueOrders(orders, supplierId)
      .where((o) =>
          o.createdAt.year == month.year && o.createdAt.month == month.month)
      .fold(0, (sum, o) => sum + mySubtotal(o, supplierId));
}
