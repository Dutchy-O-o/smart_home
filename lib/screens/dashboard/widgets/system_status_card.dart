import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';
import '../../../theme/app_spacing.dart';

/// "System Online" banner shown near the top of the dashboard.
class SystemStatusCard extends StatelessWidget {
  const SystemStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'System status: online',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: AppRadius.brXl,
          border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.sentiment_satisfied_alt,
                color: AppColors.primaryBlue, size: 36),
            AppSpacing.hGapLg,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'System Online',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.primaryBlue,
                        ),
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    'The house feels cozy and secure. No anomalies detected in the last hour.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
