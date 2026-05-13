import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import 'otp_verification_screen.dart';
import 'widgets/auth_scaffold.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isObscured = true;
  bool _agreedToTerms = false;
  double _passwordStrength = 0.0;

  void _checkPasswordStrength(String value) {
    double score = 0.0;
    if (value.isEmpty) {
      setState(() => _passwordStrength = 0.0);
      return;
    }
    if (value.length >= 8) score += 0.25;
    if (value.contains(RegExp(r'[A-Z]'))) score += 0.25;
    if (value.contains(RegExp(r'[0-9]'))) score += 0.25;
    if (value.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'))) score += 0.25;
    setState(() => _passwordStrength = score);
  }

  Future<void> _handleRegister() async {
    String fullName = _fullNameController.text.trim();
    String email = _emailController.text.trim();
    String password = _passwordController.text;
    String confirmPassword = _confirmPasswordController.text;

    if (fullName.isEmpty || email.isEmpty || password.isEmpty) {
      _showError("All fields are required.");
      return;
    }
    if (!email.contains('@')) {
      _showError("Invalid email format.");
      return;
    }
    if (password != confirmPassword) {
      _showError("Passwords do not match.");
      return;
    }
    if (!_agreedToTerms) {
      _showError("You must agree to the Terms of Service.");
      return;
    }

    try {
      final success = await ref.read(authProvider.notifier).signUp(
            email: email,
            password: password,
          );
      if (success && mounted) {
        Navigator.push(
          context,
          AppMotion.fadeSlideRoute(OtpVerificationScreen(email: email)),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        String message = e.message;
        if (e.message.toLowerCase().contains("password did not conform")) {
          message =
              "Password must be at least 8 characters and contain a special character (e.g. !@#\$%).";
        } else if (e.message.toLowerCase().contains("already exists")) {
          message = "An account with this email already exists.";
        }
        _showError(message);
      }
    } catch (e) {
      if (mounted) _showError("Registration failed: ${e.toString()}");
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.accentRed),
    );
  }

  void _showLegalInfo(String title, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: const BorderRadius.only(
            topLeft: AppRadius.rLg,
            topRight: AppRadius.rLg,
          ),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: AppSpacing.xl),
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.textSub(context).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Text(
              title,
              style: TextStyle(
                color: AppColors.text(context),
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            AppSpacing.vGapLg,
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl, vertical: 10),
                child: Text(
                  content,
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: AuthPrimaryButton(
                label: "I Understand",
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState == AuthState.loading;

    Color strengthColor = _passwordStrength <= 0.25
        ? AppColors.accentRed
        : (_passwordStrength <= 0.50
            ? AppColors.accentOrange
            : (_passwordStrength <= 0.75
                ? AppColors.accentAmber
                : AppColors.accentGreen));

    String strengthText = _passwordStrength <= 0.25
        ? "Weak"
        : (_passwordStrength <= 0.50
            ? "Fair"
            : (_passwordStrength <= 0.75 ? "Good" : "Strong"));

    return AuthScaffold(
      showBack: true,
      title: "Sign Up",
      children: [
        const SizedBox(height: 8),
        Text(
          "Create your\nSanctuary",
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
                height: 1.05,
              ),
        ),
        AppSpacing.vGapSm,
        Text(
          "Connect to your secure smart home network.",
          style: TextStyle(color: AppColors.textSub(context), fontSize: 14),
        ),
        const SizedBox(height: 28),
        AuthInput(
          controller: _fullNameController,
          label: "Full Name",
          hint: "e.g., Alex Chen",
          icon: Icons.person_outline_rounded,
        ),
        AppSpacing.vGapLg,
        AuthInput(
          controller: _emailController,
          label: "Email Address",
          hint: "alex@example.com",
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        AppSpacing.vGapLg,
        AuthInput(
          controller: _passwordController,
          label: "Password",
          hint: "••••••••",
          icon: Icons.lock_outline_rounded,
          obscure: _isObscured,
          onChanged: _checkPasswordStrength,
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
        AppSpacing.vGapSm,
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _passwordStrength),
            duration: const Duration(milliseconds: 300),
            builder: (context, val, _) => LinearProgressIndicator(
              value: val,
              backgroundColor: AppColors.borderCol(context),
              color: strengthColor,
              minHeight: 5,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          strengthText,
          style: TextStyle(
            color: strengthColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        AppSpacing.vGapLg,
        AuthInput(
          controller: _confirmPasswordController,
          label: "Confirm Password",
          hint: "••••••••",
          icon: Icons.lock_outline_rounded,
          obscure: true,
        ),
        AppSpacing.vGapXxl,
        Row(
          children: [
            Checkbox(
              value: _agreedToTerms,
              activeColor: AppColors.primaryBlue,
              checkColor: Colors.white,
              side: BorderSide(
                color: AppColors.textSub(context).withValues(alpha: 0.5),
              ),
              onChanged: (value) =>
                  setState(() => _agreedToTerms = value ?? false),
            ),
            Expanded(
              child: Wrap(
                children: [
                  Text("I agree to the ",
                      style: TextStyle(
                          color: AppColors.textSub(context), fontSize: 13)),
                  GestureDetector(
                    onTap: () => _showLegalInfo(
                      "Terms of Service",
                      "1. Usage\nBy using this app, you agree to monitor your sensors responsibly.\n\n"
                      "2. Liability\nWe are not responsible for missed alerts due to network failure.\n\n"
                      "3. Hardware\nYou agree not to reverse engineer the provided Raspberry Pi kit.",
                    ),
                    child: Text("Terms of Service",
                        style: TextStyle(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                  Text(" and ",
                      style: TextStyle(
                          color: AppColors.textSub(context), fontSize: 13)),
                  GestureDetector(
                    onTap: () => _showLegalInfo(
                      "Privacy Policy",
                      "1. Data Collection\nWe collect sensor data to provide insights.\n\n"
                      "2. Storage\nYour data is encrypted end-to-end.\n\n"
                      "3. Sharing\nWe do not share your personal data with third parties.",
                    ),
                    child: Text("Privacy Policy",
                        style: TextStyle(
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ),
                  Text(".",
                      style: TextStyle(
                          color: AppColors.textSub(context), fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
        AppSpacing.vGapXxl,
        AuthPrimaryButton(
          label: "Initialize System",
          icon: Icons.arrow_forward_rounded,
          loading: isLoading,
          enabled: _agreedToTerms,
          onPressed: _handleRegister,
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Already have an account? ",
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
        const SizedBox(height: 24),
      ],
    );
  }
}
