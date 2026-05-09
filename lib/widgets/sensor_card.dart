import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../theme/app_spacing.dart';

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
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$title: $value${unit ?? ''}${status == null ? '' : ', $status'}',
      child: Container(
        decoration: BoxDecoration(
          color: cardColor ?? AppColors.card(context),
          borderRadius: AppRadius.brMd,
          border: Border.all(color: AppColors.borderCol(context)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: iconColor ?? AppColors.primaryBlue),
              AppSpacing.vGapSm,
              Text(
                title,
                style: theme.textTheme.titleMedium,
              ),
              AppSpacing.vGapXs,
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: AppColors.textSub(context),
                    ),
                  ),
                  if (unit != null)
                    Text(
                      unit!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSub(context),
                      ),
                    ),
                ],
              ),
              if (status != null)
                Container(
                  margin: const EdgeInsets.only(top: AppSpacing.sm),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor?.withValues(alpha: 0.1),
                    borderRadius: AppRadius.brSm,
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
      ),
    );
  }
}
