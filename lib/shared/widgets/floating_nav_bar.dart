import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';

/// Bottom clearance for scroll views when the shell uses `extendBody: true`
/// and the fallback constant is needed instead of `MediaQuery.padding.bottom`.
const double kFloatingNavBarClearance = 84;

/// Solid floating pill bottom navigation bar.
///
/// Floats above the content with a soft shadow and large corner radius —
/// iOS-26/27-style placement, but with a solid surface fill (no glass blur).
/// Unselected destinations are icon-only so 6 homeowner tabs still fit on a
/// 360dp-wide phone.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return SafeArea(
      top: false,
      child: Container(
        margin: EdgeInsets.fromLTRB(16, 0, 16, 10 + bottomInset),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        // Inset the bar inside the 28px rounded pill: the selected indicator
        // is up to 64dp wide, wider than a single ~51dp slot, so on the first
        // / last tab it used to run flush against (and get clipped by) the
        // rounded ends — the highlight looked "out of the box". 10dp of
        // horizontal padding gives every indicator breathing room at both
        // ends, on phone (360dp) and tablet widths alike.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: NavigationBar(
            height: 64,
            elevation: 0,
            shadowColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            backgroundColor: AppColors.surface,
            indicatorColor: AppColors.accent.withValues(alpha: 0.12),
            // Icon-only for unselected tabs — the only way 6 destinations
            // stay legible at 360dp ((360 - 32 margin - 20 inset) / 6
            // ≈ 51.3dp per slot).
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final isSelected = states.contains(WidgetState.selected);
              return GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppColors.accent : AppColors.textHint,
              );
            }),
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: destinations,
          ),
        ),
      ),
    );
  }
}
