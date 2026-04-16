import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// File-based structured logger used by every Spotify submodule.
/// Keeps diagnostic output off the console in production but makes it easy
/// to grep the log file during development.
class SpotifyLogger {
  static File? _cachedLogFile;

  static Future<File> _getLogFile() async {
    if (_cachedLogFile != null) return _cachedLogFile!;
    final appDir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${appDir.path}/logs');
    if (!logDir.existsSync()) logDir.createSync(recursive: true);
    _cachedLogFile = File('${logDir.path}/spotify_dev.log');
    debugPrint('[Spotify] Log path: ${_cachedLogFile!.path}');
    return _cachedLogFile!;
  }

  static Future<void> log(String category, dynamic data) async {
    final timestamp = DateTime.now().toIso8601String();
    final entry = '''
╔══════════════════════════════════════════════════════════════
║ [$timestamp] $category
╠══════════════════════════════════════════════════════════════
║ ${const JsonEncoder.withIndent('  ').convert(data)}
╚══════════════════════════════════════════════════════════════

''';

    try {
      final logFile = await _getLogFile();
      await logFile.writeAsString(entry, mode: FileMode.append);
      debugPrint('[Spotify] $category logged to ${logFile.path}');
    } catch (e) {
      debugPrint('[Spotify] Log write error: $e');
    }
  }

  static Future<void> clear() async {
    final logFile = await _getLogFile();
    if (await logFile.exists()) {
      await logFile.writeAsString('');
      debugPrint('[Spotify] Log file cleared');
    }
  }
}
