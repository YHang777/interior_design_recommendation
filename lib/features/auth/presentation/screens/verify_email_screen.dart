import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_button.dart';

class VerifyEmailScreen extends ConsumerWidget {
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final email = authState.whenOrNull(data: (user) => user?.email) ?? 'your email';

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.verifyEmailTitle)),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.background, Colors.white],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.mark_email_unread,
                  size: 64,
                  color: AppColors.accent,
                ),
                const SizedBox(height: 24),
                Text(
                  'Verify Your Email',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'We have sent a verification email to:\n$email',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Please check your inbox and follow the instructions to verify your account.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 32),

                // Resend button
                AuthButton(
                  label: AppStrings.resendEmail,
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Verification email resent!'),
                        backgroundColor: AppColors.accent,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  isOutlined: true,
                ),
                const SizedBox(height: 16),

                // I've Verified button
                AuthButton(
                  label: AppStrings.iveVerified,
                  onPressed: () {
                    // In mock mode, navigate to login
                    context.go('/login');
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Email verified! You can now log in.'),
                        backgroundColor: AppColors.success,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
