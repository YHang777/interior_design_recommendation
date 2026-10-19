import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';
import 'filter_chip_bar.dart';

Future<T?> showCatalogPickerSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T item) labelOf,
  required Widget Function(BuildContext context, T item) tileBuilder,
  String Function(T item)? categoryOf,
  String? subtitle,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _CatalogPickerSheet<T>(
      title: title,
      items: items,
      labelOf: labelOf,
      tileBuilder: tileBuilder,
      categoryOf: categoryOf,
      subtitle: subtitle,
    ),
  );
}

class _CatalogPickerSheet<T> extends StatefulWidget {
  const _CatalogPickerSheet({
    required this.title,
    required this.items,
    required this.labelOf,
    required this.tileBuilder,
    this.categoryOf,
    this.subtitle,
  });

  final String title;
  final List<T> items;
  final String Function(T item) labelOf;
  final Widget Function(BuildContext context, T item) tileBuilder;
  final String Function(T item)? categoryOf;
  final String? subtitle;

  @override
  State<_CatalogPickerSheet<T>> createState() => _CatalogPickerSheetState<T>();
}

class _CatalogPickerSheetState<T> extends State<_CatalogPickerSheet<T>> {
  String? _category;

  static const String _allLabel = 'All';

  List<String> get _categories {
    if (widget.categoryOf == null) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final item in widget.items) {
      final c = widget.categoryOf!(item);
      if (seen.add(c)) out.add(c);
    }
    return out;
  }

  List<T> get _visible {
    if (_category == null) return widget.items;
    return [
      for (final item in widget.items)
        if (widget.categoryOf!(item) == _category) item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final visible = _visible;
    final height = MediaQuery.sizeOf(context).height * 0.62;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(widget.subtitle!,
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 12),
            FilterChipBar<String>(
              options: [_allLabel, ...categories],
              selected: _category ?? _allLabel,
              onSelected: (c) =>
                  setState(() => _category = c == _allLabel ? null : c),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.78,
              ),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final item = visible[i];
                return _PickerCard(
                  label: widget.labelOf(item),
                  onTap: () => Navigator.of(context).pop(item),
                  child: widget.tileBuilder(context, item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerCard extends StatelessWidget {
  const _PickerCard({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(child: Center(child: child)),
              const SizedBox(height: 4),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}
