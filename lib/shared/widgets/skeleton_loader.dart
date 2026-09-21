import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Shimmer-animated skeleton placeholder cards matching the product grid shape.
/// Use during async loading instead of a raw spinner.
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({
    super.key,
    this.count = 6,
    this.crossAxisCount = 2,
    this.childAspectRatio = 0.68,
  });

  final int count;
  final int crossAxisCount;
  final double childAspectRatio;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.crossAxisCount,
        childAspectRatio: widget.childAspectRatio,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: widget.count,
      itemBuilder: (context, index) {
        return _ShimmerCard(animation: _controller);
      },
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  const _ShimmerCard({required this.animation});

  final AnimationController animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(

      animation: animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image placeholder with shimmer
              Expanded(
                flex: 3,
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        color: AppColors.divider,
                      ),
                      Positioned.fill(
                        child: _ShimmerOverlay(progress: animation.value),
                      ),
                    ],
                  ),
                ),
              ),
              // Info placeholders with shimmer
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Stack(
                          children: [
                            Container(
                              height: 12,
                              width: double.infinity,
                              color: AppColors.divider,
                            ),
                            Positioned.fill(
                              child:
                                  _ShimmerOverlay(progress: animation.value),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Stack(
                          children: [
                            Container(
                              height: 16,
                              width: 60,
                              color: AppColors.divider,
                            ),
                            Positioned.fill(
                              child:
                                  _ShimmerOverlay(progress: animation.value),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Stack(
                              children: [
                                Container(
                                  height: 10,
                                  width: 50,
                                  color: AppColors.divider,
                                ),
                                Positioned.fill(
                                  child: _ShimmerOverlay(
                                      progress: animation.value),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Stack(
                              children: [
                                Container(
                                  height: 10,
                                  width: 40,
                                  color: AppColors.divider,
                                ),
                                Positioned.fill(
                                  child: _ShimmerOverlay(
                                      progress: animation.value),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A linear gradient that sweeps left-to-right to create a shimmer effect.
class _ShimmerOverlay extends StatelessWidget {
  const _ShimmerOverlay({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 2,
      alignment: Alignment(-1.0 + 2.0 * progress, 0),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: const Alignment(-1.0, 0),
            end: const Alignment(1.0, 0),
            colors: [
              AppColors.shimmer,
              AppColors.shimmerHighlight,
              AppColors.shimmer,
            ],
          ),
        ),
      ),
    );
  }
}
