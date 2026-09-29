import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/product.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/verify_email_screen.dart';
import '../../features/customer/budget/presentation/screens/budget_planner_screen.dart';
import '../../features/customer/homeowner/presentation/screens/ai_recommendation_screen.dart';
import '../../features/customer/homeowner/presentation/screens/dashboard_screen.dart';
import '../../features/customer/homeowner/presentation/screens/homeowner_shell.dart';
import '../../features/customer/homeowner/presentation/screens/profile_screen.dart';
import '../../features/customer/homeowner/presentation/screens/saved_designs_screen.dart';

import '../../features/supplier/presentation/screens/analytics_screen.dart';
import '../../features/supplier/presentation/screens/order_management_screen.dart';
import '../../features/supplier/presentation/screens/product_form_screen.dart';
import '../../features/supplier/presentation/screens/product_management_screen.dart';
import '../../features/supplier/presentation/screens/supplier_dashboard_screen.dart';
import '../../features/supplier/presentation/screens/supplier_profile_screen.dart';
import '../../features/supplier/presentation/screens/supplier_shell.dart';
import '../../features/supplier/presentation/screens/verification_application_screen.dart';

// Marketplace feature
import '../../features/customer/marketplace/presentation/screens/marketplace_screen.dart';
import '../../features/customer/marketplace/presentation/screens/product_detail_screen.dart';
import '../../features/customer/marketplace/presentation/screens/cart_screen.dart';
import '../../features/customer/marketplace/presentation/screens/checkout_screen.dart';
import '../../features/customer/marketplace/presentation/screens/order_confirmation_screen.dart';
import '../../features/customer/marketplace/presentation/screens/order_history_screen.dart';
import '../../features/customer/marketplace/presentation/screens/buyer_order_detail_screen.dart';
import '../../features/customer/marketplace/presentation/screens/wishlist_screen.dart';
import '../../features/customer/scanner/presentation/screens/room_scanner_screen.dart';
import '../../features/customer/ar/data/furniture_model_library.dart';
import '../../features/customer/ar/presentation/screens/ar_viewer_screen.dart';
import '../../features/supplier/presentation/screens/order_detail_screen.dart';
import '../../shared/screens/order_invoice_screen.dart';

import 'route_names.dart';

