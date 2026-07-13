import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/gradient_scaffold.dart';
import '../../../../shared/widgets/stat_card.dart';

/// Budget Planner — set renovation budget, track costs by room.
class BudgetPlannerScreen extends ConsumerStatefulWidget {
  const BudgetPlannerScreen({super.key});

  @override
  ConsumerState<BudgetPlannerScreen> createState() =>
      _BudgetPlannerScreenState();
}

class _BudgetPlannerScreenState extends ConsumerState<BudgetPlannerScreen> {
  final _budgetCtrl = TextEditingController(text: '5000');
  String _selectedRoom = 'Kitchen';
  bool _ecoFriendly = false;

  static const _rooms = ['Kitchen', 'Living Room', 'Bedroom', 'Bathroom'];

  @override
  void dispose() {
    _budgetCtrl.dispose();
    super.dispose();
  }

  int get _totalCost {
    final costs = {
      'Kitchen': [120, 2200, 800, 600, 400],
      'Living Room': [120, 1800, 1200, 800, 600],
      'Bedroom': [120, 1600, 900, 500, 300],
      'Bathroom': [120, 1400, 600, 400, 200],
    };
    final roomCosts = costs[_selectedRoom] ?? [0, 0, 0, 0, 0];
    int total = roomCosts.fold<int>(0, (sum, c) => sum + c);
    if (_ecoFriendly) total += 300;
    return total;
  }

  int get _budget => int.tryParse(_budgetCtrl.text) ?? 0;
  int get _remaining => _budget - _totalCost;

  @override
  Widget build(BuildContext context) {
    const categories = [
      ('Wall Paint', Icons.format_paint),
      ('Flooring', Icons.view_agenda),
      ('Furniture', Icons.chair),
      ('Lighting', Icons.lightbulb),
      ('Accessories', Icons.home),
    ];

    final costs = {
      'Kitchen': [120, 2200, 800, 600, 400],
      'Living Room': [120, 1800, 1200, 800, 600],
      'Bedroom': [120, 1600, 900, 500, 300],
      'Bathroom': [120, 1400, 600, 400, 200],
    }[_selectedRoom]!;

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Budget Planner'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text('Plan your $_selectedRoom renovation',
                style: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.9), fontSize: 14)),
            const SizedBox(height: 20),

            // ── Budget Overview ──
            Row(
              children: [
                StatCard(
                  icon: Icons.account_balance_wallet,
                  label: 'Total Budget',
                  value: 'RM $_budget',
                  gradient: const [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                ),
                const SizedBox(width: 10),
                StatCard(
                  icon: Icons.receipt,
                  label: 'Total Cost',
                  value: 'RM $_totalCost',
                  gradient: const [Color(0xFF2196F3), Color(0xFF42A5F5)],
                ),
                const SizedBox(width: 10),
                StatCard(
                  icon: _remaining >= 0 ? Icons.savings : Icons.warning,
                  label: _remaining >= 0 ? 'Remaining' : 'Over Budget',
                  value: 'RM ${_remaining.abs()}',
                  gradient: _remaining >= 0
                      ? const [Color(0xFFFF9800), Color(0xFFFFB74D)]
                      : const [Color(0xFFFF5722), Color(0xFFFF7043)],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Preferences ──
            _SectionCard(title: 'Preferences', children: [
              TextFormField(
                controller: _budgetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Budget (RM)',
                  prefixIcon: Icon(Icons.monetization_on),
                ),
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.poppins(),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _selectedRoom,
                decoration: const InputDecoration(
                  labelText: 'Room',
                  prefixIcon: Icon(Icons.room),
                ),
                items: _rooms
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedRoom = v);
                },
              ),
              const SizedBox(height: 14),
              CheckboxListTile(
                value: _ecoFriendly,
                onChanged: (v) => setState(() => _ecoFriendly = v ?? false),
                title: const Text('Eco-Friendly Materials'),
                subtitle: const Text('Sustainable options (+RM 300)'),
                activeColor: AppColors.success,
                contentPadding: EdgeInsets.zero,
              ),
            ]),
            const SizedBox(height: 20),

            // ── Cost Breakdown ──
            _SectionCard(title: 'Cost Breakdown', children: [
              for (var i = 0; i < categories.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Icon(categories[i].$2,
                          size: 22, color: Colors.brown.shade400),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(categories[i].$1,
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.brown.shade700)),
                      ),
                      Text('RM ${costs[i]}',
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.brown.shade900)),
                    ],
                  ),
                ),
              const Divider(),
              Row(
                children: [
                  const Expanded(
                    child: Text('Total',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  Text('RM $_totalCost',
                      style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _remaining < 0
                              ? Colors.red
                              : const Color(0xFF4CAF50))),
                ],
              ),
              if (_remaining < 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.red),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Over budget by RM ${_remaining.abs()}!',
                          style: GoogleFonts.poppins(
                              color: Colors.red, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 20),

            // ── Export ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Report exported (mocked)')),
                  );
                },
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Export Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.brown.shade900)),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
