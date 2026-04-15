import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class EmotionApiResult {
  final String mood;
  final double confidence;
  final Map<String, dynamic> raw;

  EmotionApiResult({
    required this.mood,
    required this.confidence,
    required this.raw,
  });
}

class EmotionApiService {
  static String get _endpoint =>
      dotenv.env['EMOTION_API_URL'] ?? 'https://192.168.1.10:8000/predict';

  // PRODUCTION NOTE: Temporary bypass for the Pi's self-signed cert.
  // In production, install a Let's Encrypt or root-CA cert on the Pi
  // and replace this client with a plain http.Client().
  static http.Client _buildClient() {
    if (kDebugMode) {
      final ioClient = HttpClient()
        ..badCertificateCallback = (_, __, ___) => true;
      return IOClient(ioClient);
    }
    return http.Client();
  }

  static Future<EmotionApiResult> predictFromJpeg(List<int> jpegBytes) async {
    final uri = Uri.parse(_endpoint);
    final client = _buildClient();
    try {
      final request = http.MultipartRequest('POST', uri)
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          jpegBytes,
          filename: 'frame.jpg',
        ));

      final streamed = await client.send(request).timeout(
            const Duration(seconds: 15),
          );
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 200) {
        throw Exception(
          'Predict failed (${response.statusCode}): ${response.body}',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final mood = (decoded['mood'] ?? decoded['emotion'] ?? 'unknown').toString();
      final confRaw = decoded['confidence'] ?? decoded['score'] ?? 0;
      final confidence = confRaw is num ? confRaw.toDouble() : 0.0;

      return EmotionApiResult(mood: mood, confidence: confidence, raw: decoded);
    } finally {
      client.close();
    }
  }
}
