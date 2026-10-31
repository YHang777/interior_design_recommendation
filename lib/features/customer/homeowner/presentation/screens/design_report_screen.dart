import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/user_errors.dart';
import '../../../../../models/product.dart';
import '../../../../../models/room_design.dart';
import '../../../../../services/invoice/design_report_pdf.dart';
import '../../../../../shared/widgets/app_feedback.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/float_button.dart';
import '../../../../../shared/widgets/page_heading.dart';
import '../../../../../shared/widgets/section_header.dart';
import '../../../../../shared/widgets/skeleton_loader.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../../data/design_report.dart';
import '../providers/design_providers.dart';

class DesignReportScreen extends ConsumerStatefulWidget {
  const DesignReportScreen({super.key});

  @override
  ConsumerState<DesignReportScreen> createState() =>
      _DesignReportScreenState();
}

class _DesignReportScreenState extends ConsumerState<DesignReportScreen> {
  String? _selectedDesignId;

  bool _working = false;

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _share(DesignReportData report) async {
    setState(() => _working = true);
    try {
      await DesignReportPdf.share(report);
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

  Future<void> _print(DesignReportData report) async {
    setState(() => _working = true);
    try {
      await DesignReportPdf.print(report);
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

  void _retry() {
    ref.invalidate(savedDesignsProvider);
    ref.invalidate(marketplaceProductsProvider);
  }

  Future<void> _openDesignPicker(List<RoomDesign> designs) async {
    final currentId = designs
        .firstWhere((d) => d.id == _selectedDesignId,
            orElse: () => designs.first)
        .id;

    final picked = await showModalBottomSheet<RoomDesign>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Change design',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              for (final design in designs)
                InkWell(
                  onTap: () => Navigator.pop(sheetContext, design),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                design.name,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: design.id == currentId
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${design.roomTypeLabel} · '
                                '${Formatters.shortDate(design.updatedAt)}',
                                style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  color: AppColors.textHint,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          design.id == currentId
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 20,
                          color: design.id == currentId
                              ? AppColors.accent
                              : AppColors.textHint,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDesignId = picked.id);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final designsAsync = ref.watch(savedDesignsProvider);
    final List<Product> products =
        ref.watch(marketplaceProductsProvider).valueOrNull ?? const [];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            _body(designsAsync, products),
            Positioned(
              top: 8,
              left: 8,
              child: const FloatingBackButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    AsyncValue<List<RoomDesign>> designsAsync,
    List<Product> products,
  ) {
    if (designsAsync.isLoading && designsAsync.valueOrNull == null) {
      return _skeleton();
    }
    if (designsAsync.hasError && designsAsync.valueOrNull == null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: "Couldn't load your report",
        subtitle: 'Check your connection and try again.',
        actionLabel: 'Retry',
        onAction: _retry,
      );
    }

    final designs = designsAsync.valueOrNull ?? const <RoomDesign>[];
    if (designs.isEmpty) {
      return EmptyState(
        icon: Icons.assessment,
        title: 'No saved designs yet',
        subtitle: 'Create a design first, then come back for your report.',
        actionLabel: 'Create a design',
        onAction: () => context.push('/design-editor'),
      );
    }

    final design = designs.firstWhere(
      (d) => d.id == _selectedDesignId,
      orElse: () => designs.first,
    );
    final report = buildDesignReport(design, products);
    return _report(report, designs);
  }

  Widget _skeleton() {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        60,
        16,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      children: [
        Text(
          'Design Report',
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 16),
        const SkeletonLoader(count: 4),
      ],
    );
  }

  Widget _report(DesignReportData report, List<RoomDesign> designs) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        60,
        16,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeading(
            title: 'Design Report',
            subtitle: report.design.name,
            actions: [
              TextButton(
                onPressed: () => _openDesignPicker(designs),
                child: Text(
                  'Change design',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _overviewCard(report),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Furniture & Items'),
          _itemsCard(report),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Expenses Breakdown'),
          _expensesCard(report),
          _actionBar(report),
        ],
      ),
    );
  }

  // ── Design Overview ────────────────────────────────────────────────────

  Widget _overviewCard(DesignReportData report) {
    final expenses = report.expenses;
    return _card(
      child: Column(
        children: [
          _overviewRow('Room type', report.design.roomTypeLabel),
          _overviewRow(
            'Design style',
            report.derivedStyle ?? 'Not specified',
            caption: report.derivedStyle == null
                ? null
                : 'Derived from matched products',
          ),
          _overviewRow(
            'Creation date',
            Formatters.shortDate(report.design.createdAt),
          ),
          _overviewRow(
            'Total expenses',
            expenses.hasData ? Formatters.myr(expenses.total!) : '—',
            trailing: expenses.hasData
                ? _chip('Estimated')
                : null,
          ),
        ],
      ),
    );
  }

  Widget _overviewRow(
    String label,
    String value, {
    String? caption,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 6),
                      trailing,
                    ],
                  ],
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    textAlign: TextAlign.right,
                    style: GoogleFonts.poppins(
                      fontSize: 10.5,
                      color: AppColors.textHint,
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

  Widget _chip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.accent,
          height: 1.2,
        ),
      ),
    );
  }

  // ── Furniture & Items ──────────────────────────────────────────────────

  Widget _itemsCard(DesignReportData report) {
    if (report.items.isEmpty) {
      return _card(
        child: Text(
          'No furniture placed in this design yet.',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.textHint,
          ),
        ),
      );
    }
    final expenses = report.expenses;
    return _card(
      child: Column(
        children: [
          for (var i = 0; i < report.items.length; i++) ...[
            if (i > 0)
              Divider(height: 14, thickness: 0.6, color: AppColors.divider),
            _itemRow(report.items[i]),
          ],
          const SizedBox(height: 6),
          Divider(height: 1, thickness: 1, color: AppColors.divider),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Furniture subtotal',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                expenses.hasData
                    ? Formatters.myr(expenses.furniture)
                    : '—',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemRow(DesignItemEstimate item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _chip(item.category),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            item.hasData ? Formatters.myr(item.estimatedPrice!) : 'No price data yet',
            textAlign: TextAlign.right,
            style: GoogleFonts.poppins(
              fontSize: item.hasData ? 13 : 11,
              fontWeight: item.hasData ? FontWeight.w600 : FontWeight.w400,
              color: item.hasData ? AppColors.textPrimary : AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  // ── Expenses Breakdown ─────────────────────────────────────────────────

  Widget _expensesCard(DesignReportData report) {
    final expenses = report.expenses;
    final money = expenses.hasData;
    return _card(
      child: Column(
        children: [
          _expenseRow(
            'Furniture',
            money ? Formatters.myr(expenses.furniture) : '—',
          ),
          _expenseRow(
            'Installation (est.)',
            money ? Formatters.myr(expenses.installation!) : '—',
          ),
          _expenseRow(
            'Delivery (est.)',
            money ? Formatters.myr(expenses.delivery!) : '—',
          ),
          const SizedBox(height: 6),
          Divider(height: 1, thickness: 1, color: AppColors.divider),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Total expenses',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                money ? Formatters.myr(expenses.total!) : '—',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Prices are estimated from current marketplace listings '
            '(median). Installation and delivery are estimated percentages '
            'of furniture cost.',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _expenseRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared building blocks ─────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  // ── Action bar ─────────────────────────────────────────────────────────

  Widget _actionBar(DesignReportData report) {
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
                onTap: _working ? null : () => _share(report),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _pdfButton(
                label: 'Print Report',
                icon: Icons.print_outlined,
                filled: false,
                onTap: _working ? null : () => _print(report),
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
