import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../constants/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../widgets/aurora_background.dart';

/// Shared scaffold for the auth flow. Renders an aurora gradient backdrop,
/// optional back button, and a centered scrolling content slot — so every
/// auth screen has the same premium look without each one re-inventing
/// padding, gradients, and headers.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.children,
    this.showBack = false,
    this.title,
  });

  final List<Widget> children;
  final bool showBack;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      extendBodyBehindAppBar: true,
      appBar: showBack
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: AppColors.text(context)),
                onPressed: () => Navigator.pop(context),
              ),
              title: title == null
                  ? null
                  : Text(
                      title!,
                      style: TextStyle(
                        color: AppColors.text(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
              centerTitle: true,
            )
          : null,
      body: Stack(
        children: [
          const Positioned.fill(child: AuroraBackground(intensity: 0.85)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl,
                vertical: AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children
                    .animate(interval: 60.ms)
                    .fadeIn(duration: 400.ms, curve: Curves.easeOutCubic)
                    .slideY(begin: 0.06, end: 0, duration: 400.ms),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Branded logo chip — gradient circle with a glowing inner icon.
/// Used at the top of login / forgot-password / reset-confirmation as a
/// visual anchor that pairs with the dashboard hero.
class AuthBrandLogo extends StatelessWidget {
  const AuthBrandLogo({
    super.key,
    this.icon = Icons.home_rounded,
    this.size = 88,
  });

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
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
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: AppColors.teal.withValues(alpha: 0.30),
              blurRadius: 36,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.45),
      ),
    );
  }
}

/// Polished input field used across auth screens. Filled card surface with
/// a focus ring that lights up in brand blue.
class AuthInput extends StatefulWidget {
  const AuthInput({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.icon,
    this.obscure = false,
    this.suffix,
    this.onChanged,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData? icon;
  final bool obscure;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  @override
  State<AuthInput> createState() => _AuthInputState();
}

class _AuthInputState extends State<AuthInput> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = AppColors.card(context);
    final border = _focused
        ? AppColors.primaryBlue
        : AppColors.borderCol(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            widget.label,
            style: TextStyle(
              color: AppColors.text(context),
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.1,
            ),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: border.withValues(alpha: _focused ? 0.9 : 0.4),
              width: _focused ? 1.5 : 1,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            obscureText: widget.obscure,
            keyboardType: widget.keyboardType,
            onChanged: widget.onChanged,
            style: TextStyle(color: AppColors.text(context), fontSize: 15),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(
                color: AppColors.textSub(context).withValues(alpha: 0.7),
                fontSize: 14,
              ),
              prefixIcon: widget.icon == null
                  ? null
                  : Icon(widget.icon,
                      color: _focused
                          ? AppColors.primaryBlue
                          : AppColors.textSub(context),
                      size: 20),
              suffixIcon: widget.suffix,
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Primary CTA — pill-shaped, brand-gradient, with a soft glow. Falls back
/// to a subdued state when [enabled] is false.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isOn = enabled && !loading;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: isOn ? 1.0 : 0.55,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.brandGradient,
            ),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: isOn
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.45),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: AppColors.teal.withValues(alpha: 0.30),
                      blurRadius: 24,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              onTap: isOn ? onPressed : null,
              splashColor: Colors.white.withValues(alpha: 0.18),
              child: Center(
                child: loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
