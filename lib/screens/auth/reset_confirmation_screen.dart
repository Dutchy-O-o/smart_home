import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import 'login_screen.dart';

class ResetConfirmationScreen extends StatelessWidget {
  const ResetConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // AppBar yok çünkü görselde temiz bir ekran var, sadece geri dönmek isterse diye sistem geri tuşu çalışır.
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // 1. ÖZEL İKON YAPISI (Zarf + Yeşil Tik)
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  // Ana Daire ve Zarf
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8DAE98), // Görseldeki pastel yeşilimsi ton
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.mail_outline, // Zarf ikonu
                      size: 60,
                      color: Color(0xFFD6A042), // Zarfın sarımsı rengi
                    ),
                  ),
                  // Yeşil Tik (Badge)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.background, // Arka plan rengiyle sınır çizmek için
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: AppColors.accentGreen, // Parlak yeşil
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // 2. BAŞLIK VE AÇIKLAMA
              const Text(
                "Check your mail",
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "We have sent password recovery instructions to your email. Please check your inbox and spam folder.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 40),

              // 3. BUTON (Return to Login)
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    // Kullanıcıyı Login ekranına geri gönder ve tüm geçmişi temizle
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 5,
                    shadowColor: AppColors.primaryBlue.withOpacity(0.4),
                  ),
                  child: const Text(
                    "Return to Login",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 3),

              // 4. ALT METİN (Resend Email)
              Column(
                children: [
                  const Text("Did not receive the email?", style: TextStyle(color: AppColors.textGrey)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Email resent successfully!")),
                      );
                    },
                    child: const Text(
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
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}