import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import 'float_button.dart';

class GradientScaffold extends StatelessWidget {
  const GradientScaffold({
    super.key,
    this.appBar,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.showBack = false,
  });

  final PreferredSizeWidget? appBar;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    Widget content = padding != null
        ? Padding(padding: padding!, child: child)
        : child;
    if (showBack) {
      content = Stack(
        children: [
          content,
          const Positioned(
            top: 8,
            left: 8,
            child: FloatingBackButton(),
          ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: backgroundColor ?? AppColors.background,
      appBar: appBar,
      body: SafeArea(child: content),
    );
  }
}
