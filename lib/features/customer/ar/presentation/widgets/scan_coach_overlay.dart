import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../data/scan_coach.dart';

class ScanCoachOverlay extends StatelessWidget {
  const ScanCoachOverlay({
    super.key,
    required this.state,
    required this.onDismiss,
  });

  final ScanCoachState state;

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 56, left: 24, right: 24),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xF2262626),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: state.ready ? AppColors.accentLight : Colors.white24,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                state.ready ? Icons.check_circle : Icons.explore,
                size: 18,
                color: state.ready
                    ? AppColors.accentLight
                    : AppColors.primaryLight,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Scan your room',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.white70),
                tooltip: 'Hide scanning help',
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          _stepRow(ScanCoachStep.findFloor, 'Point at the floor'),
          _stepRow(ScanCoachStep.sweepFloor, 'Sweep side to side'),
          _stepRow(ScanCoachStep.expandCoverage, 'Map a bit more'),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: state.progress.clamp(0.02, 1.0).toDouble(),
              minHeight: 5,
              backgroundColor: Colors.white12,
              color: AppColors.accentLight,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                state.hasIssue
                    ? Icons.warning_amber_rounded
                    : Icons.lightbulb_outline,
                size: 13,
                color: state.hasIssue ? AppColors.warning : Colors.white54,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  state.tip,
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    height: 1.3,
                    color: state.hasIssue ? AppColors.warning : Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepRow(ScanCoachStep step, String label) {
    final done = state.ready || state.step.index > step.index;
    final active = !done && state.step == step;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle
                : active
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
            size: 15,
            color: done
                ? AppColors.accentLight
                : active
                    ? Colors.white
                    : Colors.white38,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: active || done ? FontWeight.w500 : FontWeight.w400,
              color: done
                  ? Colors.white70
                  : active
                      ? Colors.white
                      : Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}
