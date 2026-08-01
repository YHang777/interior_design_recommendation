import 'package:flutter/material.dart';
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
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          final isSelected = option == selected;
          return ChoiceChip(
            label: Text(
              _label(option),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
            selected: isSelected,
            onSelected: (_) => onSelected(option),
            selectedColor: AppColors.accent,
            backgroundColor: AppColors.surface,
            side: BorderSide(
              color: isSelected ? AppColors.accent : AppColors.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }
}
