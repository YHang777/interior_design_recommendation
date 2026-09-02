import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/order.dart';
import '../../../../models/product.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/product_image.dart';
import '../../../../shared/widgets/quick_action_button.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../../../shared/widgets/stat_card.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/data/models/app_user.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../providers/supplier_providers.dart';

/// Supplier dashboard — live storefront snapshot with real Firestore data.
class SupplierDashboardScreen extends ConsumerStatefulWidget {
  const SupplierDashboardScreen({super.key});

  @override
  ConsumerState<SupplierDashboardScreen> createState() =>
      _SupplierDashboardScreenState();
}

class _SupplierDashboardScreenState
    extends ConsumerState<SupplierDashboardScreen> {
  Future<void> _refresh() async {
    final uid = ref.read(currentUserProvider)?.uid ?? '';
    try {
      await Future.wait([
        ref.refresh(marketplaceProductsProvider.future),
        ref.refresh(supplierOrdersProvider(uid).future),
      ]);
    } catch (_) {
      // Best effort pull-to-refresh.
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────

  void _goAddProduct() =>
      context.pushNamed(RouteNames.supplierProductNew);

  void _goTab(String routeName) => context.goNamed(routeName);

  void _goOrder(Order o) => context.pushNamed(
        RouteNames.supplierOrderDetail,
        pathParameters: {'id': o.id},
      );

  void _goProduct(Product p) => context.pushNamed(
        RouteNames.supplierProductEdit,
        pathParameters: {'id': p.id},
      );

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final uid = user?.uid ?? '';
    final productsAsync = ref.watch(marketplaceProductsProvider);
    final ordersAsync = ref.watch(supplierOrdersProvider(uid));

    final coldProducts = productsAsync.valueOrNull == null;
    final coldOrders = ordersAsync.valueOrNull == null;
    final failed = (coldProducts && productsAsync.hasError) ||
        (coldOrders && ordersAsync.hasError);

    final products = productsAsync.valueOrNull ?? const <Product>[];
    final allOrders = ordersAsync.valueOrNull ?? const <Order>[];
    final mine = productsOfSupplier(products, uid);

    final now = DateTime.now();
    final monthRevenue =
        revenueInMonth(allOrders, uid, DateTime(now.year, now.month));
    final pendingCount =
        allOrders.where((o) => o.status == OrderStatus.pending).length;
    final recentOrders = allOrders.take(3).toList();
    final lowStock = lowStockProducts(products, uid);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Dashboard')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.accent,
        child: user == null
            ? const EmptyState(
                icon: Icons.person_off_outlined,
                title: 'Not signed in',
                subtitle: 'Sign in as a supplier to manage your store.',
              )
            : failed
                ? _scrollable(
                    EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Could not load your store',
                      subtitle: 'Check your connection and try again.',
                      actionLabel: 'Retry',
                      onAction: _refresh,
                    ),
                  )
                : coldProducts || coldOrders
                    ? const _DashboardSkeleton()
                    : _content(user, mine, allOrders, monthRevenue,
                        pendingCount, recentOrders, lowStock),
      ),
    );
  }

  Widget _content(
    AppUser user,
    List<Product> mine,
    List<Order> allOrders,
    int monthRevenue,
    int pendingCount,
    List<Order> recentOrders,
    List<Product> lowStock,
  ) {
    final store = supplierFromUser(user);
    final greeting = switch (DateTime.now().hour) {
      >= 5 && < 12 => 'Good morning',
      >= 12 && < 18 => 'Good afternoon',
      _ => 'Good evening',
    };

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // ── Greeting header ──
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryLight],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$greeting, ${store.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textOnDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (store.isVerified)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified,
                              size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'Verified',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    StatusBadge.verification(
                        store.verificationStatus, compact: true),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                mine.isEmpty
                    ? 'Post your first product to start selling.'
                    : 'Your store has ${mine.length} '
                        '${mine.length == 1 ? 'product' : 'products'} live.',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Quick actions ──
        Row(
          children: [
            QuickActionButton(
              icon: Icons.add_business_outlined,
              label: 'Add product',
              gradient: const [AppColors.accent, AppColors.gradientGreen],
              onTap: _goAddProduct,
            ),
            QuickActionButton(
              icon: Icons.storefront_outlined,
              label: 'Products',
              gradient: const [AppColors.secondaryAccent, AppColors.gradientBlue],
              onTap: () => _goTab(RouteNames.supplierProducts),
            ),
            QuickActionButton(
              icon: Icons.receipt_long_outlined,
              label: 'Orders',
              gradient: const [AppColors.warning, AppColors.gradientOrange],
              onTap: () => _goTab(RouteNames.supplierOrders),
            ),
            QuickActionButton(
              icon: Icons.insights_outlined,
              label: 'Analytics',
              gradient: const [AppColors.primary, AppColors.primaryLight],
              onTap: () => _goTab(RouteNames.supplierAnalytics),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // ── Stats ──
        Row(
          children: [
            StatCard(
              icon: Icons.payments_outlined,
              label: 'Revenue this month',
              value: Formatters.myr(monthRevenue),
              gradient: const [AppColors.accent, AppColors.gradientGreen],
            ),
            const SizedBox(width: 10),
            StatCard(
              icon: Icons.hourglass_top_outlined,
              label: 'Pending orders',
              value: '$pendingCount',
              gradient: const [AppColors.warning, AppColors.gradientOrange],
              onTap: pendingCount > 0
                  ? () => _goTab(RouteNames.supplierOrders)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            StatCard(
              icon: Icons.visibility_outlined,
              label: 'Active products',
              value:
                  '${mine.where((p) => p.isActive).length}',
              gradient: const [AppColors.secondaryAccent, AppColors.gradientBlue],
              onTap: () => _goTab(RouteNames.supplierProducts),
            ),
            const SizedBox(width: 10),
            StatCard(
              icon: Icons.priority_high_outlined,
              label: 'Low stock',
              value: '${lowStock.length}',
              gradient: const [AppColors.primary, AppColors.primaryLight],
              onTap: lowStock.isNotEmpty
                  ? () => _goTab(RouteNames.supplierProducts)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── Recent orders ──
        SectionHeader(
          title: 'Recent orders',
          trailingLabel: allOrders.isEmpty ? null : 'View all',
          onTrailing: () => _goTab(RouteNames.supplierOrders),
        ),
        if (allOrders.isEmpty)
          _hintCard(
            icon: Icons.receipt_long_outlined,
            message: 'No orders yet — they appear here the moment a buyer '
                'checks out.',
          )
        else
          for (final order in recentOrders)
            _RecentOrderTile(
              order: order,
              supplierId: user.uid,
              onTap: () => _goOrder(order),
            ),

        // ── Inventory alerts ──
        SectionHeader(
          title: 'Inventory alerts',
          trailingLabel: lowStock.isEmpty ? null : 'View all',
          onTrailing: lowStock.isEmpty
              ? null
              : () => _goTab(RouteNames.supplierProducts),
        ),
        if (lowStock.isEmpty)
          _hintCard(
            icon: Icons.check_circle_outline,
            message: 'All stocked up — no products below 5 units.',
          )
        else
          for (final p in lowStock.take(3)) _LowStockTile(product: p, onTap: () => _goProduct(p)),
      ],
    );
  }

  Widget _hintCard({required IconData icon, required String message}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textHint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scrollable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }
}

/// ── Recent order row ────────────────────────────────────────────────────

class _RecentOrderTile extends StatelessWidget {
  const _RecentOrderTile({
    required this.order,
    required this.supplierId,
    required this.onTap,
  });

  final Order order;
  final String supplierId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = myLineItemCount(order, supplierId);
    final total = mySubtotal(order, supplierId);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Formatters.formatOrderNumber(order.orderNumber),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${order.customerName} · $count '
                      '${count == 1 ? 'item' : 'items'}',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
              StatusBadge.order(order.status, compact: true),
              const SizedBox(width: 10),
              Text(
                Formatters.myr(total),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ── Low stock row ───────────────────────────────────────────────────────

class _LowStockTile extends StatelessWidget {
  const _LowStockTile({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: ProductImage(
                    imageUrl: product.resolvedImages.isNotEmpty
                        ? product.resolvedImages.first
                        : '',
                    fit: BoxFit.cover,
                    errorIconSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  product.stock == 0
                      ? 'Out of stock'
                      : '${product.stock} left',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ── Loading skeleton ────────────────────────────────────────────────────

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget block(double h, [double? w]) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(8),
          ),
        );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          height: 84,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 14),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 8),
                    block(10, 46),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < 2; i++) ...[
          Container(
            height: 74,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 12),
        block(18, 130),
        const SizedBox(height: 10),
        for (var i = 0; i < 3; i++) ...[
          Container(
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
