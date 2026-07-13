import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/gradient_scaffold.dart';
import '../../../../shared/widgets/stat_card.dart';
import '../../../auth/presentation/providers/auth_providers.dart';

class SupplierDashboardScreen extends ConsumerWidget {
  const SupplierDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return GradientScaffold(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            // Header
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.business, color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Welcome back!',
                          style: GoogleFonts.poppins(
                              color: AppColors.textSecondary,
                              fontSize: 13)),
                      Text(user?.name ?? 'Supplier',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Stats
            Row(
              children: [
                StatCard(
                  icon: Icons.monetization_on,
                  label: 'Total Sales',
                  value: 'RM 12.8K',
                  gradient: const [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                ),
                const SizedBox(width: 10),
                StatCard(
                  icon: Icons.receipt,
                  label: 'Orders',
                  value: '24',
                  gradient: const [Color(0xFF2196F3), Color(0xFF42A5F5)],
                ),
                const SizedBox(width: 10),
                StatCard(
                  icon: Icons.star,
                  label: 'Rating',
                  value: '4.8',
                  gradient: const [Color(0xFFFF9800), Color(0xFFFFB74D)],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Quick Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quick Actions',
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.brown.shade900)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _ActionBtn(Icons.add_box, 'Add Product', () => context.go('/supplier/products')),
                      const SizedBox(width: 12),
                      _ActionBtn(Icons.list_alt, 'View Orders', () => context.go('/supplier/orders')),
                      const SizedBox(width: 12),
                      _ActionBtn(Icons.bar_chart, 'Analytics', () => context.go('/supplier/analytics')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Recent Orders
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Recent Orders',
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.brown.shade900)),
                  const SizedBox(height: 12),
                  _OrderRow('2024-0012', '3 items', 'RM 2,450', 'Shipped', Colors.green),
                  const Divider(),
                  _OrderRow('2024-0011', '1 item', 'RM 850', 'Pending', Colors.orange),
                  const Divider(),
                  _OrderRow('2024-0010', '5 items', 'RM 4,200', 'Delivered', Colors.blue),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Notifications
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notifications',
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.brown.shade900)),
                  const SizedBox(height: 12),
                  _NotifRow(Icons.warning, 'Low stock: Modern Sofa', '5 remaining', Colors.red),
                  const SizedBox(height: 8),
                  _NotifRow(Icons.star, 'New review received', '4.5 stars', Colors.amber),
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

class _ActionBtn extends StatelessWidget {
  const _ActionBtn(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.brown.shade50,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary, size: 28),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.brown.shade700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow(this.id, this.items, this.total, this.status, this.color);
  final String id, items, total, status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.receipt, size: 20, color: Colors.brown),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order #$id', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
                Text('$items • $total', style: GoogleFonts.poppins(fontSize: 11, color: Colors.brown.shade600)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(status,
                style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    );
  }
}

class _NotifRow extends StatelessWidget {
  const _NotifRow(this.icon, this.title, this.subtitle, this.color);
  final IconData icon;
  final String title, subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
              Text(subtitle, style: GoogleFonts.poppins(fontSize: 11, color: Colors.brown.shade600)),
            ],
          ),
        ),
      ],
    );
  }
}
