import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/verify_email_screen.dart';
import '../../features/homeowner/presentation/screens/ai_recommendation_screen.dart';
import '../../features/homeowner/presentation/screens/dashboard_screen.dart';
import '../../features/homeowner/presentation/screens/homeowner_shell.dart';
import '../../features/homeowner/presentation/screens/marketplace_screen.dart';
import '../../features/homeowner/presentation/screens/profile_screen.dart';
import '../../features/homeowner/presentation/screens/saved_designs_screen.dart';
import '../../features/homeowner/presentation/screens/scan_screen.dart';
import '../../features/supplier/presentation/screens/analytics_screen.dart';
import '../../features/supplier/presentation/screens/order_management_screen.dart';
import '../../features/supplier/presentation/screens/product_management_screen.dart';
import '../../features/supplier/presentation/screens/supplier_dashboard_screen.dart';
import '../../features/supplier/presentation/screens/supplier_profile_screen.dart';
import '../../features/supplier/presentation/screens/supplier_shell.dart';
import 'route_names.dart';

/// GoRouter provider with role-based redirect logic.
///
/// The router watches [authStateProvider] and redirects based on:
/// - Authentication state (logged in / logged out)
/// - User role (homeowner / supplier)
///
/// This is the "hidden seller" design: the router is the only place that
/// knows about both role shells. Homeowner screens never import supplier
/// widgets and vice versa.
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

      // Case 1: Not logged in, trying to access protected route → login
      if (!isLoggedIn && !isOnAuthRoute) {
        return '/login';
      }

      // Case 2: Logged in, but on an auth route → go to correct shell
      if (isLoggedIn && isOnAuthRoute) {
        return user.isHomeowner ? '/home' : '/supplier/dashboard';
      }

      // Case 3: Logged-in homeowner trying to access supplier routes → redirect
      if (isLoggedIn && user.isHomeowner &&
          state.matchedLocation.startsWith('/supplier')) {
        return '/home';
      }

      // Case 4: Logged-in supplier trying to access homeowner routes → redirect
      if (isLoggedIn && user.isSupplier &&
          !state.matchedLocation.startsWith('/supplier') &&
          !isOnAuthRoute) {
        return '/supplier/dashboard';
      }

      // No redirect needed
      return null;
    },
    routes: [
      // ── Auth routes (no shell) ──
      GoRoute(
        path: '/login',
        name: RouteNames.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: RouteNames.register,
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        name: RouteNames.forgotPassword,
        builder: (_, __) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/verify-email',
        name: RouteNames.verifyEmail,
        builder: (_, __) => const VerifyEmailScreen(),
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
