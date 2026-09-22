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
    ('Modern', Icons.apartment, 'Clean lines & neutral tones'),
    ('Classic', Icons.chair, 'Elegant & ornate details'),
    ('Minimalist', Icons.crop_square, 'Simple & uncluttered'),
    ('Bohemian', Icons.palette, 'Colorful & eclectic'),
    ('Scandinavian', Icons.ac_unit, 'Light & cozy natural'),
    ('Industrial', Icons.factory, 'Raw & urban aesthetic'),
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

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmpty(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 48),
          // Icon
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bookmark_outline,
                size: 42, color: AppColors.accent),
          ),
          const SizedBox(height: 24),
          // Title
          Text('No Saved Designs',
              style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          // Subtitle
          Text(
            'Create a room design and save it\nto see it here',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 14, color: AppColors.textSecondary, height: 1.5),
          ),
          const SizedBox(height: 28),
          // CTA
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/design-editor'),
              icon: const Icon(Icons.camera_alt, size: 20),
              label: const Text('Create Design'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
          // Style library
          _buildStyleLibrary(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Content with designs ──────────────────────────────────────────────────

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
          ...designs.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildDesignCard(context, ref, d),
              )),
          const SizedBox(height: 28),
          _buildStyleLibrary(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Design card (list row) ───────────────────────────────────────────────

  Widget _buildDesignCard(
      BuildContext context, WidgetRef ref, RoomDesign design) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/design-editor', extra: design),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Room icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _roomIcon(design.roomType),
                  size: 26,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(design.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(design.roomTypeLabel,
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (design.furniture.isNotEmpty) ...[
                          Icon(Icons.chair,
                              size: 12, color: AppColors.textHint),
                          const SizedBox(width: 3),
                          Text('${design.furniture.length} items',
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: AppColors.textHint)),
                          const SizedBox(width: 10),
                        ],
                        Text(_formatDate(design.updatedAt),
                            style: GoogleFonts.poppins(
                                fontSize: 11, color: AppColors.textHint)),
                      ],
                    ),
                  ],
                ),
              ),
              // Menu
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert,
                    size: 20, color: AppColors.textHint),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onSelected: (value) async {
                  if (value == 'edit') {
                    context.push('/design-editor', extra: design);
                  } else if (value == 'ar') {
                    context.push(
                      '/ar-viewer',
                      extra: ArFurnitureLibrary.fromIconNames(
                          design.furniture.map((f) => f.iconName).toList()),
                    );
                  } else if (value == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        title: const Text('Delete Design'),
                        content: Text('Delete "${design.name}"?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.error,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      final ds = ref.read(roomDesignDatasourceProvider);
                      await ds.deleteDesign(design.id);
                      ref.invalidate(savedDesignsProvider);
                    }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined,
                              size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 10),
                          const Text('Edit'),
                        ],
                      )),
                  PopupMenuItem(
                      value: 'ar',
                      child: Row(
                        children: [
                          Icon(Icons.view_in_ar_outlined,
                              size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 10),
                          const Text('View in AR'),
                        ],
                      )),
                  PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              size: 18, color: AppColors.error),
                          const SizedBox(width: 10),
                          Text('Delete',
                              style: TextStyle(color: AppColors.error)),
                        ],
                      )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Style Library (3-column grid) ─────────────────────────────────────────

  Widget _buildStyleLibrary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Style Library',
            style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.95,
          children: _styles
              .map((s) => _buildStyleCard(s.$1, s.$2, s.$3))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildStyleCard(String name, IconData icon, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22, color: AppColors.accent),
          ),
          const SizedBox(height: 8),
          Text(name,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                  fontSize: 9, color: AppColors.textHint)),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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
