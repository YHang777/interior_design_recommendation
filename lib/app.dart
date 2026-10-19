import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_colors.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/providers/auth_providers.dart';

class InteriorDesignApp extends ConsumerStatefulWidget {
  const InteriorDesignApp({super.key});

  @override
  ConsumerState<InteriorDesignApp> createState() => _InteriorDesignAppState();
}

class _InteriorDesignAppState extends ConsumerState<InteriorDesignApp> {
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
