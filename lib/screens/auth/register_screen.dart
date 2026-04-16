import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
// import '../dashboard/dashboard_screen.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import 'otp_verification_screen.dart';
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

    // Kriter 1: Uzunluk en az 8 karakter mi? (+0.25 Puan)
    if (value.length >= 8) score += 0.25;

    if (value.contains(RegExp(r'[A-Z]'))) score += 0.25;

    if (value.contains(RegExp(r'[0-9]'))) score += 0.25;

    if (value.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'))) score += 0.25;

    setState(() {
      _passwordStrength = score; 
    });
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
          MaterialPageRoute(builder: (context) => OtpVerificationScreen(email: email)),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        String message = e.message;
        if (e.message.toLowerCase().contains("password did not conform")) {
          message = "Password must be at least 8 characters and contain a special character (e.g. !@#\$%).";
        } else if (e.message.toLowerCase().contains("already exists")) {
          message = "An account with this email already exists.";
        }
        _showError(message);
      }
    } catch (e) {
      if (mounted) {
        _showError("Registration failed: \${e.toString()}");
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.accentRed),
    );
  }

  // --- 3. Yasal Metin Penceresi (MODAL BOTTOM SHEET) ---
  void _showLegalInfo(String title, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 20),
                width: 50,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                child: Text(
                  content,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),
            ),
            // Kapat Butonu
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text("I Understand", style: TextStyle(color: Colors.white)),
                ),
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
            : (_passwordStrength <= 0.75 ? Colors.yellow : AppColors.accentGreen));

    String strengthText = _passwordStrength <= 0.25 
        ? "Weak" 
        : (_passwordStrength <= 0.50 
            ? "Fair" 
            : (_passwordStrength <= 0.75 ? "Good" : "Strong"));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Sign Up", style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER
              const Text(
                "Create your Sanctuary",
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Connect to your secure smart home network.",
                style: TextStyle(color: AppColors.textGrey, fontSize: 14),
              ),
              const SizedBox(height: 32),

              // FORM ALANLARI
              _buildLabel("Full Name"),
              _buildInput(_fullNameController, "e.g., Alex Chen", Icons.person_outline),
              
              const SizedBox(height: 16),
              
              _buildLabel("Email Address"),
              _buildInput(_emailController, "alex@example.com", Icons.email_outlined),

              const SizedBox(height: 16),
              
              _buildLabel("Password"),
              TextField(
                controller: _passwordController,
                obscureText: _isObscured,
                onChanged: _checkPasswordStrength,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.cardDark,
                  hintText: "••••••••",
                  hintStyle: const TextStyle(color: Colors.grey),
                  suffixIcon: IconButton(
                    icon: Icon(_isObscured ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                    onPressed: () => setState(() => _isObscured = !_isObscured),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              
              LinearProgressIndicator(
                value: _passwordStrength,
                backgroundColor: Colors.grey[800],
                color: strengthColor,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 4),
              Text(
                strengthText,
                style: TextStyle(color: strengthColor, fontSize: 12),
              ),

              const SizedBox(height: 16),

              _buildLabel("Confirm Password"),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.cardDark,
                  hintText: "••••••••",
                  hintStyle: const TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // LEGAL & ONAY (Checkbox ve Linkler)
              Row(
                children: [
                  Checkbox(
                    value: _agreedToTerms,
                    activeColor: AppColors.primaryBlue,
                    checkColor: Colors.white,
                    side: const BorderSide(color: Colors.grey),
                    onChanged: (value) {
                      setState(() {
                        _agreedToTerms = value ?? false;
                      });
                    },
                  ),
                  Expanded(
                    child: Wrap(
                      children: [
                        const Text("I agree to the ", style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                        // Terms Linki
                        GestureDetector(
                          onTap: () {
                            _showLegalInfo("Terms of Service", 
                              "1. Usage\nBy using this app, you agree to monitor your sensors responsibly.\n\n"
                              "2. Liability\nWe are not responsible for missed alerts due to network failure.\n\n"
                              "3. Hardware\nYou agree not to reverse engineer the provided Raspberry Pi kit."
                            );
                          },
                          child: const Text("Terms of Service", style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        const Text(" and ", style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                        // Privacy Linki
                        GestureDetector(
                          onTap: () {
                             _showLegalInfo("Privacy Policy", 
                              "1. Data Collection\nWe collect sensor data to provide insights.\n\n"
                              "2. Storage\nYour data is encrypted end-to-end.\n\n"
                              "3. Sharing\nWe do not share your personal data with third parties."
                            );
                          },
                          child: const Text("Privacy Policy", style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        const Text(".", style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (_agreedToTerms && !isLoading) ? _handleRegister : null,

                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    disabledBackgroundColor: AppColors.primaryBlue.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isLoading)
                        const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      else ...[
                        Text(
                          "Initialize System",
                          style: TextStyle(
                            color: _agreedToTerms ? Colors.white : Colors.white54,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward, color: _agreedToTerms ? Colors.white : Colors.white54),
                      ]
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // ALT LINK (Login)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Already have an account? ", style: TextStyle(color: AppColors.textGrey)),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      "Log In",
                      style: TextStyle(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildInput(TextEditingController controller, String hint, [IconData? suffixIcon]) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.cardDark,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        suffixIcon: suffixIcon != null ? Icon(suffixIcon, color: Colors.grey) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}