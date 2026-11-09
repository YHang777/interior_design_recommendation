import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/user_errors.dart';
import '../../../../models/quote_request.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/float_button.dart';
import '../../../../shared/widgets/page_heading.dart';
import '../../../../shared/widgets/product_image.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../customer/marketplace/presentation/providers/marketplace_providers.dart';
import 'quote_requests_screen.dart';

class QuoteRequestDetailScreen extends ConsumerStatefulWidget {
  const QuoteRequestDetailScreen({super.key, required this.requestId});

  final String requestId;

  @override
  ConsumerState<QuoteRequestDetailScreen> createState() =>
      _QuoteRequestDetailScreenState();
}

class _QuoteRequestDetailScreenState
    extends ConsumerState<QuoteRequestDetailScreen> {
  bool _working = false;
  bool _contactedLocally = false;

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _callBuyer(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    try {
      final uri = Uri(scheme: 'tel', path: digits);
      final ok = await launchUrl(uri);
      if (!ok && mounted) {
        showAppSnackbar(context, 'Could not open the dialer',
            isError: true, duration: const Duration(seconds: 3));
      }
    } catch (_) {
      if (mounted) {
        showAppSnackbar(context, 'Could not open the dialer',
            isError: true, duration: const Duration(seconds: 3));
      }
    }
  }

  Future<void> _launchExternal(String url, String unsupportedMessage) async {
    final uri = Uri.parse(url);
    final can = await canLaunchUrl(uri);
    if (!can) {
      if (mounted) showAppSnackbar(context, unsupportedMessage);
      return;
    }
    final ok = await launchUrl(uri);
    if (!ok && mounted) showAppSnackbar(context, unsupportedMessage);
  }

  Future<void> _markContacted(QuoteRequest request) async {
    setState(() => _working = true);
    try {
      await ref
          .read(marketplaceRepositoryProvider)
          .markQuoteContacted(request.id);
      if (!mounted) return;
      setState(() {
        _contactedLocally = true;
        _working = false;
      });
      showAppSnackbar(
        context,
        'Marked as contacted',
        color: AppColors.success,
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _working = false);
      showAppSnackbar(
        context,
        userMessage(e, fallback: 'Could not update the request. Please try again.'),
        isError: true,
        duration: const Duration(seconds: 4),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final supplierId = ref.watch(currentUserProvider)?.uid ?? '';
    final quotesAsync = ref.watch(supplierQuoteRequestsProvider(supplierId));
    final isLoading =
        quotesAsync.isLoading && quotesAsync.valueOrNull == null;

    final request = quotesAsync.valueOrNull
        ?.where((q) => q.id == widget.requestId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.accent))
                : request == null
                    ? quotesAsync.hasError
                        ? EmptyState(
                            icon: Icons.cloud_off_outlined,
                            title: 'Could not load this request',
                            subtitle: 'Check your connection and try again.',
                            actionLabel: 'Go back',
                            onAction: () =>
                                Navigator.of(context).maybePop(),
                          )
                        : EmptyState(
                            icon: Icons.request_quote_outlined,
                            title: 'Quote request not found',
                            subtitle: 'It may have been removed.',
                            actionLabel: 'Go back',
                            onAction: () =>
                                Navigator.of(context).maybePop(),
                          )
                    : _body(request),
          ),
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 8,
            left: 8,
            child: const FloatingBackButton(),
          ),
        ],
      ),
      bottomNavigationBar: request == null ? null : _actionBar(request),
    );
  }

  Widget _body(QuoteRequest request) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 60, 16, MediaQuery.paddingOf(context).bottom + 32),
      children: [
        const PageHeading(title: 'Quote request'),
        const SizedBox(height: 16),
        _sectionCard(
          'Product',
          trailing: StatusBadge(
            label: _contactedLocally || request.isContacted
                ? 'Contacted'
                : 'Pending',
            color: _contactedLocally || request.isContacted
                ? AppColors.success
                : AppColors.warning,
            compact: true,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: ProductImage(
                    imageUrl: request.productImage ?? '',
                    fit: BoxFit.cover,
                    errorIconSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 10),
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
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Qty ${request.quantity} · '
                      'Requested ${Formatters.shortDateTime(request.createdAt)}',
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        color: AppColors.textHint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const QuoteRequestsBanner(),
        const SizedBox(height: 14),
        _sectionCard('Buyer', child: _buyerBlock(request)),
        if (request.note.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionCard(
            'What they need',
            child: Text(
              request.note.trim(),
              style: GoogleFonts.poppins(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buyerBlock(QuoteRequest request) {
    final phone = request.customerPhone.trim();
    final email = request.customerEmail.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_outline,
                  size: 20, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.customerName,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  if (email.isNotEmpty)
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 11.5,
                        color: AppColors.textHint,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _callBuyer(phone),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.phone_outlined,
                      size: 16, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    Formatters.phone(phone),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.accent,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.call_outlined,
                      size: 16, color: AppColors.accent),
                ],
              ),
            ),
          ),
        ],
        if (email.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _launchExternal(
                  'mailto:$email', 'Email isn\'t supported on this device'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(fontSize: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.email_outlined, size: 16),
              label: const Text('Email'),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.handshake_outlined,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Contact the buyer outside the app to agree on price, '
                'quantity and delivery.',
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sectionCard(String title, {required Widget child, Widget? trailing}) {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _actionBar(QuoteRequest request) {
    final contacted = _contactedLocally || request.isContacted;
    final contactedAt = request.contactedAt;

    return Container(
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
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: contacted
              ? Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle,
                          size: 18, color: AppColors.success),
                      const SizedBox(width: 8),
                      Text(
                        'Contacted ✓',
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                      if (contactedAt != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          Formatters.shortDate(contactedAt),
                          style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : SizedBox(
                  height: 52,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: _working
                          ? null
                          : const LinearGradient(
                              colors: [
                                AppColors.accent,
                                AppColors.gradientGreen,
                              ],
                            ),
                      borderRadius: BorderRadius.circular(14),
                      color: _working ? AppColors.border : null,
                    ),
                    child: ElevatedButton(
                      onPressed: _working ? null : () => _markContacted(request),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.transparent,
                        disabledForegroundColor: AppColors.textHint,
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _working
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text(
                              'Mark as contacted',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
