import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../models/product.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';

/// Full-screen form for adding or editing a product.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.existingProduct});

  final Product? existingProduct;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _descCtrl;
  late String _category;
  late String _style;
  late String _image;
  late bool _isEco;
  bool _saving = false;

  bool get _isEditing => widget.existingProduct != null;

  static const _imageOptions = [
    'assets/images/furniture_sofa_modern.png',
    'assets/images/furniture_sofa_classic.png',
    'assets/images/furniture_chair_modern.png',
    'assets/images/furniture_chair_classic.png',
    'assets/images/furniture_table_coffee.png',
    'assets/images/furniture_table_dining.png',
    'assets/images/furniture_bed_modern.png',
    'assets/images/furniture_bed_classic.png',
    'assets/images/furniture_lamp_floor.png',
    'assets/images/furniture_lamp_table.png',
    'assets/images/furniture_rug_modern.png',
    'assets/images/furniture_rug_classic.png',
    'assets/images/wall_white_glossy.png',
    'assets/images/wall_texture_wood_walnut.png',
    'assets/images/flooring.jpg',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.existingProduct;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _priceCtrl =
        TextEditingController(text: p?.price.toString() ?? '');
    _stockCtrl =
        TextEditingController(text: p?.stock.toString() ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _category = p?.category ?? 'Furniture';
    _style = p?.designStyle ?? 'Modern';
    _image = p?.image ?? _imageOptions.first;
    _isEco = p?.isEcoFriendly ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    setState(() => _saving = true);

    final user = ref.read(currentUserProvider);
    final service = ref.read(marketplaceServiceProvider);

    final product = Product(
      id: widget.existingProduct?.id ?? '',
      name: _nameCtrl.text.trim(),
      price: int.tryParse(_priceCtrl.text.trim()) ?? 0,
      stock: int.tryParse(_stockCtrl.text.trim()) ?? 0,
      image: _image,
      description: _descCtrl.text.trim(),
      designStyle: _style,
      category: _category,
      supplier: Supplier(
        id: user?.uid ?? 'unknown',
        name: user?.name ?? 'Unknown Supplier',
        phone: user?.phone ?? '',
        address: user?.address ?? '',
        email: user?.email ?? '',
      ),
      isEcoFriendly: _isEco,
      rating: widget.existingProduct?.rating ?? 4.5,
      ratingCount: widget.existingProduct?.ratingCount ?? 0,
    );

    try {
      if (_isEditing) {
        await service.updateProduct(product.id, product);
      } else {
        await service.createProduct(product);
      }
      ref.invalidate(marketplaceProductsProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing
                ? 'Product updated'
                : 'Product added'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final stylesAsync = ref.watch(stylesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title:
            Text(_isEditing ? 'Edit Product' : 'Add Product'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Name
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Product Name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
            ),
            const SizedBox(height: 12),

            // Price
            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(
                  labelText: 'Price (RM)'),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty)
                  return 'Price is required';
                if (int.tryParse(v.trim()) == null)
                  return 'Enter a valid number';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Stock
            TextFormField(
              controller: _stockCtrl,
              decoration:
                  const InputDecoration(labelText: 'Stock'),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty)
                  return 'Stock is required';
                if (int.tryParse(v.trim()) == null)
                  return 'Enter a valid number';
                return null;
              },
            ),

            // Description
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                  labelText: 'Description'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),

            // Category (from API)
            categoriesAsync.when(
              data: (cats) => DropdownButtonFormField<String>(
                value: cats.any((c) => c.name == _category)
                    ? _category
                    : null,
                decoration:
                    const InputDecoration(labelText: 'Category'),
                items: cats
                    .map((c) => DropdownMenuItem(
                          value: c.name,
                          child: Text(c.name),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _category = v!),
              ),
              loading: () => const SizedBox(height: 56),
              error: (_, __) =>
                  TextFormField(
                    controller: TextEditingController(
                        text: _category),
                    decoration: const InputDecoration(
                        labelText: 'Category'),
                    onChanged: (v) => _category = v,
                  ),
            ),
            const SizedBox(height: 12),

            // Style (from API)
            stylesAsync.when(
              data: (styles) => DropdownButtonFormField<String>(
                value: styles.contains(_style)
                    ? _style
                    : null,
                decoration:
                    const InputDecoration(labelText: 'Style'),
                items: styles
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _style = v!),
              ),
              loading: () => const SizedBox(height: 56),
              error: (_, __) =>
                  TextFormField(
                    controller: TextEditingController(
                        text: _style),
                    decoration: const InputDecoration(
                        labelText: 'Style'),
                    onChanged: (v) => _style = v,
                  ),
            ),
            const SizedBox(height: 12),

            // Eco-friendly
            SwitchListTile(
              value: _isEco,
              onChanged: (v) =>
                  setState(() => _isEco = v),
              title: const Text('Eco-Friendly'),
              subtitle: const Text(
                  'Made from sustainable materials'),
              activeColor: AppColors.success,
            ),

            // Image picker
            const SizedBox(height: 8),
            const Text('Product Image',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _imageOptions.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final img = _imageOptions[i];
                  final selected = img == _image;
                  return GestureDetector(
                    onTap: () =>
                        setState(() => _image = img),
                    child: Container(
                      width: 80,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? AppColors.accent
                              : AppColors.border,
                          width: selected ? 2.5 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(9),
                        child: Image.asset(img,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.image)),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Save
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      vertical: 16),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white),
                      )
                    : Text(_isEditing
                        ? 'Update Product'
                        : 'Add Product'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
