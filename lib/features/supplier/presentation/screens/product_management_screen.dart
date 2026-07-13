import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/gradient_scaffold.dart';

/// Supplier product management — CRUD operations on products.
class ProductManagementScreen extends ConsumerStatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  ConsumerState<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState
    extends ConsumerState<ProductManagementScreen> {
  final _products = <_SP>[
    _SP('Oak Wood Flooring', 850, 45, 'assets/images/flooring.jpg', 'Flooring',
        'Modern'),
    _SP('Modern Sofa', 2400, 12, 'assets/images/sofa_modern.jpg', 'Furniture',
        'Modern'),
    _SP('Classic Dining Table', 1800, 8, 'assets/images/dining_table.jpg',
        'Furniture', 'Classic'),
    _SP('Modern Floor Lamp', 350, 30, 'assets/images/lamp_floor.jpg',
        'Lighting', 'Modern'),
    _SP('Classic Table Lamp', 280, 25, 'assets/images/lamp_table.jpg',
        'Lighting', 'Classic'),
    _SP('Modern Coffee Table', 650, 15, 'assets/images/coffee_table.jpg',
        'Furniture', 'Modern'),
  ];

  String _filter = 'All';

  List<_SP> get _filtered =>
      _filter == 'All'
          ? _products
          : _products.where((p) => p.style == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      child: Column(
        children: [
          // Filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _FilterChip('All', _filter == 'All', () => setState(() => _filter = 'All')),
                const SizedBox(width: 8),
                _FilterChip('Modern', _filter == 'Modern', () => setState(() => _filter = 'Modern')),
                const SizedBox(width: 8),
                _FilterChip('Classic', _filter == 'Classic', () => setState(() => _filter = 'Classic')),
                const Spacer(),
                IconButton(
                  onPressed: () => _showAddEditDialog(),
                  icon: const Icon(Icons.add_circle, color: Colors.white, size: 32),
                ),
              ],
            ),
          ),

          // Product list
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text('No products yet',
                            style: GoogleFonts.poppins(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) => _ProductTile(
                      product: _filtered[i],
                      onEdit: () => _showAddEditDialog(product: _filtered[i]),
                      onDelete: () {
                        setState(() => _products.remove(_filtered[i]));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Product deleted (mocked)')),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _showAddEditDialog({_SP? product}) {
    final nameCtrl = TextEditingController(text: product?.name ?? '');
    final priceCtrl = TextEditingController(text: product?.price.toString() ?? '');
    final stockCtrl = TextEditingController(text: product?.stock.toString() ?? '');
    String category = product?.category ?? 'Furniture';
    String style = product?.style ?? 'Modern';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(product != null ? 'Edit Product' : 'Add Product',
              style: GoogleFonts.poppins()),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
                const SizedBox(height: 10),
                TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price (RM)')),
                const SizedBox(height: 10),
                TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: ['Furniture', 'Flooring', 'Lighting', 'Decor', 'Paint']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => category = v!),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: style,
                  decoration: const InputDecoration(labelText: 'Style'),
                  items: ['Modern', 'Classic', 'Industrial', 'Scandinavian', 'Bohemian']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => style = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final newProduct = _SP(nameCtrl.text, int.tryParse(priceCtrl.text) ?? 0, int.tryParse(stockCtrl.text) ?? 0, 'assets/images/furniture_sofa_modern.png', category, style);
                setState(() {
                  if (product != null) {
                    final idx = _products.indexOf(product);
                    _products[idx] = newProduct;
                  } else {
                    _products.add(newProduct);
                  }
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(product != null ? 'Product updated (mocked)' : 'Product added (mocked)')));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SP {
  final String name, image, category, style;
  final int price, stock;
  const _SP(this.name, this.price, this.stock, this.image, this.category, this.style);
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(this.label, this.active, this.onTap);
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                color: active ? AppColors.primary : Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 13)),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onEdit, required this.onDelete});
  final _SP product;
  final VoidCallback onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(product.image, width: 60, height: 50, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.image)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                Text('RM ${product.price} • Stock: ${product.stock}',
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                Row(
                  children: [
                    _Badge(product.category, Colors.brown),
                    const SizedBox(width: 6),
                    _Badge(product.style, AppColors.secondary),
                  ],
                ),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: onEdit),
          IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), onPressed: onDelete),
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
      child: Text(text, style: GoogleFonts.poppins(fontSize: 10, color: color)),
    );
  }
}
