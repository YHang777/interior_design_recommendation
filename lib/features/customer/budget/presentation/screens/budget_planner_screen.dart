import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/user_errors.dart';
import '../../../../../services/invoice/budget_report_pdf.dart';
import '../../../../../shared/widgets/app_feedback.dart';
import '../../../../../shared/widgets/gradient_scaffold.dart';
import '../../../../../shared/widgets/page_heading.dart';
import '../../../../../shared/widgets/stat_card.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../../data/budget_estimates.dart';
import '../../data/budget_plan.dart';
import '../../data/budget_providers.dart';

class BudgetPlannerScreen extends ConsumerStatefulWidget {
  const BudgetPlannerScreen({super.key});

  @override
  ConsumerState<BudgetPlannerScreen> createState() =>
      _BudgetPlannerScreenState();
}

class _BudgetPlannerScreenState extends ConsumerState<BudgetPlannerScreen> {
  final _budgetCtrl = TextEditingController();
  String _selectedRoom = defaultBudgetRoom;
  bool _ecoFriendly = false;

  bool _prefilled = false;

  bool _touched = false;

  @override
  void dispose() {
    _budgetCtrl.dispose();
    super.dispose();
  }

  int get _budget =>
      int.tryParse(_budgetCtrl.text.replaceAll(RegExp('[^0-9]'), '')) ?? 0;

