import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_colors.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/providers/auth_providers.dart';

/// Root app widget. Uses MaterialApp.router with GoRouter.
class InteriorDesignApp extends ConsumerStatefulWidget {
  const InteriorDesignApp({super.key});

  @override
  ConsumerState<InteriorDesignApp> createState() => _InteriorDesignAppState();
}

class _InteriorDesignAppState extends ConsumerState<InteriorDesignApp> {
  /// True once the first non-loading auth state has been observed.
  ///
  /// The splash below exists for the *initial* Firebase Auth restore — the
  /// window on a cold start where the session is still being read and the
  /// router cannot yet decide between `/login` and the dashboard. Without it,
  /// a returning user sees the login page flash before being bounced home.
  bool _bootstrapComplete = false;

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final authState = ref.watch(authStateProvider);

    if (!authState.isLoading) _bootstrapComplete = true;

    return MaterialApp.router(
      title: 'Intellar',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // Only the initial restore gets the full-screen splash. An explicit
        // `login()` also passes through `AsyncLoading`, and gating on that
        // here replaced the WHOLE app — login screen and its button spinner
        // included — with this splash for the entire sign-in round trip,
        // which is what made a successful login look like a long hang.
        if (!_bootstrapComplete && authState.isLoading) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.home_work_rounded,
                      size: 48, color: AppColors.accent),
                  SizedBox(height: 16),
                  CircularProgressIndicator(color: AppColors.accent),
                ],
              ),
            ),
          );
        }
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
