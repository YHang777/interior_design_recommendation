import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/order.dart';

/// Colored status pill used for order status, refund status, and verification
/// status.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.compact = false,
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
    final (label, color) = switch (status) {
      'verified' => ('Verified', Colors.green),
      'pending' => ('Pending', Colors.orange),
      'rejected' => ('Rejected', Colors.red),
      _ => ('Unknown', Colors.grey),
    };
    return StatusBadge(label: label, color: color, compact: compact);
  }

  final String label;
  final Color color;
  final bool compact;

  static Color colorForOrderStatus(OrderStatus status) => switch (status) {
        OrderStatus.pending => Colors.orange,
        OrderStatus.confirmed => const Color(0xFF1565C0),
        OrderStatus.shipped => const Color(0xFF3F51B5),
        OrderStatus.delivered => Colors.green,
        OrderStatus.cancelled => Colors.red,
      };

  static Color _colorForRefundStatus(RefundStatus status) => switch (status) {
        RefundStatus.requested => Colors.orange,
        RefundStatus.approved => Colors.green,
        RefundStatus.rejected => Colors.red,
        RefundStatus.processed => const Color(0xFF1565C0),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(compact ? 8 : 20),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