  void _persist() {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null || uid.isEmpty) return;
    final plan = BudgetPlan(
      budgetRm: _budget,
      room: _selectedRoom,
      ecoFriendly: _ecoFriendly,
      updatedAt: DateTime.now(),
    );
    unawaited(
      ref.read(budgetRepositoryProvider).saveBudget(uid, plan).catchError(
            (Object e, StackTrace st) =>
                debugPrint('[budget] save failed: $e'),
          ),
    );
  }

  bool _working = false;

  List<EstimateLine> _exportLines() => buildEstimateLines(
        ref.read(marketplaceProductsProvider).valueOrNull ?? const [],
        ecoFriendly: _ecoFriendly,
      );

  Future<void> _share() async {
    setState(() => _working = true);
    try {
      await BudgetReportPdf.share(
        room: _selectedRoom,
        budgetRm: _budget,
        lines: _exportLines(),
        generatedAt: DateTime.now(),
        ecoFriendly: _ecoFriendly,
      );
      if (mounted) {
        showAppSnackbar(context, 'Report PDF ready to share',
            duration: const Duration(seconds: 3));
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(
            context,
            userMessage(e,
                fallback: 'Could not create the PDF. Please try again.'),
            isError: true,
            duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _print() async {
    setState(() => _working = true);
    try {
      await BudgetReportPdf.print(
        room: _selectedRoom,
        budgetRm: _budget,
        lines: _exportLines(),
        generatedAt: DateTime.now(),
        ecoFriendly: _ecoFriendly,
      );
      if (mounted) {
        showAppSnackbar(context, 'Print dialog opened',
            duration: const Duration(seconds: 3));
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(
            context,
            userMessage(e,
                fallback: 'Could not create the PDF. Please try again.'),
            isError: true,
            duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final planAsync = ref.watch(budgetPlanProvider);
    final productsAsync = ref.watch(marketplaceProductsProvider);

    if (!_prefilled && !_touched && planAsync.hasValue) {
      _prefilled = true;
      final plan = planAsync.valueOrNull;
      if (plan != null) {
        _budgetCtrl.text = '${plan.budgetRm}';
        if (budgetRooms.contains(plan.room)) _selectedRoom = plan.room;
        _ecoFriendly = plan.ecoFriendly;
      }
    }

    final catalogue = productsAsync.valueOrNull;
    final lines = buildEstimateLines(catalogue ?? const [],
        ecoFriendly: _ecoFriendly);
    final totalCost = estimateTotal(lines);
    final remaining = _budget - totalCost;
    final partial = lines.any((l) => !l.hasData);

    const categories = [
      Icons.format_paint,
      Icons.view_agenda,
      Icons.chair,
      Icons.lightbulb,
      Icons.home,
    ];

    String priceLabel(int i) {
      if (catalogue == null) {
        return productsAsync.hasError ? '—' : '…';
      }
      final price = lines[i].price;
      return price == null ? '—' : Formatters.myr(price);
    }

    return GradientScaffold(
      showBack: true,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 60, 20, MediaQuery.paddingOf(context).bottom + 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PageHeading(title: 'Budget Planner'),
            const SizedBox(height: 4),
            Text('Plan your $_selectedRoom renovation',
                style: GoogleFonts.poppins(
                    color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 20),

            // ── Saved-plan stream failed (rules/network): say so loudly
            // instead of silently showing empty defaults forever. ──
            if (planAsync.hasError && planAsync.valueOrNull == null) ...[
              _NoticeBanner(
                color: AppColors.error,
                icon: Icons.cloud_off_outlined,
                title: 'Could not load your saved budget',
                message: 'Check your connection and try again.',
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(budgetPlanProvider),
              ),
              const SizedBox(height: 20),
            ],

            // ── Budget Overview ──
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    icon: Icons.account_balance_wallet,
                    label: 'Total Budget',
                    value: Formatters.myr(_budget),
                    gradient: const [
                      AppColors.accent,
                      AppColors.gradientGreen
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatCard(
                    icon: Icons.receipt,
                    label: 'Total Cost',
                    value: Formatters.myr(totalCost),
                    gradient: const [
                      AppColors.secondaryAccent,
                      AppColors.gradientBlue
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatCard(
                    icon:
                        remaining >= 0 ? Icons.savings : Icons.warning,
                    label: remaining >= 0 ? 'Remaining' : 'Over Budget',
                    value: Formatters.myr(remaining.abs()),
                    gradient: remaining >= 0
                        ? const [
                            AppColors.warning,
                            AppColors.gradientOrange
                          ]
                        : const [AppColors.error, AppColors.error],
                  ),
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
                onChanged: (_) {
                  _touched = true;
                  setState(() {});
                  _persist();
                },
                style: GoogleFonts.poppins(),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: _selectedRoom,
                decoration: const InputDecoration(
                  labelText: 'Room',
                  prefixIcon: Icon(Icons.room),
                ),
                items: budgetRooms
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _selectedRoom = v;
                    _touched = true;
                  });
                  _persist();
                },
              ),
              const SizedBox(height: 14),
              Material(
                type: MaterialType.transparency,
                child: CheckboxListTile(
                  value: _ecoFriendly,
                  onChanged: (v) {
                    setState(() {
                      _ecoFriendly = v ?? false;
                      _touched = true;
                    });
                    _persist();
                  },
                  title: const Text('Eco-Friendly Materials'),
                  subtitle: Text(_ecoFriendly
                      ? 'Estimating from eco-friendly listings only'
                      : 'Switch on to price only from eco-friendly listings'),
                  activeColor: AppColors.success,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // ── Cost Breakdown (derived from the live catalogue) ──
            _SectionCard(title: 'Cost Breakdown', children: [
              if (productsAsync.hasError && catalogue == null) ...[
                _NoticeBanner(
                  color: AppColors.error,
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load product prices',
                  message: 'Check your connection and try again.',
                  actionLabel: 'Retry',
                  onAction: () => ref.invalidate(marketplaceProductsProvider),
                ),
                const SizedBox(height: 12),
              ] else if (catalogue != null && !lines.any((l) => l.hasData)) ...[
                _NoticeBanner(
                  color: AppColors.warning,
                  icon: Icons.info_outline,
                  title: 'Estimates need products in these categories',
                  message: catalogue.isEmpty
                      ? 'The marketplace has no active products yet. Add '
                          'listings in Paint, Wall Covering, Flooring, '
                          'Furniture, Lighting, Decor or Textiles and '
                          'estimates will appear here.'
                      : _ecoFriendly
                          ? 'No eco-friendly listings matched. Add '
                              'eco-friendly products, or switch off the '
                              'Eco-Friendly Materials filter to price from '
                              'the full catalogue.'
                          : 'No active listings matched Wall Paint, '
                              'Flooring, Furniture, Lighting or '
                              'Accessories. Check the product categories '
                              'in the marketplace.',
                ),
                const SizedBox(height: 12),
              ],
              Text(
                'Median price of active listings per category; the total '
                'covers only categories with data. '
                '“—” = no price data yet.',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppColors.textHint),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < budgetLineLabels.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Icon(categories[i],
                          size: 22, color: AppColors.textSecondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(budgetLineLabels[i],
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: AppColors.textPrimary)),
                      ),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(priceLabel(i),
                              maxLines: 1,
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                        ),
                      ),
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
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(Formatters.myr(totalCost),
                          maxLines: 1,
                          style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: remaining < 0
                                  ? AppColors.error
                                  : AppColors.accent)),
                    ),
                  ),
                ],
              ),
              if (partial && catalogue != null) ...[
                const SizedBox(height: 6),
                Text('Total covers categories with price data only.',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.textHint)),
              ],
              if (remaining < 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: AppColors.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Over budget by ${Formatters.myr(remaining.abs())}!',
                          style: GoogleFonts.poppins(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 20),

            // ── Export: share / print the same summary as a PDF ──
            _actionBar(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Action bar ─────────────────────────────────────────────────────────

  Widget _actionBar() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: _pdfButton(
                label: 'Share Report',
                icon: Icons.ios_share,
                filled: true,
                onTap: _working ? null : _share,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _pdfButton(
                label: 'Print Report',
                icon: Icons.print_outlined,
                filled: false,
                onTap: _working ? null : _print,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pdfButton({
    required String label,
    required IconData icon,
    required bool filled,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 52,
      child: filled
          ? Container(
              decoration: BoxDecoration(
                gradient: onTap != null
                    ? const LinearGradient(
                        colors: [AppColors.accent, AppColors.gradientGreen],
                      )
                    : null,
                borderRadius: BorderRadius.circular(14),
                color: onTap == null ? AppColors.border : null,
              ),
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.transparent,
                  disabledForegroundColor: AppColors.textHint,
                  padding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: onTap == null
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : _buttonLabel(icon, label, Colors.white),
              ),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: onTap == null
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.textSecondary),
                    )
                  : _buttonLabel(icon, label, AppColors.textPrimary),
            ),
    );
  }

  Widget _buttonLabel(IconData icon, String label, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
              color: color),
        ),
      ],
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({
    required this.color,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                const SizedBox(height: 4),
                Text(message,
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppColors.textSecondary)),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
                  color: AppColors.textPrimary)),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
