import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Single combined card that shows Temperature and Humidity with progress
/// indicators, replacing the two side-by-side SensorCard tiles. Designed for
/// quick at-a-glance reading on the dashboard.
class TempHumidityCard extends StatelessWidget {
  const TempHumidityCard({
    super.key,
    required this.temperature,
    required this.humidity,
  });

  /// Raw string values straight from the API (e.g. "23.5" or "--").
  final String temperature;
  final String humidity;

  @override
  Widget build(BuildContext context) {
    final tempNum = double.tryParse(temperature);
    final humNum = double.tryParse(humidity);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderCol(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sensors,
                  color: AppColors.textSub(context), size: 18),
              const SizedBox(width: 8),
              Text(
                'Climate',
                style: TextStyle(
                  color: AppColors.text(context),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MetricRow(
            icon: Icons.thermostat,
            iconColor: AppColors.accentOrange,
            label: 'Temperature',
            value: temperature,
            unit: '°C',
            progress: tempNum == null
                ? null
                : ((tempNum - 0) / 50).clamp(0.0, 1.0),
            progressColor: _tempColor(tempNum),
            range: '0–50°C',
          ),
          const SizedBox(height: 14),
          _MetricRow(
            icon: Icons.water_drop,
            iconColor: AppColors.primaryBlue,
            label: 'Humidity',
            value: humidity,
            unit: '%',
            progress:
                humNum == null ? null : (humNum / 100).clamp(0.0, 1.0),
            progressColor: AppColors.primaryBlue,
            range: '0–100%',
          ),
        ],
      ),
    );
  }

  Color _tempColor(double? t) {
    if (t == null) return AppColors.accentOrange;
    if (t < 18) return AppColors.primaryBlue;
    if (t > 28) return Colors.redAccent;
    return AppColors.accentOrange;
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.unit,
    required this.progress,
    required this.progressColor,
    required this.range,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String unit;
  final double? progress;
  final Color progressColor;
  final String range;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: AppColors.textSub(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          color: AppColors.text(context),
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          unit,
                          style: TextStyle(
                            color: AppColors.textSub(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppColors.borderCol(context),
                  valueColor: AlwaysStoppedAnimation(progressColor),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                range,
                style: TextStyle(
                  color: AppColors.textSub(context).withValues(alpha: 0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
