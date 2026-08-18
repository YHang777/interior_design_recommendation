import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../models/room_design.dart';
import '../../../ar/data/furniture_model_library.dart';
import '../../../../shared/widgets/empty_state.dart';
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
              Icon(Icons.cloud_off, size: 48, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text('Could not load designs',
                  style: GoogleFonts.poppins(
                      color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(savedDesignsProvider),
                child: const Text('Retry'),
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
          EmptyState(
            icon: Icons.bookmark_outline,
            title: 'No saved designs yet',
            subtitle:
                'Scan a room and save your design to see it here',
            actionLabel: 'Start Scanning',
            onAction: () => context.push('/design-editor'),
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
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
    return GestureDetector(
      onTap: () =>
          context.push('/design-editor', extra: design),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
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
                      color: AppColors.primary
                          .withValues(alpha: 0.06),
                      width: double.infinity,
                      child: Center(
                        child: Icon(
                          _roomIcon(design.roomType),
                          size: 48,
                          color: AppColors.accent
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                  // Furniture count badge
                  if (design.furniture.isNotEmpty)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius:
                              BorderRadius.circular(12),
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
                    right: 4,
                    top: 4,
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
                        _actionBtn(Icons.edit_outlined,
                            AppColors.secondaryAccent, () {
                          context.push('/design-editor',
                              extra: design);
                        }),
                        _actionBtn(
                            Icons.delete_outline, AppColors.error,
                            () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title:
                                  const Text('Delete Design'),
                              content: Text(
                                  'Delete "${design.name}"?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx,
                                          false),
                                  child:
                                      const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () =>
                                      Navigator.pop(
                                          ctx, true),
                                  style: ElevatedButton
                                      .styleFrom(
                                    backgroundColor:
                                        AppColors.error,
                                    foregroundColor:
                                        Colors.white,
                                  ),
                                  child:
                                      const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            final ds = ref.read(
                                roomDesignDatasourceProvider);
                            await ds.deleteDesign(design.id);
                            ref.invalidate(
                                savedDesignsProvider);
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
                            fontSize: 11,
                            color: AppColors.textHint)),
                    const Spacer(),
                    Text(
                      _formatDate(design.updatedAt),
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: AppColors.textHint),
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
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            flex: 3,
            child: ClipRRect(
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
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Text(name,
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 3,
            ),
          ],
        ),
        child: Icon(icon, size: 15, color: color),
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
