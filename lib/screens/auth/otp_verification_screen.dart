import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import 'login_screen.dart';
import 'widgets/auth_scaffold.dart';

class OtpVerificationScreen extends ConsumerStatefulWidget {
  final String email;
  const OtpVerificationScreen({super.key, required this.email});

  @override
  ConsumerState<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final _codeController = TextEditingController();

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    try {
      final success = await ref.read(authProvider.notifier).confirmSignUp(
            email: widget.email,
            confirmationCode: code,
          );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification successful! Please log in.'),
            backgroundColor: AppColors.accentGreen,
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          AppMotion.fadeSlideRoute(const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification failed or code is invalid.'),
            backgroundColor: AppColors.accentRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState == AuthState.loading;

    return AuthScaffold(
      showBack: true,
      title: "Verify Email",
      children: [
        const SizedBox(height: 24),
        const AuthBrandLogo(icon: Icons.mark_email_read_outlined, size: 80),
        AppSpacing.vGapXxl,
        Text(
          "Check your inbox",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displayLarge,
        ),
        AppSpacing.vGapMd,
        Text(
          "We've sent a 6-digit confirmation code to\n${widget.email}",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSub(context),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.borderCol(context),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextField(
            controller: _codeController,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.text(context),
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 10,
            ),
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: InputDecoration(
              counterText: "",
              hintText: "000000",
              hintStyle: TextStyle(
                color: AppColors.textSub(context).withValues(alpha: 0.4),
                letterSpacing: 10,
                fontSize: 28,
              ),
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
            ),
          ),
        ),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: "Verify Code",
          icon: Icons.verified_user_outlined,
          loading: isLoading,
          onPressed: _verifyCode,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
