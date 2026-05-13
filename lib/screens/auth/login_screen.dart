import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import '../dashboard/home_selection_screen.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import 'widgets/auth_scaffold.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isObscured = true;

  Future<void> _handleLogin() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Invalid email or password. Please try again."),
          backgroundColor: AppColors.accentRed,
        ),
      );
      return;
    }

    try {
      final success = await ref.read(authProvider.notifier).signIn(
            email: email,
            password: password,
          );

      if (success && mounted) {
        Navigator.pushReplacement(
          context,
          AppMotion.fadeSlideRoute(const HomeSelectionScreen()),
        );
      }
    } catch (e) {
      safePrint('Login error: $e');
      if (mounted) {
        String message = "Invalid username or password.";
        if (e.toString().toLowerCase().contains('already signed in')) {
          message = "A user is already signed in. Please log out first.";
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
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
      children: [
        const SizedBox(height: 32),
        const AuthBrandLogo(icon: Icons.home_rounded),
        AppSpacing.vGapXxl,
        Text(
          "Welcome Home",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displayLarge,
        ),
        AppSpacing.vGapSm,
        Text(
          "Securely access your smart home network.",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSub(context),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 40),
        AuthInput(
          controller: _emailController,
          label: "Email or Username",
          hint: "user@example.com",
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        AppSpacing.vGapXl,
        AuthInput(
          controller: _passwordController,
          label: "Password",
          hint: "••••••••",
          icon: Icons.lock_outline_rounded,
          obscure: _isObscured,
          suffix: IconButton(
            icon: Icon(
              _isObscured
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: AppColors.textSub(context),
              size: 20,
            ),
            onPressed: () => setState(() => _isObscured = !_isObscured),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              Navigator.push(
                context,
                AppMotion.fadeSlideRoute(const ForgotPasswordScreen()),
              );
            },
            child: Text(
              "Forgot Password?",
              style: TextStyle(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        AppSpacing.vGapLg,
        AuthPrimaryButton(
          label: "Secure Login",
          icon: Icons.bolt_rounded,
          loading: isLoading,
          onPressed: _handleLogin,
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Don't have an account? ",
              style: TextStyle(color: AppColors.textSub(context)),
            ),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  AppMotion.fadeSlideRoute(const RegisterScreen()),
                );
              },
              child: Text(
                "Sign Up",
                style: TextStyle(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
