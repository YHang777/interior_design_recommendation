import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../models/order.dart';

/// Colored status pill used for order status, refund status, and verification
/// status.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.compact = false,
    this.icon,
  });

  /// Convenience factory for OrderStatus.
  factory StatusBadge.order(OrderStatus status, {bool compact = false}) {
    return StatusBadge(
      label: status.label,
      color: colorForOrderStatus(status),
      compact: compact,
    );
  }

  /// Convenience factory for RefundStatus.
  factory StatusBadge.refund(RefundStatus status, {bool compact = false}) {
    return StatusBadge(
      label: status.label,
      color: _colorForRefundStatus(status),
      compact: compact,
    );
  }

  /// Convenience factory for supplier verification.
  factory StatusBadge.verification(String status, {bool compact = false}) {
    final (label, color, icon) = switch (status) {
      'verified' => ('Verified', AppColors.success, Icons.check_circle_outline),
      'pending' => ('Pending', AppColors.warning, Icons.schedule),
      'rejected' => ('Rejected', AppColors.error, Icons.cancel_outlined),
      _ => ('Unknown', AppColors.textHint, Icons.help_outline),
    };
    return StatusBadge(label: label, color: color, compact: compact, icon: icon);
  }

  final String label;
  final Color color;
  final bool compact;
  final IconData? icon;

  static Color colorForOrderStatus(OrderStatus status) => switch (status) {
        OrderStatus.pending => AppColors.warning,
        OrderStatus.confirmed => AppColors.secondaryAccent,
        OrderStatus.shipped => const Color(0xFF3F51B5),
        OrderStatus.delivered => AppColors.success,
        OrderStatus.cancelled => AppColors.error,
      };

  static Color _colorForRefundStatus(RefundStatus status) => switch (status) {
        RefundStatus.requested => AppColors.warning,
        RefundStatus.approved => AppColors.success,
        RefundStatus.rejected => AppColors.error,
        RefundStatus.processed => AppColors.secondaryAccent,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(compact ? 8 : 20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 11 : 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w600,
              color: color,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
