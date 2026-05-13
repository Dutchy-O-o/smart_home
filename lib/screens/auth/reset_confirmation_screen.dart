import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import 'login_screen.dart';
import 'widgets/auth_scaffold.dart';

class ResetConfirmationScreen extends StatelessWidget {
  const ResetConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      children: [
        const SizedBox(height: 48),
        Center(
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: AppColors.brandGradient,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.45),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.mail_outline_rounded,
                  size: 56,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.bg(context),
                  shape: BoxShape.circle,
                ),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: const BoxDecoration(
                    color: AppColors.accentGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        Text(
          "Check your mail",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displayLarge,
        ),
        AppSpacing.vGapLg,
        Text(
          "We have sent password recovery instructions to your email. Please check your inbox and spam folder.",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSub(context),
            fontSize: 15,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 36),
        AuthPrimaryButton(
          label: "Return to Login",
          icon: Icons.login_rounded,
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              AppMotion.fadeSlideRoute(const LoginScreen()),
              (route) => false,
            );
          },
        ),
        const SizedBox(height: 40),
        Center(
          child: Column(
            children: [
              Text("Did not receive the email?",
                  style: TextStyle(color: AppColors.textSub(context))),
              AppSpacing.vGapSm,
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Email resent successfully!")),
                  );
                },
                child: Text(
                  "Resend Email",
                  style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
