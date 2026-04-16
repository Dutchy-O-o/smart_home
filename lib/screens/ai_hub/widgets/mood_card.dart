import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';
import '../../../constants/mood_palette.dart';

/// Small hero card showing the current mood emoji + label + confidence badge.
/// Falls back to a placeholder hint when no mood has been scanned.
class MoodCard extends StatelessWidget {
  const MoodCard({
    super.key,
    required this.mood,
    required this.confidence,
  });

  final String? mood;
  final double confidence;

  @override
  Widget build(BuildContext context) {
    if (mood == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          'Scan your face to read your mood',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSub(context), fontSize: 14),
        ),
      );
    }

    final color = MoodPalette.colorFor(mood);
    final emoji = MoodPalette.emojiFor(mood);
    final label = MoodPalette.label(mood!);
    final pct = (confidence * 100).toInt();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Confidence',
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '%$pct',
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
