import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';
import '../../../providers/home_provider.dart';
import '../../../services/api_service.dart';
import '../../../services/spotify/spotify_api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared prefix every Pi self-derives at boot — `AkilliEv-<machineid6>`.
/// Mobile resolves the in-house speaker by prefix, no per-home config.
const String kSpeakerNamePrefix = 'AkilliEv-';

/// Mood Tracks section: Spotify connect prompt, loading spinner,
/// empty state, or a list of personalized track rows.
///
/// Stateful so we can persistently highlight whichever track the user
/// last tapped — without that, after [_busy] clears there's no visual
/// signal that "this is the song playing right now".
class MoodTracksList extends StatefulWidget {
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
  State<MoodTracksList> createState() => _MoodTracksListState();
}

class _MoodTracksListState extends State<MoodTracksList> {
  /// URI of the most recently tapped track. Cleared when the track list
  /// is replaced (e.g. mood changes or refresh button), so a stale
  /// "playing" highlight doesn't survive the swap.
  String? _activeUri;

  bool get isConnected => widget.isConnected;
  bool get isLoading => widget.isLoading;
  bool get hasMood => widget.hasMood;
  List<Map<String, dynamic>>? get tracks => widget.tracks;
  Color get moodColor => widget.moodColor;
  VoidCallback get onConnect => widget.onConnect;
  VoidCallback get onRefresh => widget.onRefresh;

  @override
  void didUpdateWidget(covariant MoodTracksList old) {
    super.didUpdateWidget(old);
    // Track list got refreshed → drop stale highlight.
    if (old.tracks != widget.tracks) {
      _activeUri = null;
    }
  }

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
      children: [
        for (int i = 0; i < tracks!.length; i++)
          _TrackRow(
            track: tracks![i],
            moodColor: moodColor,
            isActive: _activeUri == tracks![i]['uri']?.toString(),
            onActivated: (uri) => setState(() => _activeUri = uri),
            // Pass the rest of the queue so when this track ends Spotify
            // auto-plays the next mood-matched recommendation instead of
            // stopping. Order = tapped track first, then the others in
            // their existing list order.
            queueAfter: [
              ...tracks!.sublist(i + 1),
              ...tracks!.sublist(0, i),
            ],
          ),
      ],
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

class _TrackRow extends ConsumerStatefulWidget {
  const _TrackRow({
    required this.track,
    required this.moodColor,
    required this.queueAfter,
    required this.isActive,
    required this.onActivated,
  });

  final Map<String, dynamic> track;
  final Color moodColor;

  /// Tracks to queue after [track] so playback continues automatically
  /// once this song ends. Same shape as [MoodTracksList.tracks].
  final List<Map<String, dynamic>> queueAfter;

  /// True if this row is the most recently tapped track in the list —
  /// rendered with a persistent accent so the user can see "this is what
  /// I just queued" even after the loading spinner clears.
  final bool isActive;

  /// Called with this track's URI once a play request fires, so the
  /// parent can mark it as active and clear the previous one.
  final void Function(String uri) onActivated;

  @override
  ConsumerState<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends ConsumerState<_TrackRow> {
  bool _busy = false;

  Future<void> _onTap() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final uri = (widget.track['uri'] ?? '').toString();
    final name = (widget.track['name'] ?? '-').toString();

    if (uri.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Parça bilgisi eksik.')));
      return;
    }

    setState(() => _busy = true);
    widget.onActivated(uri);
    try {
      var device =
          await SpotifyApiClient.findDeviceByPrefix(kSpeakerNamePrefix);

      // Speaker isn't reachable on Spotify Connect — most common cause is
      // that the user hasn't powered on the in-house speaker yet, so the
      // Pi's raspotify daemon isn't running. Auto-recover: ask the
      // backend to flip its power to "on", wait a few seconds for the
      // daemon to register with Spotify, then retry the lookup.
      if (device == null) {
        final selectedHome = ref.read(selectedHomeProvider);
        final homeId = (selectedHome?['home_id'] ??
                selectedHome?['id'] ??
                selectedHome?['homeid'])
            ?.toString();
        final devices =
            homeId == null ? null : await ApiService.fetchDevices(homeId);
        Map<String, dynamic>? speakerDev;
        if (devices != null) {
          for (final d in devices) {
            if (d is! Map) continue;
            final type = (d['device_type'] ?? '').toString().toLowerCase();
            final name = (d['device_name'] ?? '').toString().toLowerCase();
            if (type == 'speaker' || type == 'audio' ||
                name.contains('speaker')) {
              speakerDev = Map<String, dynamic>.from(d);
              break;
            }
          }
        }

        if (speakerDev != null && homeId != null) {
          if (!mounted) return;
          messenger.showSnackBar(const SnackBar(
            content: Text('Speaker is off — turning it on…'),
            duration: Duration(seconds: 2),
          ));
          final ok = await ApiService.sendCommand(
            homeId: homeId,
            deviceId: speakerDev['deviceid'].toString(),
            action: 'power',
            value: 'on',
          );
          if (ok) {
            // Give the Pi a moment to spin up raspotify and register
            // with Spotify Connect. ~5 s is the typical cold-start.
            await Future.delayed(const Duration(seconds: 6));
            device = await SpotifyApiClient.findDeviceByPrefix(
                kSpeakerNamePrefix);
          }
        }

        if (device == null) {
          if (!mounted) return;
          messenger.showSnackBar(SnackBar(
            content: Text(speakerDev == null
                ? "No smart speaker is set up in this home."
                : "Couldn't reach the speaker. Try turning it on manually."),
            duration: const Duration(seconds: 3),
          ));
          return;
        }
      }
      // Build the full queue: tapped track first, then the rest of the
      // mood-matched recommendations. Spotify will auto-advance through
      // them when each finishes — no extra "next" calls needed here.
      final queueUris = <String>[uri];
      for (final t in widget.queueAfter) {
        final u = (t['uri'] ?? '').toString();
        if (u.isNotEmpty && u != uri) queueUris.add(u);
      }
      final ok = await SpotifyApiClient.playTracks(
        deviceId: device['id'].toString(),
        uris: queueUris,
      );
      if (!mounted) return;
      // No snackbar on success — the persistent highlight on the row
      // (and the speaker card up top) already says "playing this".
      // Only surface a snackbar on failure.
      if (!ok) {
        messenger.showSnackBar(SnackBar(
          content: Text('Çalınamadı: $name'),
          duration: const Duration(seconds: 2),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.track['name'] ?? '-').toString();
    final artist = (widget.track['artist'] ?? '').toString();

    final highlight = _busy || widget.isActive;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: highlight
              ? widget.moodColor.withValues(alpha: 0.12)
              : AppColors.card(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: highlight
                ? widget.moodColor
                : AppColors.borderCol(context),
            width: widget.isActive ? 1.4 : 1,
          ),
          boxShadow: widget.isActive && !_busy
              ? [
                  BoxShadow(
                    color: widget.moodColor.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: widget.moodColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.music_note, color: widget.moodColor, size: 20),
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
            if (_busy)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.moodColor,
                ),
              )
            else if (widget.isActive)
              Icon(Icons.graphic_eq,
                  color: widget.moodColor, size: 22)
            else
              Icon(Icons.play_circle_fill,
                  color: widget.moodColor, size: 22),
          ],
        ),
      ),
    );
  }
}
