import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/utils/user_errors.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/float_button.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_button.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen>
    with SingleTickerProviderStateMixin {
  bool _resending = false;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

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
      showAppSnackbar(context, 'Verification email sent! Check your inbox.');
    } catch (e) {
      if (!mounted) return;
      showAppSnackbar(
        context,
        userMessage(e,
            fallback: 'Could not resend the email. Please try again.'),
        isError: true,
      );
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
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.background, Colors.white],
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Center(
                  child: ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.accent, AppColors.accentLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.3),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.mark_email_unread,
                          size: 48, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Verify Your Email',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 12),
                Text(
                  'We have sent a verification email to:',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    email,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please check your inbox and follow the instructions to verify your account.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 40),

                AuthButton(
                  label: AppStrings.iveVerified,
                  onPressed: () {
                    context.go('/login');
                    showAppSnackbar(
                        context, 'Email verified! You can now log in.');
                  },
                ),
                const SizedBox(height: 12),

                AuthButton(
                  label: _resending ? 'Sending…' : AppStrings.resendEmail,
                  onPressed: (uid == null || _resending) ? null : _resend,
                  isOutlined: true,
                ),
              ],
            ),
          ),
        ),
      ),
      Positioned(
        top: MediaQuery.viewPaddingOf(context).top + 8,
        left: 8,
        child: const FloatingBackButton(),
      ),
        ],
      ),
    );
  }
}