/// GoRouter provider with role-based redirect logic.
///
/// The router uses [refreshListenable] (the auth state notifier) to
/// re-evaluate redirects when auth state changes, instead of recreating
/// the entire router. This prevents the login page from flashing on app
/// restart or after a successful login.
final appRouterProvider = Provider<GoRouter>((ref) {
  // Use a ChangeNotifier that fires on auth state changes. This lets
  // GoRouter re-evaluate redirects without recreating the router (which
  // would flash the login page on app restart or after login).
  final authRefresh = ref.watch(authRefreshProvider);

  return GoRouter(
    initialLocation: '/login',
    // Re-evaluate the redirect whenever the auth state changes.
    refreshListenable: authRefresh,
    redirect: (context, state) {
      // Read the *current* auth state at redirect time (not captured at
      // router creation).
      final authState = ref.read(authStateProvider);

      // While Firebase Auth is checking the session, don't redirect —
      // this prevents the login page from flashing on app restart.
      final isLoading = authState.isLoading;
      if (isLoading) return null;

      final user = authState.whenOrNull(data: (u) => u);
      final isLoggedIn = user != null;
      final isOnAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/forgot-password' ||
          state.matchedLocation == '/verify-email';

      if (!isLoggedIn && !isOnAuthRoute) {
        return '/login';
      }
      if (isLoggedIn && isOnAuthRoute) {
        return user.isHomeowner ? '/home' : '/supplier/dashboard';
      }
      if (isLoggedIn && user.isHomeowner &&
          state.matchedLocation.startsWith('/supplier')) {
        return '/home';
      }
      // Suppliers may browse the storefront (grid + product detail) so they
      // can preview their own live listings ("View in store"), and may open
      // the AR viewer from a product's "View in AR" preview. Cart, checkout,
      // orders and wishlist remain buyer-only.
      final isStorefrontBrowse =
          state.matchedLocation == '/marketplace' ||
              state.matchedLocation.startsWith('/marketplace/product/') ||
              state.matchedLocation == '/ar-viewer';
      // The invoice screen is shared (buyer receipt + seller paperwork), so
      // suppliers must reach /orders/... without being bounced to the
      // dashboard they normally get sent to outside /supplier.
      final isSharedInvoice =
          state.matchedLocation.startsWith('/orders/');
      if (isLoggedIn && user.isSupplier &&
          !isStorefrontBrowse &&
          !isSharedInvoice &&
          !state.matchedLocation.startsWith('/supplier') &&
          !isOnAuthRoute) {
        return '/supplier/dashboard';
      }
      return null;
    },
    routes: [
      // ── Auth routes (no shell) ──
      GoRoute(
        path: '/login',
        name: RouteNames.login,
        pageBuilder: (_, __) => _buildPage(const LoginScreen()),
      ),
      GoRoute(
        path: '/register',
        name: RouteNames.register,
        pageBuilder: (_, __) => _buildPage(const RegisterScreen()),
      ),
      GoRoute(
        path: '/forgot-password',
        name: RouteNames.forgotPassword,
        pageBuilder: (_, __) => _buildPage(const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: '/verify-email',
        name: RouteNames.verifyEmail,
        pageBuilder: (_, __) => _buildPage(const VerifyEmailScreen()),
      ),

      // ── Standalone routes ──
      GoRoute(
        path: '/budget',
        name: RouteNames.homeownerBudget,
        pageBuilder: (_, __) => _buildPage(const BudgetPlannerScreen()),
      ),

      // ── Design Editor (full-screen from scan or saved designs) ──
      GoRoute(
        path: '/design-editor',
        name: RouteNames.homeownerDesignEditor,
        pageBuilder: (_, state) => _buildPage(
          RoomScannerScreen(existingDesign: state.extra as dynamic),
        ),
      ),

      // ── AR Viewer (full-screen; extras: Product | List<ArFurnitureItem>) ──
      GoRoute(
        path: '/ar-viewer',
        name: RouteNames.arViewer,
        pageBuilder: (_, state) => _buildPage(_buildArViewer(state.extra)),
      ),

      // ── Marketplace (buyer, full-screen over shell) ──
      GoRoute(
        path: '/marketplace/product/:id',
        name: RouteNames.homeownerProductDetail,
        pageBuilder: (_, state) => _buildPage(
          ProductDetailScreen(
            productId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/marketplace/cart',
        name: RouteNames.homeownerCart,
        pageBuilder: (_, __) => _buildPage(const CartScreen()),
      ),
      GoRoute(
        path: '/marketplace/checkout',
        name: RouteNames.homeownerCheckout,
        pageBuilder: (_, __) => _buildPage(const CheckoutScreen()),
      ),
      GoRoute(
        path: '/marketplace/order-confirmation',
        name: RouteNames.homeownerOrderConfirmation,
        pageBuilder: (_, __) =>
            _buildPage(const OrderConfirmationScreen()),
      ),
      GoRoute(
        path: '/marketplace/orders',
        name: RouteNames.homeownerOrderHistory,
        pageBuilder: (_, __) => _buildPage(const OrderHistoryScreen()),
      ),
      GoRoute(
        path: '/marketplace/orders/:id',
        name: RouteNames.homeownerOrderDetail,
        pageBuilder: (_, state) => _buildPage(
          BuyerOrderDetailScreen(
            orderId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/marketplace/wishlist',
        name: RouteNames.homeownerWishlist,
        pageBuilder: (_, __) => _buildPage(const WishlistScreen()),
      ),

      // ── Supplier product form (create / edit, full-screen) ──
      GoRoute(
        path: '/supplier/products/new',
        name: RouteNames.supplierProductNew,
        pageBuilder: (_, __) => _buildPage(const ProductFormScreen()),
      ),
      GoRoute(
        path: '/supplier/products/:id/edit',
        name: RouteNames.supplierProductEdit,
        pageBuilder: (_, state) => _buildPage(
          ProductFormScreen(productId: state.pathParameters['id']),
        ),
      ),

      // ── Supplier order detail (full-screen) ──
      GoRoute(
        path: '/supplier/orders/:id',
        name: RouteNames.supplierOrderDetail,
        pageBuilder: (_, state) => _buildPage(
          SupplierOrderDetailScreen(
            orderId: state.pathParameters['id']!,
          ),
        ),
      ),

      // ── Supplier verification application (full-screen) ──
      GoRoute(
        path: '/supplier/verification',
        name: RouteNames.supplierVerification,
        pageBuilder: (_, __) =>
            _buildPage(const VerificationApplicationScreen()),
      ),

      // ── Invoice (shared: buyer receipt + seller paperwork, full-screen) ──
      GoRoute(
        path: '/orders/:orderId/invoice/:supplierId',
        name: RouteNames.orderInvoice,
        pageBuilder: (_, state) => _buildPage(
          OrderInvoiceScreen(
            orderId: state.pathParameters['orderId']!,
            supplierId: state.pathParameters['supplierId']!,
          ),
        ),
      ),

      // ── Homeowner shell ──
      StatefulShellRoute.indexedStack(
        builder: (_, __, navigationShell) =>
            HomeownerShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: RouteNames.homeownerDashboard,
                builder: (_, __) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/design',
                name: RouteNames.homeownerScan,
                builder: (_, __) => const RoomScannerScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ai',
                name: RouteNames.homeownerAi,
                builder: (_, __) => const AiRecommendationScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/marketplace',
                name: RouteNames.homeownerMarketplace,
                builder: (_, __) => const MarketplaceScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/saved',
                name: RouteNames.homeownerSaved,
                builder: (_, __) => const SavedDesignsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                name: RouteNames.homeownerProfile,
                builder: (_, __) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),

      // ── Supplier shell ──
      StatefulShellRoute.indexedStack(
        builder: (_, __, navigationShell) =>
            SupplierShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/supplier/dashboard',
                name: RouteNames.supplierDashboard,
                builder: (_, __) => const SupplierDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/supplier/products',
                name: RouteNames.supplierProducts,
                builder: (_, __) => const ProductManagementScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/supplier/orders',
                name: RouteNames.supplierOrders,
                builder: (_, __) => const OrderManagementScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/supplier/analytics',
                name: RouteNames.supplierAnalytics,
                builder: (_, __) => const SalesAnalyticsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/supplier/profile',
                name: RouteNames.supplierProfile,
                builder: (_, __) => const SupplierProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Smooth fade transition for all pages.
CustomTransitionPage<T> _buildPage<T>(Widget child) {
  return CustomTransitionPage<T>(
    child: child,
    transitionsBuilder: (_, animation, __, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 200),
  );
}

/// Maps the /ar-viewer route extra to the screen:
///  * a [Product] → product mode (marketplace AR button): the product's own
///    true-size 3D model leads the catalog;
///  * a [List] of [ArFurnitureItem] → room-plan mode (scanner / saved
///    designs) with exactly those bundled models;
///  * anything else / nothing → the full bundled catalog.
Widget _buildArViewer(Object? extra) {
  if (extra is Product) return ArViewerScreen(product: extra);
  if (extra is List<ArFurnitureItem>) return ArViewerScreen(items: extra);
  return const ArViewerScreen();
}
