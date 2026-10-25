import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/order.dart';
import '../../../../models/product.dart';
import '../../../../services/verification/verification_application_model.dart';
import '../../../../services/verification/verification_application_service.dart';
import '../../../auth/data/models/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

// ─── Supplier identity ────────────────────────────────────────────────────────

final currentSupplierProvider = Provider<Supplier?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return supplierFromUser(user);
});

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

final verificationApplicationServiceProvider =
    Provider<VerificationApplicationService>((ref) {
  return VerificationApplicationService();
});

final myVerificationApplicationProvider =
    StreamProvider<VerificationApplication?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream<VerificationApplication?>.value(null);
  return ref
      .watch(verificationApplicationServiceProvider)
      .watchMyApplication(user.uid);
});

// ─── Products (owned by the current supplier) ─────────────────────────────────

List<Product> productsOfSupplier(
    Iterable<Product> products, String supplierId) {
  return products
      .where((p) => p.resolvedSupplierId == supplierId)
      .toList();
}

int activeProductsCount(Iterable<Product> products, String supplierId) =>
    productsOfSupplier(products, supplierId).where((p) => p.isActive).length;

List<Product> lowStockProducts(Iterable<Product> products, String supplierId) {
  return productsOfSupplier(products, supplierId)
      .where((p) => p.stock > 0 && p.stock < 5)
      .toList();
}

// ─── Order helpers (per-supplier views of shared orders) ──────────────────────

List<OrderItem> orderItemsForSupplier(Order order, String supplierId) =>
    order.items.where((i) => i.supplierId == supplierId).toList();

int myLineItemCount(Order order, String supplierId) =>
    orderItemsForSupplier(order, supplierId).length;

int mySubtotal(Order order, String supplierId) => orderItemsForSupplier(order, supplierId)
    .fold(0, (sum, i) => sum + i.lineTotal);

bool orderInvolvesSupplier(Order order, String supplierId) =>
    order.items.any((i) => i.supplierId == supplierId) ||
    order.resolvedSupplierIds.contains(supplierId);

// ─── Revenue semantics ────────────────────────────────────────────────────────

Iterable<Order> revenueOrders(Iterable<Order> orders, String supplierId) =>
    orders.where((o) => orderInvolvesSupplier(o, supplierId) && o.status != OrderStatus.cancelled);

int totalRevenue(Iterable<Order> orders, String supplierId) =>
    revenueOrders(orders, supplierId)
        .fold(0, (sum, o) => sum + mySubtotal(o, supplierId));

int revenueInMonth(Iterable<Order> orders, String supplierId, DateTime month) {
  return revenueOrders(orders, supplierId)
      .where((o) =>
          o.createdAt.year == month.year && o.createdAt.month == month.month)
      .fold(0, (sum, o) => sum + mySubtotal(o, supplierId));
}

// ─── Sales report metrics (pure — consumed by the sales report screen + PDF) ──

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

  final int units;

  final int revenue;
}

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

class CustomerInsights {
  const CustomerInsights({
    required this.uniqueCustomers,
    required this.repeatCustomers,
    required this.newCustomers,
    this.retentionRate,
    this.repeatPurchaseRate,
    this.avgOrderValue,
  });

  final int uniqueCustomers;

  final int repeatCustomers;

  final int newCustomers;

  final double? retentionRate;

  final double? repeatPurchaseRate;

  final int? avgOrderValue;
}

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

int collectedCount(Iterable<Order> orders, String supplierId) => orders
    .where((o) =>
        orderInvolvesSupplier(o, supplierId) && o.status == OrderStatus.collected)
    .length;

double? conversionRate(Iterable<Order> orders, String supplierId) {
  final all = orders.where((o) => orderInvolvesSupplier(o, supplierId)).length;
  if (all == 0) return null;
  return collectedCount(orders, supplierId) / all;
}
