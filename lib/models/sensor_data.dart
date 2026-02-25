import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class SensorCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color iconColor;
  final String status;
  final Color statusColor;

  const SensorCard({
    super.key,
    required this.title,
    required this.value,
    this.unit = "",
    required this.icon,
    required this.iconColor,
    this.status = "",
    this.statusColor = Colors.transparent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Üst: İkon
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: iconColor, size: 28),
              if (status.isNotEmpty)
                Icon(Icons.circle, size: 8, color: statusColor),
            ],
          ),
          
          // Buraya Spacer koyuyoruz ki başlık ve değeri alta itsin
          const Spacer(),
          
          // Orta: Başlık (Taşarsa "..." koysun)
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 14,
            ),
          ),
          
          const SizedBox(height: 4),
          
          // Alt: Değer ve Durum (FittedBox ile sığdırıyoruz)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (unit.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 2),
                    child: Text(
                      unit,
                      style: const TextStyle(color: AppColors.textGrey, fontSize: 14),
                    ),
                  ),
              ],
            ),
          ),
          
          if (status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                status,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}