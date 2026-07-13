import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../models/product.dart';
import '../../../../shared/widgets/gradient_scaffold.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';

/// Marketplace — browse, filter, and purchase furniture & materials.
class MarketplaceScreen extends ConsumerWidget {
  const MarketplaceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(marketplaceProductsProvider);
    final filtered = ref.watch(filteredProductsProvider);
    final filter = ref.watch(selectedStyleFilterProvider);
    final cart = ref.watch(cartProvider);

    return GradientScaffold(
      child: Column(
        children: [
          // ── Header ──
          _MarketplaceHeader(cartCount: cart.length, ref: ref),
          const SizedBox(height: 12),

          // ── Filter ──
          _FilterBar(selected: filter, ref: ref),
          const SizedBox(height: 12),

          // ── Product Grid ──
          Expanded(
            child: productsAsync.when(
              data: (_) => filtered.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.store, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No products found',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : _ProductGrid(products: filtered, ref: ref),
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text('Failed to load products',
                        style: GoogleFonts.poppins(color: Colors.red)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () =>
                          ref.invalidate(marketplaceProductsProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header ───

class _MarketplaceHeader extends StatelessWidget {
  const _MarketplaceHeader({required this.cartCount, required this.ref});

  final int cartCount;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Marketplace',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined,
                    color: Colors.white, size: 28),
                onPressed: () => _showCartBottomSheet(context, ref),
              ),
              if (cartCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$cartCount',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Filter Bar ───

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.ref});

  final String selected;
  final WidgetRef ref;

  static const _styles = [
    'All',
    'Modern',
    'Classic',
    'Industrial',
    'Scandinavian',
    'Bohemian',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: selected,
            isExpanded: true,
            dropdownColor: Colors.white,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
            icon:
                const Icon(Icons.expand_more, color: AppColors.textPrimary),
            items: _styles.map((style) {
              return DropdownMenuItem(
                value: style,
                child: Text(style),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                ref.read(selectedStyleFilterProvider.notifier).state = value;
              }
            },
          ),
        ),
      ),
    );
  }
}

// ─── Product Grid ───

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.products, required this.ref});

  final List<Product> products;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600
            ? 4
            : constraints.maxWidth > 400
                ? 3
                : 2;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.72,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              return _ProductCard(
                product: products[index],
                onAddToCart: () {
                  final cart = ref.read(cartProvider);
                  ref.read(cartProvider.notifier).state = [...cart, products[index]];
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${products[index].name} added to cart'),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ─── Product Card ───

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onAddToCart});

  final Product product;
  final VoidCallback onAddToCart;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 180;
        return GestureDetector(
          onTap: () => _showProductDetail(context),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    child: Image.asset(
                      product.image,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.image,
                            size: 32, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                // Info
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 8 : 12,
                      vertical: compact ? 6 : 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: compact ? 12 : 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.brown.shade900,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'RM ${product.price}',
                          style: GoogleFonts.poppins(
                            fontSize: compact ? 13 : 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF4CAF50),
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.brown.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                product.category,
                                style: GoogleFonts.poppins(
                                    fontSize: compact ? 9 : 10,
                                    color: Colors.brown.shade700),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Stock: ${product.stock}',
                              style: GoogleFonts.poppins(
                                fontSize: compact ? 9 : 10,
                                color: product.stock > 0
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showProductDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ProductDetailSheet(
          product: product, onAddToCart: onAddToCart),
    );
  }
}

// ─── Product Detail Sheet ───

class _ProductDetailSheet extends StatelessWidget {
  const _ProductDetailSheet({required this.product, required this.onAddToCart});

  final Product product;
  final VoidCallback onAddToCart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  product.image,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 80,
                    height: 80,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image, color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.name,
                        style: GoogleFonts.poppins(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('RM ${product.price}',
                        style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF4CAF50))),
                    Text(
                        product.stock > 0
                            ? 'In Stock (${product.stock} available)'
                            : 'Out of Stock',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: product.stock > 0
                                ? Colors.green
                                : Colors.red)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text('Supplier',
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          _buildDetailRow(Icons.business, product.supplier.name),
          _buildDetailRow(Icons.phone, product.supplier.phone),
          _buildDetailRow(Icons.email, product.supplier.email),
          _buildDetailRow(Icons.location_on, product.supplier.address),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onAddToCart,
                  icon: const Icon(Icons.add_shopping_cart, size: 20),
                  label: const Text('Add to Cart'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.brown.shade400),
          const SizedBox(width: 8),
          Text(text,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.brown.shade700)),
        ],
      ),
    );
  }
}

// ─── Cart Bottom Sheet ───

void _showCartBottomSheet(BuildContext context, WidgetRef ref) {
  final cart = ref.read(cartProvider);

  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Shopping Cart',
                style: GoogleFonts.poppins(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (cart.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.shopping_cart_outlined,
                          size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('Your cart is empty',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              )
            else ...[
              ...cart.map((product) => ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(product.image,
                          width: 48, height: 48, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.image)),
                    ),
                    title: Text(product.name,
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500, fontSize: 14)),
                    subtitle: Text('RM ${product.price}',
                        style: GoogleFonts.poppins(
                            color: const Color(0xFF4CAF50), fontSize: 13)),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          color: Colors.red),
                      onPressed: () {
                        final updated = List<Product>.from(cart);
                        updated.removeWhere((p) => p.id == product.id);
                        ref.read(cartProvider.notifier).state = updated;
                      },
                    ),
                  )),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total: RM ${cart.fold<int>(0, (sum, p) => sum + p.price)}',
                    style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      ref.read(cartProvider.notifier).state = [];
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Checkout complete (mocked)'),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('Checkout'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    },
  );
}
