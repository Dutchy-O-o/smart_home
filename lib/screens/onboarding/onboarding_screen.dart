import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../constants/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/aurora_background.dart';
import '../auth/login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  // Each page picks an accent color so the gradient illustration ring
  // shifts as you swipe — gives the impression of a guided tour rather
  // than a static carousel.
  final List<_OnboardingContent> _contents = [
    _OnboardingContent(
      title: "Safety First, Always.",
      description:
          "Your home is smarter than ever. Vibration and gas sensors detect earthquakes and leaks instantly.",
      icon: Icons.shield_rounded,
      accent: AppColors.accentGreen,
      accent2: AppColors.teal,
    ),
    _OnboardingContent(
      title: "AI Emotion Hub",
      description:
          "The system learns from you — your hub adjusts lighting, music, and temperature to match your vibe.",
      icon: Icons.favorite_rounded,
      accent: AppColors.accentPink,
      accent2: AppColors.primaryViolet,
    ),
    _OnboardingContent(
      title: "Complete Control",
      description:
          "Manage lights, TV, and climate seamlessly — powered by Raspberry Pi for instant, secure response.",
      icon: Icons.touch_app_rounded,
      accent: AppColors.primaryBlue,
      accent2: AppColors.primaryViolet,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _contents[_currentIndex];
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _navigateToLogin,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSub(context),
            ),
            child: const Text(
              "Skip",
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Aurora intensity slightly tinted toward the current page accent
          // so the backdrop subtly travels with the carousel.
          Positioned.fill(
            child: AuroraBackground(
              intensity: 0.85,
              colors: [c.accent, c.accent2, AppColors.primaryBlue],
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  flex: 3,
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() => _currentIndex = index);
                    },
                    itemCount: _contents.length,
                    itemBuilder: (context, index) {
                      final page = _contents[index];
                      return Center(
                        child: _IllustrationOrb(content: page),
                      );
                    },
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Column(
                      children: [
                        AppSpacing.vGapXl,
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 320),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.08),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: Column(
                            key: ValueKey(_currentIndex),
                            children: [
                              Text(
                                c.title,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .displayLarge
                                    ?.copyWith(fontSize: 26),
                              ),
                              AppSpacing.vGapLg,
                              Text(
                                c.description,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSub(context),
                                  height: 1.55,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _contents.length,
                            (index) => _buildDot(index),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _NextButton(
                          isLast: _currentIndex == _contents.length - 1,
                          onTap: () {
                            if (_currentIndex == _contents.length - 1) {
                              _navigateToLogin();
                            } else {
                              _pageController.nextPage(
                                duration: AppMotion.slow,
                                curve: AppMotion.standard,
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    final active = _currentIndex == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(right: 6),
      height: 8,
      width: active ? 28 : 8,
      decoration: BoxDecoration(
        gradient: active
            ? const LinearGradient(colors: AppColors.brandGradient)
            : null,
        color: active
            ? null
            : AppColors.textSub(context).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(4),
        boxShadow: active
            ? [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.45),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
    );
  }

  void _navigateToLogin() {
    Navigator.pushReplacement(
      context,
      AppMotion.fadeSlideRoute(const LoginScreen()),
    );
  }
}

/// Round illustration orb — gradient ring + glow + icon. Animates in on
/// page change so swiping feels like the orb itself is reshaping.
class _IllustrationOrb extends StatelessWidget {
  const _IllustrationOrb({required this.content});

  final _OnboardingContent content;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft outer halo
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  content.accent.withValues(alpha: 0.35),
                  content.accent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          // Gradient ring
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [content.accent, content.accent2],
              ),
              boxShadow: [
                BoxShadow(
                  color: content.accent.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
          ),
          // Inner card that holds the icon — gives the orb depth instead
          // of a flat gradient circle.
          Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bg(context),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.10),
                width: 1.2,
              ),
            ),
            child: Icon(
              content.icon,
              size: 76,
              color: content.accent,
            ),
          ),
        ],
      ),
    )
        .animate(key: ValueKey(content.icon))
        .scale(
          begin: const Offset(0.92, 0.92),
          end: const Offset(1, 1),
          duration: 360.ms,
          curve: Curves.easeOutBack,
        )
        .fadeIn(duration: 280.ms);
  }
}

/// Pill-shaped next/get-started button with brand gradient.
class _NextButton extends StatelessWidget {
  const _NextButton({required this.isLast, required this.onTap});

  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.brandGradient,
          ),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withValues(alpha: 0.45),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: AppColors.teal.withValues(alpha: 0.30),
              blurRadius: 26,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isLast ? "Get Started" : "Next",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (!isLast) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 20),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingContent {
  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final Color accent2;

  _OnboardingContent({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.accent2,
  });
}
