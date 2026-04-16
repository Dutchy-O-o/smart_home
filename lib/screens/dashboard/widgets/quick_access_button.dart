import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

/// Circular quick-access button used in the dashboard's action row.
/// When [highlighted] is true the fill uses the primary color; otherwise
/// it uses the theme's card color.
class QuickAccessButton extends StatelessWidget {
  const QuickAccessButton({
    super.key,
    required this.icon,
    required this.label,
    this.highlighted = false,
    this.iconColor = Colors.white,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool highlighted;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: highlighted
                  ? AppColors.primaryBlue
                  : AppColors.card(context),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSub(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
