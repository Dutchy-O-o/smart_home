import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';
import '../../../constants/mood_palette.dart';

/// Placeholder tiles for upcoming AWS-driven ambient control (lights, TV).
/// Visually inactive; shows mood-suggested settings once a mood is set.
class AmbientSection extends StatelessWidget {
  const AmbientSection({super.key, required this.mood});

  final String? mood;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          const SizedBox(height: 6),
          Text(
            'Lights and TV will adjust to your mood.',
            style: TextStyle(color: AppColors.textSub(context), fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _AmbientTile(
                  icon: Icons.lightbulb_outline,
                  title: 'Light',
                  status: mood == null
                      ? 'Pending'
                      : 'Tone: ${_hexOf(MoodPalette.colorFor(mood))}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AmbientTile(
                  icon: Icons.tv_outlined,
                  title: 'TV',
                  status:
                      mood == null ? 'Pending' : _suggestTvState(mood!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.auto_awesome, color: AppColors.textSub(context), size: 20),
        const SizedBox(width: 8),
        Text(
          'Ambient',
          style: TextStyle(
            color: AppColors.text(context),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.textSub(context).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'SOON',
            style: TextStyle(
              color: AppColors.textSub(context),
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  static String _hexOf(Color c) =>
      c.toARGB32().toRadixString(16).substring(2).toUpperCase();

  static String _suggestTvState(String mood) {
    switch (mood.toLowerCase()) {
      case 'happy':
      case 'excited':
        return 'Comedy / Music';
      case 'sad':
      case 'melancholy':
        return 'Calm playlist';
      case 'fearful':
      case 'fear':
        return 'Off';
      case 'calm':
        return 'Nature scenes';
      case 'angry':
        return 'Off';
      default:
        return 'Auto';
    }
  }
}

class _AmbientTile extends StatelessWidget {
  const _AmbientTile({
    required this.icon,
    required this.title,
    required this.status,
  });

  final IconData icon;
  final String title;
  final String status;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.textSub(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderCol(context).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: muted, size: 18),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: muted.withValues(alpha: 0.8),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
