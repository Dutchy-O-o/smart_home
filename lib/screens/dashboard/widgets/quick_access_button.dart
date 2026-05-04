import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

/// Circular quick-access button used in the dashboard's action row.
/// When [highlighted] is true the fill uses [highlightColor] (or primary blue
/// when not provided); otherwise it uses the theme's card color.
/// Pass [loading] to swap the icon for a spinner while the action is running,
/// and [enabled] to dim/disable the button during another running action.
class QuickAccessButton extends StatelessWidget {
  const QuickAccessButton({
    super.key,
    required this.icon,
    required this.label,
    this.description,
    this.highlighted = false,
    this.iconColor = Colors.white,
    this.highlightColor,
    this.onTap,
    this.loading = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String? description;
  final bool highlighted;
  final Color iconColor;
  final Color? highlightColor;
  final VoidCallback? onTap;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final fill = highlighted
        ? (highlightColor ?? AppColors.primaryBlue)
        : AppColors.card(context);
    final dim = !enabled && !loading;

    return Opacity(
      opacity: dim ? 0.4 : 1.0,
      child: GestureDetector(
        onTap: (enabled && !loading) ? onTap : null,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: highlighted
                          ? fill.withValues(alpha: 0.4)
                          : Colors.black.withValues(alpha: 0.2),
                      blurRadius: highlighted ? 14 : 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(18),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                        ),
                      )
                    : Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.text(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 2),
                Text(
                  description!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSub(context).withValues(alpha: 0.85),
                    fontSize: 10,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
