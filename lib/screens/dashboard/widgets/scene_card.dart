import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../constants/app_colors.dart';
import '../../../theme/app_spacing.dart';

/// Larger, gradient-tinted scene card used in the dashboard's 2×2 Quick
/// Access grid. Replaces the cramped circular [QuickAccessButton] row.
///
/// Visual idiom: rounded rectangle with a soft tint of [accent] and a
/// glowing icon chip in the top-left. While running, the icon chip
/// pulses to confirm an in-flight action. Tap area covers the full card.
class SceneCard extends StatelessWidget {
  const SceneCard({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.accent,
    required this.onTap,
    this.onLongPress,
    this.loading = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String description;
  final Color accent;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final dim = !enabled && !loading;
    final card = AppColors.card(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final iconChip = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent,
            Color.alphaBlend(
              Colors.white.withValues(alpha: 0.22),
              accent,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.55),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(11),
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Icon(icon, color: Colors.white, size: 22),
    );

    return Semantics(
      button: true,
      enabled: enabled && !loading,
      label: label,
      hint: description,
      child: Opacity(
      opacity: dim ? 0.45 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (enabled && !loading)
              ? () {
                  HapticFeedback.lightImpact();
                  onTap?.call();
                }
              : null,
          onLongPress: (enabled && onLongPress != null)
              ? () {
                  HapticFeedback.mediumImpact();
                  onLongPress!();
                }
              : null,
          borderRadius: AppRadius.brLg,
          splashColor: accent.withValues(alpha: 0.18),
          highlightColor: accent.withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  card,
                  Color.alphaBlend(
                    accent.withValues(alpha: isDark ? 0.16 : 0.10),
                    card,
                  ),
                ],
              ),
              borderRadius: AppRadius.brLg,
              border: Border.all(
                color: accent.withValues(alpha: loading ? 0.6 : 0.32),
                width: loading ? 1.4 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: loading ? 0.32 : 0.18),
                  blurRadius: loading ? 22 : 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                loading
                    ? iconChip
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scale(
                          begin: const Offset(1, 1),
                          end: const Offset(1.08, 1.08),
                          duration: 900.ms,
                          curve: Curves.easeInOut,
                        )
                    : iconChip,
                const SizedBox(height: 14),
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}
