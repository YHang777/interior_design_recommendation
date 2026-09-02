import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Debounced search bar with prefix icon and clear button.
///
/// Callers may supply an external [controller] and [focusNode] to observe
/// keystrokes and focus directly; [onSubmitted] fires on keyboard submit and
/// [onFocusChanged] reports focus changes.
class SearchBar extends StatefulWidget {
  const SearchBar({
    super.key,
    this.hintText = 'Search...',
    this.onChanged,
    this.debounceMs = 350,
    this.onSubmitted,
    this.onFocusChanged,
    this.controller,
    this.focusNode,
  });

  final String hintText;
  final ValueChanged<String>? onChanged;
  final int debounceMs;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<bool>? onFocusChanged;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  State<SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<SearchBar> {
  TextEditingController? _ownedController;
  FocusNode? _ownedFocusNode;
  Timer? _debounce;

  TextEditingController get _controller =>
      widget.controller ?? (_ownedController ??= TextEditingController());

  FocusNode get _focusNode => widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _ownedFocusNode = FocusNode();
    }
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    if (widget.controller == null) _ownedController?.dispose();
    if (widget.focusNode == null) _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    widget.onFocusChanged?.call(_focusNode.hasFocus);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() {}); // refresh the clear (suffix) button as the user types
    _debounce = Timer(Duration(milliseconds: widget.debounceMs), () {
      widget.onChanged?.call(value);
    });
  }

  void _clear() {
    _controller.clear();
    _debounce?.cancel();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: _onChanged,
        onSubmitted: (value) => widget.onSubmitted?.call(value),
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle:
              const TextStyle(fontSize: 14, color: AppColors.textHint),
          prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary,
              size: 20),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18,
                      color: AppColors.textSecondary),
                  onPressed: _clear,
                )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
