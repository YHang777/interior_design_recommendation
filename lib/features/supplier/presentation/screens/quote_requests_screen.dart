import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/router/route_names.dart';
import '../../../../models/quote_request.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/float_button.dart';
import '../../../../shared/widgets/page_heading.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../customer/marketplace/presentation/providers/marketplace_providers.dart';

class QuoteRequestsScreen extends ConsumerWidget {
  const QuoteRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supplierId = ref.watch(currentUserProvider)?.uid ?? '';
    final quotesAsync = ref.watch(supplierQuoteRequestsProvider(supplierId));
    final isLoading =
        quotesAsync.isLoading && quotesAsync.valueOrNull == null;
    final quotes = quotesAsync.valueOrNull ?? const <QuoteRequest>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.accent))
                : quotesAsync.hasError && quotes.isEmpty
                    ? _scrollableState(
                        EmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: 'Could not load quote requests',
                          subtitle: 'Check your connection and try again.',
                          actionLabel: 'Retry',
                          onAction: () => ref
                              .invalidate(supplierQuoteRequestsProvider(supplierId)),
                        ),
                      )
                    : quotes.isEmpty
                        ? _scrollableState(
                            const EmptyState(
                              icon: Icons.request_quote_outlined,
                              title: 'No quote requests yet',
                              subtitle: 'When buyers ask for bulk pricing on '
                                  'your products, their requests appear here.',
                            ),
                          )
                        : _list(context, quotes),
          ),
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 8,
            left: 8,
            child: const FloatingBackButton(),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, List<QuoteRequest> quotes) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.paddingOf(context).bottom + 24),
      children: [
        const PageHeading(title: 'Quote requests'),
        const SizedBox(height: 12),
        const QuoteRequestsBanner(),
        const SizedBox(height: 6),
        for (final request in quotes)
          _QuoteTile(
            request: request,
            onTap: () => context.pushNamed(
              RouteNames.supplierQuoteRequestDetail,
              pathParameters: {'id': request.id},
            ),
          ),
      ],
    );
  }

  Widget _scrollableState(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }
}

// Shared by the quote list and detail screens — the whole feature's contract
// with the buyer happens off-app, so both sides must say it out loud.
class QuoteRequestsBanner extends StatelessWidget {
  const QuoteRequestsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Contact buyers outside the app — call or email them directly. '
              'Payment and delivery are arranged with the buyer.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteTile extends StatelessWidget {
  const _QuoteTile({required this.request, required this.onTap});

  final QuoteRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final contacted = request.isContacted;
    return Container(
      margin: const EdgeInsets.only(top: 10),
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.productName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Qty ${request.quantity} · ${request.customerName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusBadge(
                    label: contacted ? 'Contacted' : 'Pending',
                    color:
                        contacted ? AppColors.success : AppColors.warning,
                    compact: true,
                  ),
                  const SizedBox(height: 6),
                  const Icon(Icons.chevron_right,
                      size: 20, color: AppColors.textHint),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
