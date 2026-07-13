import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/gradient_scaffold.dart';
import '../../../../shared/widgets/stat_card.dart';

class SalesAnalyticsScreen extends ConsumerWidget {
  const SalesAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GradientScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text('Sales Overview',
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            Row(
              children: [
                StatCard(icon: Icons.monetization_on, label: 'Total Sales', value: 'RM 125K', gradient: const [Color(0xFF4CAF50), Color(0xFF66BB6A)]),
                const SizedBox(width: 10),
                StatCard(icon: Icons.receipt, label: 'Orders', value: '156', gradient: const [Color(0xFF2196F3), Color(0xFF42A5F5)]),
                const SizedBox(width: 10),
                StatCard(icon: Icons.trending_up, label: 'Growth', value: '23.5%', gradient: const [Color(0xFFFF9800), Color(0xFFFFB74D)]),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12)]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Monthly Sales', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.brown.shade900)),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 180,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: const [
                        _Bar('Jan', 0.6),
                        _Bar('Feb', 0.9),
                        _Bar('Mar', 0.75),
                        _Bar('Apr', 1.0),
                        _Bar('May', 0.85),
                        _Bar('Jun', 0.8),
                        _Bar('Jul', 1.0),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final String month;
  final double ratio;
  const _Bar(this.month, this.ratio);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              height: 120 * ratio,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xFFBCAAA4), Color(0xFFD7CCC8)],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ),
            const SizedBox(height: 6),
            Text(month, style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
