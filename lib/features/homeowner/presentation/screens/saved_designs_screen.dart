import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../models/room_design.dart';
import '../../../ar/data/furniture_model_library.dart';

import '../../../../shared/widgets/gradient_scaffold.dart';
import '../../../../shared/widgets/section_header.dart';
import '../../presentation/providers/design_providers.dart';

/// Saved Designs + Style Library.
class SavedDesignsScreen extends ConsumerWidget {
  const SavedDesignsScreen({super.key});

  static const _styles = [
    ('Modern', 'assets/images/ai_style_modern.jpg'),
    ('Classic', 'assets/images/ai_style_classic.jpg'),
    ('Minimalist', 'assets/images/ai_style_minimalist.jpg'),
    ('Bohemian', 'assets/images/ai_style_bohemian.jpg'),
    ('Scandinavian', 'assets/images/ai_style_scandinavian.jpg'),
    ('Industrial', 'assets/images/ai_style_industrial.jpg'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final designsAsync = ref.watch(savedDesignsProvider);

    return GradientScaffold(
      child: designsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cloud_off,
                    size: 32, color: AppColors.error),
              ),
              const SizedBox(height: 16),
              Text('Could not load designs',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text('Please check your connection',
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => ref.invalidate(savedDesignsProvider),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (designs) => designs.isEmpty
            ? _buildEmpty(context)
            : _buildContent(context, ref, designs),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Enhanced empty state
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.accent.withValues(alpha: 0.1),
                  AppColors.accentLight.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bookmark_outline,
                size: 48, color: AppColors.accent),
          ),
          const SizedBox(height: 20),
          Text('No saved designs yet',
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
                'Scan a room and save your design to see it here',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 14, color: AppColors.textSecondary)),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => context.push('/design-editor'),
            icon: const Icon(Icons.camera_alt, size: 18),
            label: const Text('Start Scanning'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
            ),
          ),
          const SizedBox(height: 32),
          _buildStyleLibrary(context),
        ],
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, List<RoomDesign> designs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          SectionHeader(
            title: 'Saved Designs (${designs.length})',
            trailingLabel: 'New Scan',
            onTrailing: () => context.push('/design-editor'),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.82,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: designs.length,
            itemBuilder: (_, i) =>
                _buildDesignCard(context, ref, designs[i]),
          ),
          const SizedBox(height: 24),
          _buildStyleLibrary(context),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildDesignCard(
      BuildContext context, WidgetRef ref, RoomDesign design) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/design-editor', extra: design),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Room preview area
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(14)),
                    child: Container(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      width: double.infinity,
                      child: Center(
                        child: Icon(
                          _roomIcon(design.roomType),
                          size: 48,
                          color: AppColors.accent.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                  // Gradient overlay at bottom
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 32,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.15),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Furniture count badge
                  if (design.furniture.isNotEmpty)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.accent, AppColors.accentLight],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.3),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Text(
                          '${design.furniture.length}',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  // Action buttons
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Row(
                      children: [
                        _actionBtn(Icons.view_in_ar_outlined,
                            AppColors.accent, () {
                          context.push(
                            '/ar-viewer',
                            extra: ArFurnitureLibrary.fromIconNames(
                                design.furniture
                                    .map((f) => f.iconName)
                                    .toList()),
                          );
                        }),
                        const SizedBox(width: 4),
                        _actionBtn(Icons.edit_outlined,
                            AppColors.secondaryAccent, () {
                          context.push('/design-editor', extra: design);
                        }),
                        const SizedBox(width: 4),
                        _actionBtn(Icons.delete_outline, AppColors.error,
                            () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              title: const Text('Delete Design'),
                              content: Text('Delete "${design.name}"?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.error,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            final ds = ref.read(
                                roomDesignDatasourceProvider);
                            await ds.deleteDesign(design.id);
                            ref.invalidate(savedDesignsProvider);
                          }
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(design.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(design.roomTypeLabel,
                        style: GoogleFonts.poppins(
                            fontSize: 11, color: AppColors.textHint)),
                    const Spacer(),
                    Text(
                      _formatDate(design.updatedAt),
                      style: GoogleFonts.poppins(
                          fontSize: 10, color: AppColors.textHint),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStyleLibrary(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Style Library'),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.0,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: _styles.length,
          itemBuilder: (_, i) =>
              _buildStyleCard(context, _styles[i].$1, _styles[i].$2),
        ),
      ],
    );
  }

  Widget _buildStyleCard(
      BuildContext context, String name, String image) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {},
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(14)),
                    child: Image.asset(image,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                            color: AppColors.divider,
                            child: const Icon(Icons.image,
                                color: AppColors.textHint))),
                  ),
                  // Gradient overlay at bottom for text readability
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.5),
                          ],
                        ),
                      ),
                      child: Text(name,
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }

  IconData _roomIcon(String roomType) {
    switch (roomType) {
      case 'living_room':
        return Icons.weekend;
      case 'bedroom':
        return Icons.bed;
      case 'kitchen':
        return Icons.kitchen;
      case 'bathroom':
        return Icons.bathtub;
      case 'dining_room':
        return Icons.table_restaurant;
      case 'home_office':
        return Icons.desk;
      default:
        return Icons.meeting_room;
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
