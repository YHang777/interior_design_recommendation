// The app's SearchBar (shared/widgets) shadows Flutter's material SearchBar.
import 'package:flutter/material.dart' hide SearchBar;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/product.dart';
import '../../../../services/model_generation/generation_decider.dart';
import '../../../../services/model_generation/model_generation_trigger.dart';
import '../../../../shared/widgets/app_feedback.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/filter_chip_bar.dart';
import '../../../../shared/widgets/product_image.dart';
import '../../../../shared/widgets/quantity_stepper.dart';
import '../../../../shared/widgets/search_bar.dart';
import '../../../../shared/widgets/stat_card.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../marketplace/presentation/providers/marketplace_providers.dart';
import '../providers/supplier_providers.dart';

/// Supplier's product catalogue screen: stats, search, status filters and
/// per-product lifecycle actions (pause/resume, stock edit, edit, delete).
class ProductManagementScreen extends ConsumerStatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  ConsumerState<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

enum _ProductFilter { all, active, paused, lowStock }

enum _OverflowAction { regenerate3D }

class _ProductManagementScreenState
    extends ConsumerState<ProductManagementScreen> {
  String _query = '';
  _ProductFilter _filter = _ProductFilter.all;

  /// Optimistic active-state overrides keyed by product id. While an entry
  /// is present the UI shows this value instead of the streamed one.
  final Map<String, bool> _activeOverride = {};

  /// Product ids with a toggle/stock/delete request in flight.
  final Set<String> _busy = {};

  // ── Navigation ─────────────────────────────────────────────────────────

  void _goNew() => context.pushNamed(RouteNames.supplierProductNew);

  void _goEdit(Product p) => context.pushNamed(
        RouteNames.supplierProductEdit,
        pathParameters: {'id': p.id},
      );

  // ── Actions ────────────────────────────────────────────────────────────

  Future<void> _toggleActive(Product p, bool next) async {
    if (_busy.contains(p.id)) return;
    setState(() {
      _busy.add(p.id);
      _activeOverride[p.id] = next;
    });
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      await repo.setProductActive(p.id, next);
      // The stream now reflects the change — drop the override once it
      // matches the real value.
      if (mounted) {
        setState(() => _activeOverride.remove(p.id));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _activeOverride.remove(p.id));
      showAppSnackbar(
        context,
        next ? 'Could not activate "${p.name}"' : 'Could not pause "${p.name}"',
        isError: true,
        detail: e.toString(),
        duration: const Duration(seconds: 4),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  Future<void> _editStock(Product p) async {
    if (_busy.contains(p.id)) return;
    var stock = p.stock;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            title: Text(
              'Edit stock',
              style: GoogleFonts.poppins(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Icon(Icons.inventory_2_outlined,
                        size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      'Units available',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    QuantityStepper(
                      value: stock,
                      min: 0,
                      max: 9999,
                      onChanged: (v) => setDialogState(() => stock = v),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.textOnDark,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || stock == p.stock || !mounted) return;
    await _saveStock(p, stock);
  }

  Future<void> _saveStock(Product p, int stock) async {
    setState(() => _busy.add(p.id));
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      // The stock dialog was seeded from THIS streamed snapshot, so the
      // seller's change is `stock − p.stock`; the repository applies that
      // delta to the live document stock inside a transaction.
      await repo.updateProduct(p.copyWith(stock: stock),
          originalStock: p.stock);
      if (mounted) {
        showAppSnackbar(context, 'Stock updated to $stock units for "${p.name}"',
            color: AppColors.success, duration: const Duration(seconds: 3));
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(context, 'Could not update stock for "${p.name}"',
            isError: true,
            detail: e.toString(),
            duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  Future<void> _delete(Product p) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete ${p.name}?',
      message:
          'This will remove the product from the marketplace permanently. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy.add(p.id));
    final repo = ref.read(marketplaceRepositoryProvider);
    try {
      await repo.deleteProduct(p.id);
      if (mounted) {
        showAppSnackbar(context, '"${p.name}" was deleted',
            color: AppColors.success, duration: const Duration(seconds: 3));
      }
    } catch (e) {
      if (mounted) {
        showAppSnackbar(context, 'Could not delete "${p.name}"',
            isError: true,
            detail: e.toString(),
            duration: const Duration(seconds: 4));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  /// Retry from the red "3D failed — retry" chip.
  void _retry3D(Product p) => _run3DGeneration(p, force: true);

  /// "Regenerate 3D" overflow action for a product with a healthy model —
  /// `force` re-submits a fresh Tripo task (or re-stamps the procedural
  /// ready state), which is exactly what the seller asked for.
  void _regenerate3D(Product p) => _run3DGeneration(p, force: true);

  /// Runs the kick-off and surfaces a snackbar driven by the [GenerationDecision]
  /// it returned. The decision enum is what guarantees the message matches
  /// reality: a Retry on a transient failure says the SAME task is being
  /// re-checked (no extra charge); "Regenerate 3D" on a ready Tripo product
  /// that is not AI-eligible says the current AI model was KEPT instead of
  /// silently overwriting it with the procedural model.
  void _run3DGeneration(Product p, {required bool force}) {
    final decision = kickOffProduct3DGeneration(p, force: force);
    if (!mounted) return;
    switch (decision.action) {
      case GenerationAction.submitNewTripo:
      case GenerationAction.stampProcedural:
        // Work is in flight / a new model will appear shortly.
        showAppSnackbar(
          context,
          decision.message.isEmpty
              ? 'Starting 3D generation for "${p.name}"…'
              : decision.message,
          color: AppColors.warning,
          duration: const Duration(seconds: 3),
        );
        break;
      case GenerationAction.pollExistingTask:
        // Free re-check of the already-paid task — no new submission.
        showAppSnackbar(
          context,
          decision.message.isEmpty
              ? 'Continuing the running AI task for "${p.name}"…'
              : decision.message,
          color: AppColors.warning,
          duration: const Duration(seconds: 3),
        );
        break;
      case GenerationAction.none:
        // Nothing was (re)written — explain why.
        showAppSnackbar(
          context,
          decision.message.isEmpty
              ? 'No 3D model change needed for "${p.name}".'
              : decision.message,
          color: AppColors.success,
          duration: const Duration(seconds: 4),
        );
        break;
      case GenerationAction.markFailed:
      case GenerationAction.markNoModel:
        showAppSnackbar(
          context,
          decision.message,
          color: AppColors.error,
          duration: const Duration(seconds: 4),
        );
        break;
    }
  }

  // ── Data derivation ────────────────────────────────────────────────────

  List<Product> _visible(List<Product> mine) {
    final query = _query.trim().toLowerCase();
    return mine.where((p) {
      if (query.isNotEmpty && !p.name.toLowerCase().contains(query)) {
        return false;
      }
      final override = _activeOverride[p.id];
      final isActive = override ?? p.isActive;
      return switch (_filter) {
        _ProductFilter.all => true,
        _ProductFilter.active => isActive,
        _ProductFilter.paused => !isActive,
        _ProductFilter.lowStock => p.stock > 0 && p.stock < 5,
      };
    }).toList();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final supplierId = user?.uid ?? '';
    final productsAsync = ref.watch(marketplaceProductsProvider);
    final isLoading =
        productsAsync.isLoading && productsAsync.valueOrNull == null;

    final all = productsAsync.valueOrNull ?? const <Product>[];
    final mine =
        supplierId.isEmpty ? <Product>[] : productsOfSupplier(all, supplierId);
    final activeCount =
        mine.where((p) => _activeOverride[p.id] ?? p.isActive).length;
    final lowCount = lowStockProducts(mine, supplierId).length;
    final visible = _visible(mine);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Products'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _goNew,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add product'),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.accent,
        child: isLoading
            ? const _ProductsSkeletonList()
            : productsAsync.hasError && all.isEmpty
                ? _scrollableState(
                    EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: 'Could not load products',
                      subtitle: 'Check your connection and try again.',
                      actionLabel: 'Retry',
                      onAction: _refresh,
                    ),
                  )
                : mine.isEmpty
                    ? _scrollableState(
                        EmptyState(
                          icon: Icons.storefront_outlined,
                          title: 'No products yet',
                          subtitle: 'Post your first product and it will '
                              'appear in the marketplace right away.',
                          actionLabel: 'Add your first product',
                          onAction: _goNew,
                        ),
                      )
                    : visible.isEmpty
                        ? _scrollableState(
                            EmptyState(
                              icon: Icons.search_off,
                              title: 'No products match',
                              subtitle: 'Try a different search or filter.',
                              actionLabel: 'Clear filters',
                              onAction: () => setState(() {
                                _query = '';
                                _filter = _ProductFilter.all;
                              }),
                            ),
                          )
                        : _content(
                            mine.length, activeCount, lowCount, visible),
      ),
    );
  }

  Future<void> _refresh() async {
    try {
      final _ = await ref.refresh(marketplaceProductsProvider.future);
    } catch (_) {
      // Pull-to-refresh is best effort; the stream surfaces errors itself.
    }
  }

  Widget _content(
      int total, int active, int low, List<Product> visible) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          children: [
            StatCard(
              icon: Icons.inventory_2_outlined,
              label: 'Total products',
              value: '$total',
              gradient: const [AppColors.primary, AppColors.primaryLight],
            ),
            const SizedBox(width: 10),
            StatCard(
              icon: Icons.visibility_outlined,
              label: 'Active',
              value: '$active',
              gradient: const [AppColors.accent, AppColors.gradientGreen],
            ),
            const SizedBox(width: 10),
            StatCard(
              icon: Icons.priority_high_outlined,
              label: 'Low stock',
              value: '$low',
              gradient: const [AppColors.warning, AppColors.gradientOrange],
              onTap: low > 0
                  ? () => setState(() => _filter = _ProductFilter.lowStock)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SearchBar(
          hintText: 'Search your products…',
          onChanged: (q) => setState(() => _query = q),
        ),
        const SizedBox(height: 12),
        FilterChipBar<_ProductFilter>(
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.tune,
                size: 16, color: AppColors.textSecondary),
          ),
          options: _ProductFilter.values,
          selected: _filter,
          labelBuilder: (f) => switch (f) {
            _ProductFilter.all => 'All',
            _ProductFilter.active => 'Active',
            _ProductFilter.paused => 'Paused',
            _ProductFilter.lowStock => 'Low stock',
          },
          onSelected: (f) => setState(() => _filter = f),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 2),
          child: Text(
            '${visible.length} of $total products',
            style: GoogleFonts.poppins(
              fontSize: 11.5,
              color: AppColors.textHint,
            ),
          ),
        ),
        ...visible.map((p) => _ProductTile(
              product: p,
              overrideActive: _activeOverride[p.id],
              busy: _busy.contains(p.id),
              onOpen: () => _goEdit(p),
              onToggleActive: (next) => _toggleActive(p, next),
              onEditStock: () => _editStock(p),
              onRetry3D: () => _retry3D(p),
              onRegenerate3D: () => _regenerate3D(p),
              onDelete: () => _delete(p),
            )),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Keeps empty/error states inside a scrollable so pull-to-refresh works.
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

/// ── Product row ─────────────────────────────────────────────────────────

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.overrideActive,
    required this.busy,
    required this.onOpen,
    required this.onToggleActive,
    required this.onEditStock,
    required this.onRetry3D,
    required this.onRegenerate3D,
    required this.onDelete,
  });

  final Product product;
  final bool? overrideActive;
  final bool busy;
  final VoidCallback onOpen;
  final ValueChanged<bool> onToggleActive;
  final VoidCallback onEditStock;

  /// Retry tap from the red "3D failed" chip.
  final VoidCallback onRetry3D;

  /// "Regenerate 3D" from the overflow menu (ready products only).
  final VoidCallback onRegenerate3D;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isActive = overrideActive ?? product.isActive;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: ProductImage(
                      imageUrl: product.resolvedImages.isNotEmpty
                          ? product.resolvedImages.first
                          : '',
                      fit: BoxFit.cover,
                      errorIconSize: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: busy ? null : onOpen,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                Formatters.myr(product.price),
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.accent,
                                ),
                              ),
                              if (product.discountPercent != null) ...[
                                const SizedBox(width: 6),
                                _Pill(
                                  label: '-${product.discountPercent}%',
                                  color: AppColors.error,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              _stockPill(product),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: busy ? null : onEditStock,
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.all(3),
                                  child: Icon(
                                    Icons.mode_edit_outline,
                                    size: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          _arStatusRow(product),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Pause / resume — optimistic with revert on failure.
                Switch(
                  value: isActive,
                  onChanged: busy ? null : onToggleActive,
                  activeTrackColor: AppColors.accentLight,
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: AppColors.divider),
          Row(
            children: [
              _RowAction(
                icon: Icons.edit_outlined,
                label: 'Edit',
                color: AppColors.textSecondary,
                onTap: busy ? null : onOpen,
              ),
              _RowAction(
                icon: Icons.inventory_2_outlined,
                label: 'Stock',
                color: AppColors.textSecondary,
                onTap: busy ? null : onEditStock,
              ),
              const Spacer(),
              // Regenerate 3D lives in the overflow menu of READY products
              // (an explicit seller action — it re-submits a paid Tripo task
              // when one is configured).
              if (product.ar3d?.isReady ?? false)
                PopupMenuButton<_OverflowAction>(
                  tooltip: 'More actions',
                  icon: Icon(Icons.more_horiz,
                      size: 20, color: AppColors.textSecondary),
                  splashRadius: 20,
                  onSelected: (action) {
                    switch (action) {
                      case _OverflowAction.regenerate3D:
                        onRegenerate3D();
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(
                      value: _OverflowAction.regenerate3D,
                      child: Row(
                        children: [
                          Icon(Icons.view_in_ar_outlined,
                              size: 18, color: AppColors.secondaryAccent),
                          SizedBox(width: 8),
                          Text('Regenerate 3D'),
                        ],
                      ),
                    ),
                  ],
                ),
              _RowAction(
                icon: Icons.delete_outline,
                label: 'Delete',
                color: busy ? AppColors.textHint : AppColors.error,
                onTap: busy ? null : onDelete,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ],
      ),
    );
  }

  /// AR-pipeline status line: a green "3D ready" pill, an amber "3D
  /// generating…" pill, or a red tappable "3D failed — retry" pill. Rows
  /// without a 3D state (legacy products) show nothing.
  Widget _arStatusRow(Product p) {
    final ar3d = p.ar3d;
    if (ar3d == null) return const SizedBox.shrink();
    final String label;
    final Color color;
    VoidCallback? onTap;
    switch (ar3d.status) {
      case 'ready':
        label = '3D ready';
        color = AppColors.success;
      case 'generating':
        label = '3D generating…';
        color = AppColors.warning;
      case 'failed':
        label = '3D failed — retry';
        color = AppColors.error;
        onTap = busy ? null : onRetry3D;
      default:
        return const SizedBox.shrink();
    }
    final pill = _Pill(label: label, color: color);
    final padded = Padding(
      padding: const EdgeInsets.only(top: 6),
      child: pill,
    );
    if (onTap == null) return padded;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        button: true,
        label: 'Retry 3D generation',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: pill,
        ),
      ),
    );
  }

  Widget _stockPill(Product p) {
    if (p.isOutOfStock) {
      return _Pill(label: 'Out of stock', color: AppColors.error);
    }
    if (p.isLowStock) {
      return _Pill(label: 'Low · ${p.stock} left', color: AppColors.warning);
    }
    return _Pill(label: 'In stock · ${p.stock}', color: AppColors.success);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15,
                color: enabled ? color : AppColors.textHint),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: enabled ? color : AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ── Loading skeleton rows ───────────────────────────────────────────────

class _ProductsSkeletonList extends StatelessWidget {
  const _ProductsSkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        height: 104,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 12,
                    width: 160,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 14,
                    width: 90,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 10,
                    width: 70,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
