import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/user_errors.dart';
import '../../../../../models/saved_address.dart';
import '../../../../../services/marketplace_repository.dart';
import '../../../../../shared/widgets/app_feedback.dart';
import '../../../../../shared/widgets/confirm_dialog.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/float_button.dart';
import '../../../../../shared/widgets/page_heading.dart';
import '../../../../auth/presentation/providers/auth_providers.dart';
import '../providers/marketplace_providers.dart';

class SavedAddressesScreen extends ConsumerWidget {
  const SavedAddressesScreen({super.key});

  Future<void> _setDefault(WidgetRef ref, BuildContext context, String id) async {
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;
    try {
      await ref.read(marketplaceRepositoryProvider).setDefaultAddress(uid, id);
    } catch (e) {
      if (!context.mounted) return;
      showAppSnackbar(
        context,
        userMessage(e, fallback: 'Could not set the default address.'),
        color: AppColors.error,
      );
    }
  }

  Future<void> _delete(
      WidgetRef ref, BuildContext context, SavedAddress address) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete address?',
      message: 'This saved address will be removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;
    try {
      await ref
          .read(marketplaceRepositoryProvider)
          .deleteAddress(uid, address.id);
      if (context.mounted) {
        showAppSnackbar(context, 'Address deleted');
      }
    } catch (e) {
      if (!context.mounted) return;
      showAppSnackbar(
        context,
        userMessage(e, fallback: 'Could not delete the address.'),
        color: AppColors.error,
      );
    }
  }

  Future<void> _edit(
      WidgetRef ref, BuildContext context, SavedAddress address) async {
    final edited = await showDialog<SavedAddress>(
      context: context,
      builder: (_) => _AddressFormDialog(initial: address),
    );
    if (edited == null) return;
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;
    try {
      await ref.read(marketplaceRepositoryProvider).saveAddress(uid, edited);
    } catch (e) {
      if (!context.mounted) return;
      showAppSnackbar(
        context,
        userMessage(e, fallback: 'Could not save the address.'),
        color: AppColors.error,
      );
    }
  }

  Future<void> _add(WidgetRef ref, BuildContext context) async {
    final created = await showDialog<SavedAddress>(
      context: context,
      builder: (_) => const _AddressFormDialog(),
    );
    if (created == null) return;
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid == null) return;
    try {
      final existing =
          ref.read(savedAddressesProvider).valueOrNull ?? const <SavedAddress>[];
      final toSave = existing.isEmpty
          ? created.copyWith(isDefault: true)
          : created;
      await ref.read(marketplaceRepositoryProvider).saveAddress(uid, toSave);
    } catch (e) {
      if (!context.mounted) return;
      showAppSnackbar(
        context,
        userMessage(e, fallback: 'Could not save the address.'),
        color: AppColors.error,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.watch(savedAddressesProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: addressesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              error: (_, __) => EmptyState(
                icon: Icons.error_outline,
                title: "Couldn't load your addresses",
                subtitle: 'Check your connection and try again',
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(savedAddressesProvider),
              ),
              data: (addresses) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 60, 16, 32),
                children: [
                  const PageHeading(
                    title: 'Saved addresses',
                    subtitle: 'Switch easily between your delivery spots',
                  ),
                  const SizedBox(height: 16),
                  if (addresses.isEmpty)
                    EmptyState(
                      icon: Icons.location_on_outlined,
                      title: 'No saved addresses yet',
                      subtitle: 'Addresses you use at checkout will appear '
                          'here.',
                    )
                  else
                    for (final a in addresses) ...[
                      _AddressCard(
                        address: a,
                        onSetDefault: () => _setDefault(ref, context, a.id),
                        onEdit: () => _edit(ref, context, a),
                        onDelete: () => _delete(ref, context, a),
                      ),
                      const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => _add(ref, context),
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text(
                        'Add address',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.onSetDefault,
    required this.onEdit,
    required this.onDelete,
  });

  final SavedAddress address;
  final VoidCallback onSetDefault;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: address.isDefault ? AppColors.accent : AppColors.border,
          width: address.isDefault ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  address.label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (address.isDefault)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Default',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            address.recipientName,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          if (address.phone.isNotEmpty)
            Text(
              address.phone,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            address.address,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textHint,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (!address.isDefault)
                TextButton(
                  onPressed: onSetDefault,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Set default',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              const Spacer(),
              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Edit',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Delete',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddressFormDialog extends StatefulWidget {
  const _AddressFormDialog({this.initial});

  final SavedAddress? initial;

  @override
  State<_AddressFormDialog> createState() => _AddressFormDialogState();
}

class _AddressFormDialogState extends State<_AddressFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.initial?.label ?? '');
    _nameCtrl =
        TextEditingController(text: widget.initial?.recipientName ?? '');
    _phoneCtrl = TextEditingController(text: widget.initial?.phone ?? '');
    _addressCtrl = TextEditingController(text: widget.initial?.address ?? '');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final initial = widget.initial;
    Navigator.pop(
      context,
      SavedAddress(
        id: initial?.id ?? MarketplaceRepository.newOrderId(),
        label: _labelCtrl.text.trim(),
        recipientName: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        isDefault: initial?.isDefault ?? false,
        createdAt: initial?.createdAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.initial == null ? 'Add address' : 'Edit address',
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _labelCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'e.g. Home, Office',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Label is required';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Full name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: 'e.g. 012-345 6789',
                ),
                validator: (v) {
                  final digits = (v ?? '').replaceAll(RegExp(r'[\s\-+()]'), '');
                  if (digits.length < 9 || digits.length > 15) {
                    return 'Enter a valid phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _addressCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Delivery address',
                  hintText: 'Street, area, city, postcode, state',
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.length < 10) {
                    return 'Please enter your full delivery address';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            minimumSize: Size.zero,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
