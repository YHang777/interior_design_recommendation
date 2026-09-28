import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Reusable gradient stat card used in dashboards.
/// Replaces _EnhancedStatCard, _EnhancedSupplierStatCard, _BudgetStatCard.
class StatCard extends StatefulWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final List<Color> gradient;
  final VoidCallback? onTap;

  @override
  State<StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<StatCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        transform: _isPressed
            ? (Matrix4.identity()..scale(0.97))
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.gradient,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: widget.gradient.first.withValues(alpha: _isPressed ? 0.15 : 0.3),
              blurRadius: _isPressed ? 6 : 12,
              offset: Offset(0, _isPressed ? 2 : 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, color: Colors.white, size: 32),
            const SizedBox(height: 10),
            // scaleDown (not ellipsis): money values like "RM 12,345"
            // must never be cut to "RM 12,3…" in a 1/3-width card —
            // shrink to fit instead of clipping or truncating.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.value,
                maxLines: 1,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.label,
              // Two lines so labels like "Total products" fit on narrow
              // dashboard cards instead of ellipsizing mid-word.
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
