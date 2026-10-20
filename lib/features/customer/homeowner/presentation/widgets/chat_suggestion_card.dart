import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../models/chat_session.dart';
import '../../../../../shared/widgets/product_image.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import 'chat_card_actions.dart';

enum _CardOverflow {
  open,
  wishlist,
  qtyPlus,
  qtyMinus,
  remove,
  similar,
}

class ChatSuggestionCard extends ConsumerWidget {
  const ChatSuggestionCard({
    super.key,
    required this.suggestion,
    required this.actions,
    this.showPlace = true,
  });

  final ChatSuggestionSnapshot suggestion;
  final ChatCardActions actions;
  final bool showPlace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = suggestion;
    final inCart =
        ref.watch(cartProvider).any((item) => item.product.id == s.productId);
    final saved = ref.watch(wishlistProvider).contains(s.productId);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => actions.openProduct(s.productId),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ProductImage(
                      imageUrl: s.image,
                      width: 56,
                      height: 56,
                      errorIconSize: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          Formatters.myr(s.price),
                          style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                        if (s.reason.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            s.reason,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => actions.addToCart(s),
            icon: const Icon(Icons.add_shopping_cart, size: 16),
            label: Text(
              'Add',
              style: GoogleFonts.poppins(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 36),
              visualDensity: VisualDensity.compact,
            ),
          ),
          if (showPlace)
            TextButton.icon(
              onPressed: () => actions.placeInLayout(s),
              icon: const Icon(Icons.weekend_outlined, size: 16),
              label: Text(
                'Place',
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.secondaryAccent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                visualDensity: VisualDensity.compact,
              ),
            ),
          PopupMenuButton<_CardOverflow>(
            icon: const Icon(Icons.more_vert, size: 18),
            padding: EdgeInsets.zero,
            tooltip: 'More actions',
            color: AppColors.surface,
            onSelected: (choice) => _onChoice(ref, choice),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _CardOverflow.open,
                child: Text('Open product'),
              ),
              PopupMenuItem(
                value: _CardOverflow.wishlist,
                child: Text(saved ? 'Remove from wishlist' : 'Save to wishlist'),
              ),
              if (inCart) ...[
                const PopupMenuItem(
                  value: _CardOverflow.qtyPlus,
                  child: Text('Increase quantity'),
                ),
                const PopupMenuItem(
                  value: _CardOverflow.qtyMinus,
                  child: Text('Decrease quantity'),
                ),
                const PopupMenuItem(
                  value: _CardOverflow.remove,
                  child: Text('Remove from cart'),
                ),
              ] else
                const PopupMenuItem(
                  value: _CardOverflow.similar,
                  child: Text('See similar'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _onChoice(WidgetRef ref, _CardOverflow choice) {
    final s = suggestion;
    switch (choice) {
      case _CardOverflow.open:
        actions.openProduct(s.productId);
      case _CardOverflow.wishlist:
        actions.toggleWishlist(s);
      case _CardOverflow.qtyPlus:
        actions.bumpCartQty(s, 1);
      case _CardOverflow.qtyMinus:
        actions.bumpCartQty(s, -1);
      case _CardOverflow.remove:
        actions.removeFromCart(s);
      case _CardOverflow.similar:
        final category = _categoryOf(ref, s);
        if (category.isNotEmpty) actions.browseCategory(category);
    }
  }

  String _categoryOf(WidgetRef ref, ChatSuggestionSnapshot s) {
    final products = ref.read(marketplaceProductsProvider).valueOrNull;
    for (final p in products ?? const []) {
      if (p.id == s.productId) return p.category;
    }
    return '';
  }
}
