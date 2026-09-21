import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';

/// Compact rounded −/+ stepper with a zero-padded counter (e.g. '03').
/// Values are clamped to [min]/[max]; [onChanged] fires only when the value
/// actually changes and the target is in range.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 99999,
    this.label,
    this.compact = false,
    this.onBlockedTap,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  /// Optional caption rendered beside the counter (e.g. 'stock').
  final String? label;
  final bool compact;

  /// Fired when −/+ is pressed while already at the [min]/[max] edge —
  /// lets parents explain why the step was ignored (e.g. "max reached").
  final VoidCallback? onBlockedTap;

  bool get _canDecrement => value > min;
  bool get _canIncrement => value < max;

  void _decrement() {
    if (_canDecrement) {
      onChanged(value - 1);
    } else {
      onBlockedTap?.call();
    }
  }

  void _increment() {
    if (_canIncrement) {
      onChanged(value + 1);
    } else {
      onBlockedTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Larger touch targets: 36dp compact, 40dp normal (meets 48dp with padding)
    final buttonSize = compact ? 36.0 : 40.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepperButton(
          icon: Icons.remove,
          size: buttonSize,
          enabled: _canDecrement,
          onTap: _decrement,
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value.toString().padLeft(2, '0'),
                style: GoogleFonts.poppins(
                  fontSize: compact ? 15 : 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: -0.2,
                  height: 1.2,
                ),
              ),
              if (label != null) ...[
                const SizedBox(width: 4),
                Text(
                  label!,
                  style: GoogleFonts.poppins(
                    fontSize: compact ? 10 : 11,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ],
          ),
        ),
        _StepperButton(
          icon: Icons.add,
          size: buttonSize,
          enabled: _canIncrement,
          onTap: _increment,
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.size,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final double size;

  /// Whether the step is actually possible. Edge taps still fire [onTap]
  /// (so parents can explain why via `onBlockedTap`) but render dimmed.
  final bool enabled;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: enabled ? AppColors.accent : AppColors.surfaceContainer,
            shape: BoxShape.circle,
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: size * 0.48,
            color: enabled ? AppColors.textOnDark : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}
