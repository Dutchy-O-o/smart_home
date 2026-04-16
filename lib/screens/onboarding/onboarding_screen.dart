import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../auth/login_screen.dart';

// This is the introductory (Onboarding) screen of the app.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  // Content displayed on screens (Using Icons instead of Images)
  final List<OnboardingContent> _contents = [
    OnboardingContent(
      title: "Safety First, Always.",
      description: "Your home is smarter than ever. Using advanced vibration and gas sensors, we detect earthquakes and leaks instantly.",
      icon: Icons.shield_outlined,
    ),
    OnboardingContent(
      title: "AI Emotion Hub",
      description: "The system learns from you. Whether you're stressed or celebrating, your hub adjusts the lighting, music, and temperature to match your vibe perfectly.",
      icon: Icons.favorite_border,
    ),
    OnboardingContent(
      title: "Complete Control",
      description: "Seamlessly manage your lights, curtains, and climate. Powered by Raspberry Pi for instant, secure response.",
      icon: Icons.touch_app_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () => _navigateToLogin(),
            child: const Text(
              "Skip",
              style: TextStyle(color: AppColors.textGrey),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemCount: _contents.length,
                itemBuilder: (context, index) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        height: 220,
                        width: 220,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1E2746),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryBlue.withValues(alpha: 0.2),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: Icon(
                          _contents[index].icon,
                          size: 100,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      _contents[_currentIndex].title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textWhite,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _contents[_currentIndex].description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textGrey,
                        height: 1.5,
                      ),
                    ),
                    const Spacer(),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _contents.length,
                        (index) => buildDot(index),
                      ),
                    ),
                    const SizedBox(height: 30),

                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () {
                          if (_currentIndex == _contents.length - 1) {
                            _navigateToLogin();
                          } else {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 10,
                          shadowColor: AppColors.primaryBlue.withValues(alpha: 0.4),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _currentIndex == _contents.length - 1
                                  ? "Get Started"
                                  : "Next",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (_currentIndex != _contents.length - 1) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward, color: Colors.white),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildDot(int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(right: 6),
      height: 8,
      width: _currentIndex == index ? 24 : 8,
      decoration: BoxDecoration(
        color: _currentIndex == index ? AppColors.primaryBlue : Colors.grey.shade700,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  void _navigateToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }
}

class OnboardingContent {
  final String title;
  final String description;
  final IconData icon;

  OnboardingContent({
    required this.title,
    required this.description,
    required this.icon,
  });
}