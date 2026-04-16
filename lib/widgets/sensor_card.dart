import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Theme-aware sensor summary card used on the dashboard.
class SensorCard extends StatelessWidget {
  const SensorCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.cardColor,
    this.unit,
    this.iconColor,
    this.status,
    this.statusColor,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color? cardColor;
  final String? unit;
  final Color? iconColor;
  final String? status;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor ?? AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderCol(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: iconColor ?? AppColors.primaryBlue),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: AppColors.text(context),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (unit != null)
                  Text(
                    unit!,
                    style: TextStyle(
                      color: AppColors.textSub(context),
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
            if (status != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor?.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: statusColor ?? AppColors.accentGreen,
                  ),
                ),
                child: Text(
                  status!,
                  style: TextStyle(
                    color: statusColor ?? AppColors.accentGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
