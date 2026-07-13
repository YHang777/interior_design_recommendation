import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/gradient_scaffold.dart';

/// Saved Designs + Style Library
class SavedDesignsScreen extends ConsumerStatefulWidget {
  const SavedDesignsScreen({super.key});

  @override
  ConsumerState<SavedDesignsScreen> createState() =>
      _SavedDesignsScreenState();
}

class _SavedDesignsScreenState extends ConsumerState<SavedDesignsScreen> {
  final _designs = [
    _Design('Modern Living Room', '2024-06-01',
        'assets/images/saved_design_1.jpg'),
    _Design('Eco Kitchen', '2024-05-28', 'assets/images/saved_design_2.jpg'),
  ];

  static const _styles = [
    ('Modern', 'assets/images/ai_style_modern.jpg'),
    ('Classic', 'assets/images/ai_style_classic.jpg'),
    ('Minimalist', 'assets/images/ai_style_minimalist.jpg'),
    ('Bohemian', 'assets/images/ai_style_bohemian.jpg'),
    ('Scandinavian', 'assets/images/ai_style_scandinavian.jpg'),
    ('Industrial', 'assets/images/ai_style_industrial.jpg'),
  ];

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            // ── Saved Designs ──
            Text('Saved Designs',
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 12),
            if (_designs.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.bookmark_border, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('No saved designs yet',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _designs.length,
                itemBuilder: (_, i) => _buildDesignCard(_designs[i]),
              ),
            const SizedBox(height: 24),

            // ── Style Library ──
            Text('Style Library',
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
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
              itemBuilder: (_, i) => _buildStyleCard(_styles[i].$1, _styles[i].$2),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildDesignCard(_Design design) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Image.asset(design.image,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image, color: Colors.grey))),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: Row(
                    children: [
                      _buildIconBtn(Icons.edit, Colors.blue, () {}),
                      _buildIconBtn(Icons.delete, Colors.red, () {
                        setState(() => _designs.removeWhere(
                            (d) => d.name == design.name));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text('${design.name} deleted (mocked)')),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.brown.shade900)),
                  const Spacer(),
                  Text('Saved on ${design.date}',
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: Colors.brown.shade600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.textSecondary,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  Widget _buildStyleCard(String name, String image) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
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
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: Image.asset(image,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.image, color: Colors.grey))),
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: Text(name,
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.brown.shade900)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Design {
  final String name;
  final String date;
  final String image;
  const _Design(this.name, this.date, this.image);
}
