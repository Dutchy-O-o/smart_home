import 'dart:ui';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../theme/app_spacing.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? glowColor;
  final double opacity;
  final VoidCallback? onTap;
  final double blur;
  final String? semanticsLabel;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = AppRadius.xl,
    this.glowColor,
    this.opacity = 0.06,
    this.onTap,
    this.blur = 12,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glow = glowColor ?? AppColors.teal;
    final radius = BorderRadius.circular(borderRadius);

    Widget card = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: glow.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              splashColor: glow.withValues(alpha: 0.1),
              highlightColor: glow.withValues(alpha: 0.05),
              child: Container(
                padding: padding ?? const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: opacity),
                  border: Border.all(
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                    width: 1,
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      (isDark ? Colors.white : Colors.black).withValues(alpha: opacity + 0.02),
                      (isDark ? Colors.white : Colors.black).withValues(alpha: opacity - 0.02),
                    ],
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );

    if (semanticsLabel != null || onTap != null) {
      card = Semantics(
        button: onTap != null,
        label: semanticsLabel,
        child: card,
      );
    }
    return card;
  }
}
