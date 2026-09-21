import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';

/// Horizontal scrollable row of selectable filter chips.
/// Generic over T — use String for simple labels or model objects for complex data.
class FilterChipBar<T> extends StatelessWidget {
  const FilterChipBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.labelBuilder,
    this.prefixIcon,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T)? labelBuilder;
  final Widget? prefixIcon;

  String _label(T option) {
    if (labelBuilder != null) return labelBuilder!(option);
    return option.toString();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          final isSelected = option == selected;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: ChoiceChip(
              avatar: prefixIcon != null && isSelected
                  ? prefixIcon
                  : null,
              label: Text(
                _label(option),
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => onSelected(option),
              selectedColor: AppColors.accent,
              backgroundColor: AppColors.surfaceElevated,
              side: BorderSide(
                color: isSelected
                    ? AppColors.accent
                    : AppColors.border,
                width: isSelected ? 1.5 : 1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              elevation: isSelected ? 1 : 0,
              shadowColor: AppColors.accent.withValues(alpha: 0.2),
            ),
          );
        },
      ),
    );
  }
}
