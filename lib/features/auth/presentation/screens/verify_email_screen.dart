import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../domain/repositories/auth_repository.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_button.dart';

/// Shown after registration: the middleware (via Brevo) has emailed a
/// verification link. The link's page marks the Firebase user
/// `emailVerified`; once it has, "I've Verified" proceeds to login.
///
/// Receives `email` and `uid` as route query parameters (the user is signed
/// out at this point, so authState has no user to read them from); the
/// Resend button uses them to re-request the email from the middleware.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _resending = false;

  Future<void> _resend() async {
    final uri = GoRouterState.of(context).uri;
    final email = uri.queryParameters['email'];
    final uid = uri.queryParameters['uid'];
    if (email == null || uid == null) return;
    setState(() => _resending = true);
    try {
      await ref
          .read(authStateProvider.notifier)
          .resendVerificationEmail(email: email, uid: uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Verification email sent! Check your inbox.'),
        backgroundColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
      ));
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = GoRouterState.of(context).uri;
    final authState = ref.watch(authStateProvider);
    final email = uri.queryParameters['email'] ??
        authState.whenOrNull(data: (user) => user?.email) ??
        'your email';
    final uid = uri.queryParameters['uid'];

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
                  label: _resending ? 'Sending…' : AppStrings.resendEmail,
                  onPressed: (uid == null || _resending) ? null : _resend,
                  isOutlined: true,
                ),
                const SizedBox(height: 16),

                // I've Verified button
                AuthButton(
                  label: AppStrings.iveVerified,
                  onPressed: () {
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
