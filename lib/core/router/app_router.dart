import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/verify_email_screen.dart';
import '../../features/budget/presentation/screens/budget_planner_screen.dart';
import '../../features/homeowner/presentation/screens/ai_recommendation_screen.dart';
import '../../features/homeowner/presentation/screens/dashboard_screen.dart';
import '../../features/homeowner/presentation/screens/homeowner_shell.dart';
import '../../features/homeowner/presentation/screens/profile_screen.dart';
import '../../features/homeowner/presentation/screens/saved_designs_screen.dart';
import '../../features/homeowner/presentation/screens/scan_screen.dart';
import '../../features/supplier/presentation/screens/analytics_screen.dart';
import '../../features/supplier/presentation/screens/order_management_screen.dart';
import '../../features/supplier/presentation/screens/product_management_screen.dart';
import '../../features/supplier/presentation/screens/supplier_dashboard_screen.dart';
import '../../features/supplier/presentation/screens/supplier_profile_screen.dart';
import '../../features/supplier/presentation/screens/supplier_shell.dart';

// Marketplace feature
import '../../features/marketplace/presentation/screens/marketplace_screen.dart';
import '../../features/marketplace/presentation/screens/product_detail_screen.dart';
import '../../features/marketplace/presentation/screens/cart_screen.dart';
import '../../features/marketplace/presentation/screens/checkout_screen.dart';
import '../../features/marketplace/presentation/screens/order_confirmation_screen.dart';
import '../../features/marketplace/presentation/screens/order_history_screen.dart';
import '../../features/marketplace/presentation/screens/wishlist_screen.dart';
import '../../features/scanner/presentation/screens/room_scanner_screen.dart';
import '../../features/supplier/presentation/screens/order_detail_screen.dart';

import 'route_names.dart';

/// GoRouter provider with role-based redirect logic.
///
/// The router watches [authStateProvider] and redirects based on:
/// - Authentication state (logged in / logged out)
/// - User role (homeowner / supplier)
final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
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
      if (isLoggedIn && user.isSupplier &&
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
        path: '/marketplace/wishlist',
        name: RouteNames.homeownerWishlist,
        pageBuilder: (_, __) => _buildPage(const WishlistScreen()),
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
                path: '/scan',
                name: RouteNames.homeownerScan,
                builder: (_, __) => const ScanScreen(),
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
