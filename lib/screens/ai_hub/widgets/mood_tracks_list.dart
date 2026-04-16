import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

/// Mood Tracks section: Spotify connect prompt, loading spinner,
/// empty state, or a list of personalized track rows.
class MoodTracksList extends StatelessWidget {
  const MoodTracksList({
    super.key,
    required this.isConnected,
    required this.isLoading,
    required this.hasMood,
    required this.tracks,
    required this.moodColor,
    required this.onConnect,
    required this.onRefresh,
  });

  final bool isConnected;
  final bool isLoading;
  final bool hasMood;
  final List<Map<String, dynamic>>? tracks;
  final Color moodColor;
  final VoidCallback onConnect;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          const SizedBox(height: 14),
          _body(context),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.music_note, color: Color(0xFF1DB954), size: 20),
        const SizedBox(width: 8),
        Text(
          'Mood Tracks',
          style: TextStyle(
            color: AppColors.text(context),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        if (isConnected && tracks != null)
          GestureDetector(
            onTap: isLoading ? null : onRefresh,
            child: Icon(Icons.refresh,
                color: AppColors.textSub(context), size: 20),
          ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (!isConnected) return _ConnectPrompt(onTap: onConnect, loading: isLoading);
    if (!hasMood) return _empty(context, 'Scan first to see recommendations.');
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primaryBlue,
            ),
          ),
        ),
      );
    }
    if (tracks == null || tracks!.isEmpty) {
      return _empty(context, 'No recommendations found.');
    }
    return Column(
      children: tracks!.map((t) => _TrackRow(track: t, moodColor: moodColor)).toList(),
    );
  }

  Widget _empty(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: AppColors.textSub(context), fontSize: 13),
        ),
      ),
    );
  }
}

class _ConnectPrompt extends StatelessWidget {
  const _ConnectPrompt({required this.onTap, required this.loading});

  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1DB954), Color(0xFF117A37)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.music_note, color: Colors.white),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Connect Spotify — for mood-based tracks',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.moodColor});

  final Map<String, dynamic> track;
  final Color moodColor;

  @override
  Widget build(BuildContext context) {
    final name = (track['name'] ?? '-').toString();
    final artist = (track['artist'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderCol(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: moodColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.music_note, color: moodColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.speaker, color: AppColors.textSub(context), size: 18),
        ],
      ),
    );
  }
}
