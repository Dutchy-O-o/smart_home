import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';
import '../../../constants/mood_palette.dart';

/// Bottom sheet that lets the user pick a mood manually — bypasses the scanner
/// and directly invokes [onPicked] with the chosen mood string.
Future<void> showMoodPickerSheet({
  required BuildContext context,
  required ValueChanged<String> onPicked,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _MoodPickerSheet(onPicked: onPicked),
  );
}

class _MoodPickerSheet extends StatelessWidget {
  const _MoodPickerSheet({required this.onPicked});

  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSub(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Pick your mood',
              style: TextStyle(
                color: AppColors.text(context),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Set mood directly without scanning',
              style: TextStyle(color: AppColors.textSub(context), fontSize: 12),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: MoodPalette.pickable.map((mood) {
                final emoji = MoodPalette.emojiFor(mood);
                final color = MoodPalette.colorFor(mood);
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    onPicked(mood);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: color.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 22)),
                        const SizedBox(width: 8),
                        Text(
                          MoodPalette.label(mood),
                          style: TextStyle(
                            color: AppColors.text(context),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
