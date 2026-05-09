import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/sensor_history_service.dart';
import '../theme/app_spacing.dart';

/// Single combined card that shows Temperature and Humidity with progress
/// indicators, replacing the two side-by-side SensorCard tiles. Designed for
/// quick at-a-glance reading on the dashboard.
class TempHumidityCard extends StatelessWidget {
  const TempHumidityCard({
    super.key,
    required this.temperature,
    required this.humidity,
    this.history = const [],
  });

  /// Raw string values straight from the API (e.g. "23.5" or "--").
  final String temperature;
  final String humidity;

  /// Last ~24h of readings, oldest first. Empty list shows a "collecting…"
  /// placeholder under the metric. Each metric line is rendered with the
  /// values from this same list (one shared timeline keeps temp/humidity
  /// aligned).
  final List<SensorReading> history;

  @override
  Widget build(BuildContext context) {
    final tempNum = double.tryParse(temperature);
    final humNum = double.tryParse(humidity);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: AppRadius.brLg,
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
              AppSpacing.hGapSm,
              Text(
                'Climate',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          AppSpacing.vGapLg,
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
            sparklinePoints: history
                .where((r) => r.temperature != null)
                .map((r) => r.temperature!)
                .toList(),
            sparklineColor: _tempColor(tempNum),
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
            sparklinePoints: history
                .where((r) => r.humidity != null)
                .map((r) => r.humidity!)
                .toList(),
            sparklineColor: AppColors.primaryBlue,
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
    this.sparklinePoints = const [],
    this.sparklineColor,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String unit;
  final double? progress;
  final Color progressColor;
  final String range;
  final List<double> sparklinePoints;
  final Color? sparklineColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: AppRadius.brSm,
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
              const SizedBox(height: 6),
              SizedBox(
                height: 28,
                child: sparklinePoints.length < 2
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          sparklinePoints.isEmpty
                              ? '$range · collecting trend…'
                              : range,
                          style: TextStyle(
                            color: AppColors.textSub(context)
                                .withValues(alpha: 0.7),
                            fontSize: 10,
                          ),
                        ),
                      )
                    : _Sparkline(
                        points: sparklinePoints,
                        color: sparklineColor ?? progressColor,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tiny line chart used by [_MetricRow] to show the recent trend.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (int i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i]),
    ];
    final minY = points.reduce((a, b) => a < b ? a : b);
    final maxY = points.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY).abs() * 0.15).clamp(0.5, 5.0);

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.25),
                  color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
