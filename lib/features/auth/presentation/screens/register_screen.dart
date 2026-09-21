import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/validators.dart';
import '../../data/models/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../providers/auth_providers.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  UserRole _role = UserRole.homeowner;
  bool _obscure = true;

  bool get _isSupplier => _role == UserRole.supplier;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    _confirmCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    final created = await ref.read(authStateProvider.notifier).register(
      email: _emailCtrl.text.trim(),
      password: _pwdCtrl.text,
      name: _nameCtrl.text.trim(),
      role: _role,
      phone: _isSupplier ? _phoneCtrl.text.trim() : null,
      address: _isSupplier ? _addressCtrl.text.trim() : null,
    );
    if (created == null || !mounted) return;
    context.push(Uri(
      path: '/verify-email',
      queryParameters: {'email': created.email, 'uid': created.uid},
    ).toString());
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(text,
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authStateProvider);
    final loading = state is AsyncLoading<AppUser?>;
    final nameLabel = _isSupplier ? 'Business Name' : 'Full Name';

    ref.listen<AsyncValue<AppUser?>>(authStateProvider, (_, next) {
      next.whenOrNull(error: (e, _) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AuthException ? e.message : 'Registration failed'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      });
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Create Account',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Get started',
                  style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Fill in your details below',
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 20),

              // -- Role selector --
              SegmentedButton<UserRole>(
                segments: const [
                  ButtonSegment(
                    value: UserRole.homeowner,
                    label: Text('Homeowner'),
                    icon: Icon(Icons.home_outlined),
                  ),
                  ButtonSegment(
                    value: UserRole.supplier,
                    label: Text('Supplier'),
                    icon: Icon(Icons.storefront_outlined),
                  ),
                ],
                selected: {_role},
                onSelectionChanged: (selection) {
                  setState(() => _role = selection.first);
                },
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: AppColors.accent,
                  selectedForegroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.border),
                  textStyle: GoogleFonts.poppins(fontSize: 14),
                ),
              ),
              if (_isSupplier) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                      'Supplier listings publish instantly once your email is verified.',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.accent)),
                ),
              ],

              // -- Account section --
              _sectionLabel('Account Details'),
              TextFormField(
                controller: _nameCtrl,
                keyboardType: TextInputType.name,
                textInputAction: TextInputAction.next,
                validator: (v) => Validators.required(v, nameLabel),
                decoration: InputDecoration(
                    labelText: nameLabel,
                    prefixIcon: Icon(_isSupplier
                        ? Icons.business_outlined
                        : Icons.person_outlined)),
              ),
              const SizedBox(height: 16),

              // -- Supplier-only business contact fields --
              if (_isSupplier) ...[
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  validator: (v) => Validators.required(v, 'Business phone'),
                  decoration: const InputDecoration(
                      labelText: 'Business Phone',
                      prefixIcon: Icon(Icons.phone_outlined)),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressCtrl,
                  keyboardType: TextInputType.streetAddress,
                  textInputAction: TextInputAction.next,
                  maxLines: 2,
                  validator: (v) => Validators.required(v, 'Business address'),
                  decoration: const InputDecoration(
                      labelText: 'Business Address',
                      prefixIcon: Icon(Icons.location_on_outlined)),
                ),
              ],

              // -- Contact section --
              _sectionLabel('Login Credentials'),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: Validators.email,
                decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined)),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pwdCtrl,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                validator: Validators.password,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                validator: (v) => Validators.confirmPassword(v, _pwdCtrl.text),
                onFieldSubmitted: (_) => _register(),
                decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: Icon(Icons.lock_outlined)),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: loading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    shadowColor: AppColors.accent.withValues(alpha: 0.4),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : Text(
                          _isSupplier ? 'Register as Supplier' : 'Create Account',
                          style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text('Already have an account?',
                        style: GoogleFonts.poppins(
                            fontSize: 14, color: AppColors.textSecondary)),
                  ),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: Text('Sign In',
                        style: GoogleFonts.poppins(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
