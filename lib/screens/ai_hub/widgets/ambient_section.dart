import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../constants/app_colors.dart';
import '../../../constants/mood_palette.dart';
import '../../../providers/home_provider.dart';
import '../../../services/api_service.dart';

/// Emotion-aware ambient scene applier. One tap sets the home's lighting
/// (and optionally the speaker) to a coordinated atmosphere matching the
/// detected mood.
class AmbientSection extends ConsumerStatefulWidget {
  const AmbientSection({super.key, required this.mood});

  final String? mood;

  @override
  ConsumerState<AmbientSection> createState() => _AmbientSectionState();
}

class _AmbientSectionState extends ConsumerState<AmbientSection> {
  bool _running = false;
  String? _lastAppliedMood;

  // Per-mood tuning beyond the LED color (which comes from MoodPalette).
  // brightness 0-100, speakerVolume 0-100 (null = leave alone),
  // playback: 'play'|'pause'|'stop'|null.
  ({int brightness, int? speakerVolume, String? playback, String description})
      _sceneFor(String mood) {
    switch (mood.toLowerCase()) {
      case 'happy':
        return (brightness: 90, speakerVolume: 60, playback: 'play',
            description: 'Vivid amber glow · upbeat audio');
      case 'sad':
        return (brightness: 30, speakerVolume: 35, playback: 'play',
            description: 'Warm dim cocoon · calming volume');
      case 'melancholy':
        return (brightness: 25, speakerVolume: 30, playback: 'play',
            description: 'Muted twilight · quiet listen');
      case 'angry':
        return (brightness: 35, speakerVolume: 20, playback: 'pause',
            description: 'Cool calming light · audio paused');
      case 'calm':
        return (brightness: 45, speakerVolume: 30, playback: null,
            description: 'Soft teal glow · low volume');
      case 'excited':
        return (brightness: 100, speakerVolume: 70, playback: 'play',
            description: 'Bright vibrant · energetic playback');
      case 'fear':
      case 'fearful':
        return (brightness: 50, speakerVolume: 25, playback: 'pause',
            description: 'Warm gentle light · audio quiet');
      case 'surprise':
      case 'surprised':
        return (brightness: 95, speakerVolume: null, playback: null,
            description: 'Bright attention amber');
      case 'disgust':
      case 'disgusted':
        return (brightness: 55, speakerVolume: null, playback: null,
            description: 'Cool refresh tone');
      case 'neutral':
      default:
        return (brightness: 70, speakerVolume: null, playback: null,
            description: 'Balanced white · neutral tone');
    }
  }

  String _ledHex(String mood) {
    // Neutral has no flattering LED equivalent for grey; force white.
    if (mood.toLowerCase() == 'neutral') return '#FFFFFF';
    final c = MoodPalette.colorFor(mood);
    final argb = c.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    String two(int n) => n.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#${two(r)}${two(g)}${two(b)}';
  }

  bool _isLed(Map d) {
    final t = (d['device_type'] ?? '').toString().toLowerCase();
    final n = (d['device_name'] ?? '').toString().toLowerCase();
    return t == 'light' ||
        t == 'led' ||
        t == 'led_strip' ||
        t == 'smartbulb' ||
        n.contains('led') ||
        n.contains('light');
  }

  bool _isSpeaker(Map d) {
    final t = (d['device_type'] ?? '').toString().toLowerCase();
    final n = (d['device_name'] ?? '').toString().toLowerCase();
    return t == 'speaker' || t == 'audio' || n.contains('speaker');
  }

  Future<void> _apply() async {
    final mood = widget.mood;
    if (mood == null || _running) return;

    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = (selectedHome?['home_id'] ??
            selectedHome?['id'] ??
            selectedHome?['homeid'])
        ?.toString();
    if (homeId == null || homeId.isEmpty) return;

    final scene = _sceneFor(mood);
    final hex = _ledHex(mood);

    setState(() => _running = true);

    final devices = await ApiService.fetchDevices(homeId);
    if (devices == null || !mounted) {
      if (mounted) setState(() => _running = false);
      return;
    }

    final commands = <List<dynamic>>[]; // [deviceId, property, value]
    final touched = <String>{};
    for (final d in devices) {
      if (d is! Map) continue;
      final id = d['deviceid']?.toString();
      if (id == null) continue;
      if (_isLed(d)) {
        commands.add([id, 'power', 'on']);
        commands.add([id, 'brightness', scene.brightness.toString()]);
        commands.add([id, 'color', hex]);
        touched.add(id);
      } else if (_isSpeaker(d)) {
        if (scene.speakerVolume != null) {
          commands.add([id, 'volume', scene.speakerVolume!.toString()]);
          touched.add(id);
        }
        if (scene.playback != null) {
          commands.add([id, 'playback', scene.playback!]);
          touched.add(id);
        }
      }
    }

    if (commands.isEmpty) {
      if (mounted) {
        setState(() => _running = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No lights or speakers found in this home.'),
            backgroundColor: AppColors.cardDark,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final results = await Future.wait(commands.map((c) => ApiService.sendCommand(
          homeId: homeId,
          deviceId: c[0] as String,
          action: c[1] as String,
          value: c[2],
        )));
    if (!mounted) return;
    final ok = results.where((r) => r).length;
    final allOk = ok == results.length;
    setState(() {
      _running = false;
      if (allOk) _lastAppliedMood = mood;
    });
    final label = MoodPalette.label(mood);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(allOk
            ? '$label ambience applied · ${touched.length} device${touched.length == 1 ? "" : "s"}'
            : '$label partial · $ok of ${results.length} commands sent'),
        backgroundColor: allOk ? AppColors.accentGreen : AppColors.accentOrange,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mood = widget.mood;
    final hasMood = mood != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, hasMood),
          const SizedBox(height: 6),
          Text(
            hasMood
                ? 'Match your home to how you feel.'
                : 'Detect or pick a mood and your room can match it.',
            style: TextStyle(color: AppColors.textSub(context), fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (!hasMood) _emptyState(context) else _applyCard(context, mood),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool hasMood) {
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
        if (hasMood && _lastAppliedMood == widget.mood) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accentGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: AppColors.accentGreen, size: 12),
                const SizedBox(width: 4),
                Text(
                  'APPLIED',
                  style: TextStyle(
                    color: AppColors.accentGreen,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.borderCol(context).withValues(alpha: 0.5),
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline,
              color: AppColors.textSub(context), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Scan your face or pick a mood to enable one-tap ambience.',
              style: TextStyle(
                color: AppColors.textSub(context),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _applyCard(BuildContext context, String mood) {
    final accent = MoodPalette.colorFor(mood);
    final emoji = MoodPalette.emojiFor(mood);
    final label = MoodPalette.label(mood);
    final scene = _sceneFor(mood);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.18),
            accent.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Mood swatch
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.45),
                      blurRadius: 10,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: AppColors.text(context),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      scene.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSub(context),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _running ? null : _apply,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: accent.withValues(alpha: 0.5),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(
                _running ? 'Applying…' : 'Apply $label vibe',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Affects LED lights and speaker. Other devices stay as-is.',
            style: TextStyle(
              color: AppColors.textSub(context).withValues(alpha: 0.85),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
