import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import '../dashboard/dashboard_screen.dart';
import 'register_screen.dart'; // Kayıt ekranına gitmek için import ettik
import 'forgot_password_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';


import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // Form kontrolcüleri
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  bool _isObscured = true; // Şifre gizli mi?

  // Giriş yapma fonksiyonu
 // Giriş yapma fonksiyonu
  Future<void> _handleLogin() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    // Basit bir validasyon (Boş mu kontrolü)
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
      // 1. Riverpod üzerinden giriş işlemini tetikle
      final success = await ref.read(authProvider.notifier).signIn(
        email: email,
        password: password,
      );

      if (success && mounted) {
        // --- YENİ EKLENEN KISIM: TOKEN'I AL VE HAFIZAYA YAZ ---
        try {
          // Amplify'den mevcut aktif oturumu çekiyoruz
          final session = await Amplify.Auth.fetchAuthSession();
          
          // Eğer bu bir Cognito oturumuysa Token'ı içinden alıyoruz
          if (session is CognitoAuthSession) {
            // Bize API Gateway fedaisini geçmek için "ID Token" lazım
            final idToken = session.userPoolTokensResult.value.idToken.raw;
            
            // Telefonun hafızasına 'jwt_token' adıyla kazıyoruz
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('jwt_token', idToken);
            
            safePrint("Token başarıyla hafızaya kaydedildi! Token: ${idToken.substring(0, 10)}...");
          }
        } catch (tokenError) {
          safePrint("Oturum açıldı ama Token alınamadı: $tokenError");
        }
        // --------------------------------------------------------

        // 2. İşlem bitince kullanıcıyı ana sayfaya yönlendir
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
        );
      }
    } catch (e) {
      // log the real error
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              
              // 1. HEADER (LOGO & BAŞLIK)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white12),
                ),
                child: const Icon(Icons.home, size: 50, color: AppColors.textWhite),
              ),
              const SizedBox(height: 24),
              const Text(
                "Welcome Home",
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Securely access your emotional intelligence hub.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textGrey, fontSize: 14),
              ),
              const SizedBox(height: 48),

              // 2. FORM ALANLARI
              // Email Alanı
              _buildTextField(
                controller: _emailController,
                hintText: "user@example.com",
                icon: Icons.email_outlined,
                label: "Email or Username",
              ),
              const SizedBox(height: 20),

              // Şifre Alanı
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Password", style: TextStyle(color: AppColors.textWhite, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _passwordController,
                    obscureText: _isObscured,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.cardDark,
                      hintText: "••••••••",
                      hintStyle: const TextStyle(color: Colors.grey),
                      prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isObscured ? Icons.visibility_off : Icons.visibility,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _isObscured = !_isObscured;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30), // Yuvarlak kenarlar
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                  ),
                ],
              ),
              
              // Forgot Password Linki
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                   
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
                    );
                  },
                  child: const Text(
                    "Forgot Password?",
                    style: TextStyle(color: AppColors.primaryBlue),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 3. BUTON (Secure Login)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 5,
                    shadowColor: AppColors.primaryBlue.withOpacity(0.4),
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
                        const Icon(Icons.bolt, color: Colors.white),
                        const SizedBox(width: 8),
                        const Text(
                          "Secure Login",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 30),

              // Face ID (Görselde olduğu için ekledim - Opsiyonel)
              const Column(
                children: [
                  Icon(Icons.face, size: 40, color: Colors.grey),
                  SizedBox(height: 4),
                  Text("Face ID", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),

              const SizedBox(height: 30),

              // 4. ALT METİN (Sign Up)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? ", style: TextStyle(color: AppColors.textGrey)),
                  GestureDetector(
                    onTap: () {
                      // Register ekranına git
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RegisterScreen()),
                      );
                    },
                    child: const Text(
                      "Sign Up",
                      style: TextStyle(
                        color: AppColors.primaryBlue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Text Field Yardımcı Widget'ı (Kod tekrarını önlemek için)
  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required String label,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textWhite, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.cardDark,
            hintText: hintText,
            hintStyle: const TextStyle(color: Colors.grey),
            prefixIcon: Icon(icon, color: Colors.grey),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
          ),
        ),
      ],
    );
  }
}