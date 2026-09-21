import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';

/// Modern styled text field for auth screens.
/// Features focus shadow, rounded 12px borders, and animated error shake.
class AuthTextField extends StatefulWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onFieldSubmitted,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;
  final bool enabled;

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;
  bool _hasError = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: _ShakeCurve()),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        final offset = _hasError
            ? (1 - _shakeAnimation.value) *
                6 *
                (_shakeAnimation.value < 0.5 ? 1 : -1)
            : 0.0;
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: Focus(
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        child: TextFormField(
          controller: widget.controller,
          obscureText: widget.obscureText,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          validator: (value) {
            final result = widget.validator?.call(value);
            final hasError = result != null && result.isNotEmpty;
            if (hasError && !_hasError) _shakeController.forward(from: 0);
            setState(() => _hasError = hasError);
            return result;
          },
          onFieldSubmitted: widget.onFieldSubmitted,
          enabled: widget.enabled,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: widget.prefixIcon != null
                ? Icon(
                    widget.prefixIcon,
                    color: _isFocused ? AppColors.accent : AppColors.textHint,
                    size: 20,
                  )
                : null,
            suffixIcon: widget.suffixIcon,
            labelStyle: GoogleFonts.poppins(
              color: _isFocused ? AppColors.accent : AppColors.textSecondary,
              fontSize: 14,
            ),
            hintStyle: GoogleFonts.poppins(
              color: AppColors.textHint,
              fontSize: 14,
            ),
            filled: true,
            fillColor: _isFocused
                ? AppColors.accent.withValues(alpha: 0.04)
                : AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.error, width: 1.5),
            ),
            errorStyle: GoogleFonts.poppins(
              color: AppColors.error,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom curve that produces a left-right-left shake pattern.
class _ShakeCurve extends Curve {
  @override
  double transformInternal(double t) {
    if (t < 0.25) return 4 * t;
    if (t < 0.5) return 2 - 4 * t;
    if (t < 0.75) return -2 + 4 * t;
    return (1 - t) * 4;
  }
}
