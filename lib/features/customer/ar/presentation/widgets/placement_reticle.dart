import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../data/placement_reticle.dart';

class PlacementReticle extends StatelessWidget {
  const PlacementReticle({super.key, required this.state, required this.label});

  final ReticleState state;

  final String label;

  @override
  Widget build(BuildContext context) {
    final locked = state.status == ReticleStatus.locked;
    final warn = state.status == ReticleStatus.tooFar ||
        state.status == ReticleStatus.tooClose;
    // Apple FocusSquare idea: grow gently with distance so the reticle stays
    // legible on the floor (~1.5 m) without ballooning up close. Their exact
    // curve: 1.0 at 0.7 m, then +0.25 per extra meter.
    final d = state.distanceM;
    var size = 40.0;
    if (d != null) {
      final factor = d < 0.7 ? d / 0.7 : 0.25 * d + 0.825;
      size = (40 * factor).clamp(28.0, 56.0);
    }
    final ringColor = locked
        ? AppColors.accentLight
        : warn
            ? AppColors.warning
            : Colors.white70;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: locked ? 1.0 : 1.22,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: ringColor,
                width: locked ? 3 : 1.5,
              ),
            ),
            child: Icon(
              locked
                  ? Icons.check
                  : warn
                      ? Icons.north_east
                      : Icons.center_focus_strong,
              size: locked ? 16 : 18,
              color: ringColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: warn ? AppColors.warning : Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
