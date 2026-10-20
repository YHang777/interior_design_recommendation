import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/router/route_names.dart';
import '../../../../../models/cart_item.dart';
import '../../../../../models/chat_session.dart';
import '../../../../../models/product.dart';
import '../../../../../shared/widgets/app_feedback.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../providers/design_providers.dart';

class ChatCardActions {
  ChatCardActions({
    required this.context,
    required this.ref,
    this.onBeforeNavigate,
  });

  final BuildContext context;
  final WidgetRef ref;

  /// Lets a modal surface (the robot sheet) close before a route change.
  final VoidCallback? onBeforeNavigate;

  Product? _resolve(String productId) {
    final products = ref.read(marketplaceProductsProvider).valueOrNull;
    for (final p in products ?? const <Product>[]) {
      if (p.id == productId) return p;
    }
    return null;
  }

  CartItem? _cartItem(String productId) {
    for (final item in ref.read(cartProvider)) {
      if (item.product.id == productId) return item;
    }
    return null;
  }

  void addToCart(ChatSuggestionSnapshot suggestion) {
    final product = _resolve(suggestion.productId);
    if (product == null || !product.isActive || product.isOutOfStock) {
      showAppSnackbar(context, 'That item is no longer available.');
      return;
    }
    ref.read(cartProvider.notifier).addItem(product);
    showAddedToCartSnack(
      context,
      '${product.name} added to cart',
      onViewCart: openCart,
    );
  }

  void placeInLayout(ChatSuggestionSnapshot suggestion) {
    final product = _resolve(suggestion.productId);
    if (product == null) {
      showAppSnackbar(context, 'That item is no longer available.');
      return;
    }
    ref
        .read(pendingChatPlacementsProvider.notifier)
        .enqueue(chatPlacementForProduct(product));
    showAppSnackbar(
      context,
      '${product.name} added to your room plan',
      color: AppColors.success,
      actionLabel: 'View plan',
      onAction: openPlan,
    );
  }

  void toggleWishlist(ChatSuggestionSnapshot suggestion) {
    final product = _resolve(suggestion.productId);
    final name = product?.name ?? suggestion.name;
    final added = !ref.read(wishlistProvider).contains(suggestion.productId);
    ref.read(wishlistProvider.notifier).toggle(suggestion.productId);
    showAppSnackbar(
      context,
      added ? '$name saved to your wishlist' : '$name removed from your wishlist',
    );
  }

  void bumpCartQty(ChatSuggestionSnapshot suggestion, int delta) {
    final item = _cartItem(suggestion.productId);
    if (item == null) return;
    final next = item.quantity + delta;
    if (next < 1) {
      removeFromCart(suggestion);
      return;
    }
    ref.read(cartProvider.notifier).setQuantity(item.product.id, next);
  }

  void removeFromCart(ChatSuggestionSnapshot suggestion) {
    final item = _cartItem(suggestion.productId);
    if (item == null) return;
    final removed = item;
    ref.read(cartProvider.notifier).removeItem(removed.product.id);
    showAppSnackbar(
      context,
      '${removed.product.name} removed from cart',
      actionLabel: 'Undo',
      onAction: () => ref.read(cartProvider.notifier).restoreItem(removed),
    );
  }

  void openProduct(String productId) {
    context.pushNamed(
      RouteNames.homeownerProductDetail,
      pathParameters: {'id': productId},
    );
  }

  void browseCategory(String category) {
    resetMarketplaceFilters(ref);
    ref.read(selectedCategoryFilterProvider.notifier).state = category;
    _go('/marketplace');
  }

  void openCart() => context.pushNamed(RouteNames.homeownerCart);

  void openOrders() => context.pushNamed(RouteNames.homeownerOrderHistory);

  void openWishlist() => context.pushNamed(RouteNames.homeownerWishlist);

  void openBudget() => context.pushNamed(RouteNames.homeownerBudget);

  void openPlan() => _go('/design');

  void _go(String path) {
    final router = GoRouter.of(context);
    onBeforeNavigate?.call();
    router.go(path);
  }
}
