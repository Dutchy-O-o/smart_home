import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import 'reset_confirmation_screen.dart';
import 'widgets/auth_scaffold.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();

  void _handleSendResetLink() {
    String email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a valid email address."),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      AppMotion.fadeSlideRoute(const ResetConfirmationScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      showBack: true,
      title: "Reset Password",
      children: [
        const SizedBox(height: 24),
        const AuthBrandLogo(icon: Icons.lock_reset_rounded, size: 80),
        const SizedBox(height: 28),
        Text(
          "Forgot Password?",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontSize: 26,
              ),
        ),
        AppSpacing.vGapMd,
        Text(
          "Don't worry, it happens to the best of us. Enter the email address linked to your Smart Home Hub below, and we'll send you rescue instructions.",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSub(context),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 36),
        AuthInput(
          controller: _emailController,
          label: "Email Address",
          hint: "name@example.com",
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 28),
        AuthPrimaryButton(
          label: "Send Reset Link",
          icon: Icons.send_rounded,
          onPressed: _handleSendResetLink,
        ),
        const SizedBox(height: 32),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Remembered your password? ",
                  style: TextStyle(color: AppColors.textSub(context))),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Text(
                  "Log In",
                  style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_outlined,
                  size: 14, color: AppColors.textSub(context)),
              const SizedBox(width: 6),
              Text(
                "SECURED BY MQTT",
                style: TextStyle(
                  color: AppColors.textSub(context).withValues(alpha: 0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
