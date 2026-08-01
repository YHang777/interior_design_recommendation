import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/skeleton_loader.dart';
import '../../../../../models/product.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import 'product_form_screen.dart';

/// Supplier product management — CRUD via API, search, filter.
class ProductManagementScreen extends ConsumerWidget {
  const ProductManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(marketplaceProductsProvider);
    final user = ref.watch(currentUserProvider);
    final supplierName = user?.name ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Products'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.textOnDark),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ProductFormScreen()),
            ),
          ),
        ],
      ),
      body: productsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: SkeletonLoader(count: 6),
        ),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Failed to load products',
          actionLabel: 'Retry',
          onAction: () =>
              ref.invalidate(marketplaceProductsProvider),
        ),
        data: (products) {
          final myProducts = supplierName.isNotEmpty
              ? products
                  .where((p) =>
                      p.supplier.name.toLowerCase() ==
                      supplierName.toLowerCase())
                  .toList()
              : products;

          if (myProducts.isEmpty) {
            return EmptyState(
              icon: Icons.inventory_2,
              title: 'No products yet',
              subtitle:
                  'Add your first product to start selling',
              actionLabel: 'Add Product',
              onAction: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const ProductFormScreen()),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(marketplaceProductsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: myProducts.length,
              itemBuilder: (context, index) {
                final product = myProducts[index];
                return _ProductTile(
                  product: product,
                  onEdit: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ProductFormScreen(
                            existingProduct: product)),
                  ),
                  onDelete: () =>
                      _confirmDelete(context, ref, product),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, Product product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text(
            'Delete "${product.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(marketplaceServiceProvider)
                    .deleteProduct(product.id);
                ref.invalidate(marketplaceProductsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content:
                          Text('${product.name} deleted'),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed: $e'),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.onEdit,
    required this.onDelete,
  });

  final Product product;
  final VoidCallback onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              product.image,
              width: 64,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 64,
                height: 56,
                color: AppColors.divider,
                child: const Icon(Icons.image,
                    color: AppColors.textHint),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(Formatters.myr(product.price),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accent)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _Badge(product.category,
                        AppColors.accent),
                    const SizedBox(width: 6),
                    _Badge(product.designStyle,
                        AppColors.primary),
                    if (product.isEcoFriendly) ...[
                      const SizedBox(width: 6),
                      _Badge('Eco', AppColors.success),
                    ],
                    const Spacer(),
                    Text(
                      product.isOutOfStock
                          ? 'Out of Stock'
                          : product.isLowStock
                              ? 'Only ${product.stock} left'
                              : 'Stock: ${product.stock}',
                      style: TextStyle(
                        fontSize: 11,
                        color: product.isOutOfStock
                            ? AppColors.error
                            : product.isLowStock
                                ? AppColors.warning
                                : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 20, color: AppColors.textSecondary),
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 20, color: AppColors.error),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color)),
    );
  }
}
