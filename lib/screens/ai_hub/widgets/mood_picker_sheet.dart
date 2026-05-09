import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';
import '../../../constants/mood_palette.dart';
import '../../../theme/app_spacing.dart';

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
      borderRadius: BorderRadius.vertical(top: AppRadius.rLg),
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
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xxl),
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
            AppSpacing.vGapLg,
            Text(
              'Pick your mood',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            AppSpacing.vGapXs,
            Text(
              'Set mood directly without scanning',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            AppSpacing.vGapLg,
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: MoodPalette.pickable.map((mood) {
                final emoji = MoodPalette.emojiFor(mood);
                final color = MoodPalette.colorFor(mood);
                return Semantics(
                  button: true,
                  label: MoodPalette.label(mood),
                  child: GestureDetector(
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
                        color: color.withValues(alpha: 0.15),
                        borderRadius: AppRadius.brSm,
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 22)),
                          AppSpacing.hGapSm,
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
