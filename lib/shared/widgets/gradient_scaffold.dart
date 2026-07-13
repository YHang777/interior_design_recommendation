import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Reusable scaffold with the app's signature 3-tone gradient background.
/// Every screen in the old main.dart uses this pattern.
class GradientScaffold extends StatelessWidget {
  const GradientScaffold({
    super.key,
    this.appBar,
    required this.child,
    this.padding,
    this.extendBody = false,
  });

  final PreferredSizeWidget? appBar;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool extendBody;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      extendBodyBehindAppBar: extendBody,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary,
              AppColors.primaryLight,
              AppColors.primaryLighter,
            ],
          ),
        ),
        child: SafeArea(
          child: padding != null
              ? Padding(padding: padding!, child: child)
              : child,
        ),
      ),
    );
  }
}
