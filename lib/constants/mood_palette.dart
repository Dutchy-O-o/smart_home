import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Emoji and accent color for each supported mood label.
/// Shared by the Emotion Hub UI and anything that visualizes mood state.
class MoodPalette {
  static const Map<String, String> emojis = {
    'happy': '😊',
    'sad': '😢',
    'melancholy': '🌧️',
    'angry': '😠',
    'calm': '😌',
    'excited': '🤩',
    'neutral': '😐',
    'fearful': '😨',
    'surprised': '😮',
    'disgusted': '🤢',
    // Short forms returned by some models
    'disgust': '🤢',
    'fear': '😨',
    'surprise': '😮',
  };

  static const Map<String, Color> colors = {
    'happy': Color(0xFFFFB800),
    'sad': Color(0xFF4A7FBF),
    'melancholy': Color(0xFF6B7FAA),
    'angry': Color(0xFFE53935),
    'calm': Color(0xFF4DB6AC),
    'excited': Color(0xFFFF6B9D),
    'neutral': Color(0xFF9E9E9E),
    'fearful': Color(0xFF7E57C2),
    'fear': Color(0xFF7E57C2),
    'surprised': Color(0xFFFFCA28),
    'surprise': Color(0xFFFFCA28),
    'disgusted': Color(0xFF8BC34A),
    'disgust': Color(0xFF8BC34A),
  };

  /// Moods that can be picked manually from the sheet.
  static const List<String> pickable = [
    'happy',
    'sad',
    'melancholy',
    'angry',
    'calm',
    'excited',
    'neutral',
    'fear',
    'surprise',
    'disgust',
  ];

  static Color colorFor(String? mood) =>
      colors[mood?.toLowerCase()] ?? AppColors.primaryBlue;

  static String emojiFor(String? mood) =>
      emojis[mood?.toLowerCase()] ?? '✨';

  static String label(String mood) =>
      mood[0].toUpperCase() + mood.substring(1);
}
