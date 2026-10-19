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
import '../../features/customer/homeowner/presentation/screens/design_report_screen.dart';
import '../../features/customer/homeowner/presentation/screens/homeowner_shell.dart';
import '../../features/customer/homeowner/presentation/screens/profile_screen.dart';
import '../../features/customer/homeowner/presentation/screens/saved_designs_screen.dart';

import '../../features/supplier/presentation/screens/analytics_screen.dart';
import '../../features/supplier/presentation/screens/order_management_screen.dart';
import '../../features/supplier/presentation/screens/product_form_screen.dart';
import '../../features/supplier/presentation/screens/product_management_screen.dart';
import '../../features/supplier/presentation/screens/sales_report_screen.dart';
import '../../features/supplier/presentation/screens/supplier_dashboard_screen.dart';
import '../../features/supplier/presentation/screens/supplier_profile_screen.dart';
import '../../features/supplier/presentation/screens/supplier_shell.dart';
import '../../features/supplier/presentation/screens/verification_application_screen.dart';

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

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRefresh = ref.watch(authRefreshProvider);

  return GuardedGoRouter(
    initialLocation: '/login',
    refreshListenable: authRefresh,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);

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
      final isStorefrontBrowse =
          state.matchedLocation == '/marketplace' ||
              state.matchedLocation.startsWith('/marketplace/product/') ||
              state.matchedLocation == '/ar-viewer';
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

      // ── Supplier sales report (full-screen) ──
      GoRoute(
        path: '/supplier/sales-report',
        name: RouteNames.supplierSalesReport,
        pageBuilder: (_, __) => _buildPage(const SalesReportScreen()),
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

      // ── Customer design report (full-screen) ──
      GoRoute(
        path: '/design/report',
        name: RouteNames.designReport,
        pageBuilder: (_, __) => _buildPage(const DesignReportScreen()),
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

class GuardedGoRouter extends GoRouter {
  GuardedGoRouter({
    required List<RouteBase> routes,
    GoRouterRedirect? redirect,
    super.refreshListenable,
    super.initialLocation,
  }) : super.routingConfig(
          routingConfig: ValueNotifier<RoutingConfig>(
            RoutingConfig(
              routes: routes,
              redirect: redirect ?? (_, __) => null,
            ),
          ),
        );

  @override
  Future<T?> push<T extends Object?>(String location, {Object? extra}) {
    if (_wouldStackSecondShell(location, extra) ||
        _wouldSwitchShellBranch(location, extra)) {
      go(location, extra: extra);
      return Future<T?>.value();
    }
    return super.push<T>(location, extra: extra);
  }

  bool _wouldStackSecondShell(String location, Object? extra) {
    final RouteMatchList current = routerDelegate.currentConfiguration;
    if (current.matches.isEmpty ||
        current.matches.last is! ImperativeRouteMatch) {
      return false;
    }
    final RouteMatchList next =
        configuration.findMatch(Uri.parse(location), extra: extra);
    return next.matches.any((RouteMatchBase match) => match is ShellRouteMatch);
  }

  bool _wouldSwitchShellBranch(String location, Object? extra) {
    final RouteMatchList current = routerDelegate.currentConfiguration;
    if (current.matches.isEmpty) return false;
    final RouteMatchBase top = current.matches.last;
    if (top is! ShellRouteMatch) return false;
    final RouteMatchList next =
        configuration.findMatch(Uri.parse(location), extra: extra);
    if (next.matches.isEmpty) return false;
    final RouteMatchBase nextTop = next.matches.last;
    if (nextTop is! ShellRouteMatch) return false;
    if (!identical(nextTop.route, top.route)) return false;
    return nextTop.navigatorKey != top.navigatorKey;
  }
}

CustomTransitionPage<T> _buildPage<T>(Widget child) {
  return CustomTransitionPage<T>(
    child: child,
    transitionsBuilder: (_, animation, __, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 200),
  );
}

Widget _buildArViewer(Object? extra) {
  if (extra is Product) return ArViewerScreen(product: extra);
  if (extra is List<ArFurnitureItem>) return ArViewerScreen(items: extra);
  return const ArViewerScreen();
}
