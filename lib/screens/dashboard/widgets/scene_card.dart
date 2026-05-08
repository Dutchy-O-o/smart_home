import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

/// Larger, gradient-tinted scene card used in the dashboard's 2×2 Quick
/// Access grid. Replaces the cramped circular [QuickAccessButton] row.
///
/// Visual idiom: rounded rectangle with a soft tint of [accent] and a
/// glowing icon chip in the top-left. Tap area covers the full card.
class SceneCard extends StatelessWidget {
  const SceneCard({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.accent,
    required this.onTap,
    this.loading = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String description;
  final Color accent;
  final VoidCallback? onTap;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final dim = !enabled && !loading;
    final card = AppColors.card(context);

    return Opacity(
      opacity: dim ? 0.45 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (enabled && !loading) ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          splashColor: accent.withValues(alpha: 0.15),
          highlightColor: accent.withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  card,
                  Color.alphaBlend(
                    accent.withValues(alpha: 0.10),
                    card,
                  ),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: accent.withValues(alpha: 0.35),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accent,
                        Color.alphaBlend(
                          Colors.white.withValues(alpha: 0.18),
                          accent,
                        ),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.45),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: loading
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white),
                          ),
                        )
                      : Icon(icon, color: Colors.white, size: 22),
                ),
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
    );
  }
}
