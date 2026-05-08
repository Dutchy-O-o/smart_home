import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'api_service.dart';

class ChatMessage {
  final String role; // 'user' or 'assistant'
  // Mutable so the chat screen can append streaming deltas in-place.
  String content;
  final bool isToolAction;

  ChatMessage({required this.role, required this.content, this.isToolAction = false});
}

class AiAgentService {
  static const String _model = 'claude-haiku-4-5-20251001';
  static const String _apiUrl = 'https://api.anthropic.com/v1/messages';

  static String get _apiKey => dotenv.env['CLAUDE_API_KEY'] ?? '';
  static bool get isConfigured => _apiKey.isNotEmpty;

  static Future<String> chat({
    required List<Map<String, dynamic>> messages,
    required String homeId,
    void Function(String action)? onToolAction,
    void Function(String mood, double confidence)? onSetMood,
    /// Called with each text delta as the model streams its reply. The
    /// caller appends to its bubble for a typewriter effect. Tool-use
    /// turns don't emit text deltas — only the final response does.
    void Function(String delta)? onTextDelta,
  }) async {
    if (!isConfigured) {
      return 'API key is not configured. Set it in lib/config/env.dart';
    }

    final tools = [
      {
        'name': 'get_sensor_data',
        'description': 'Get current sensor readings (temperature, humidity, gas level, vibration) from the smart home sensors.',
        'input_schema': {'type': 'object', 'properties': {}, 'required': []},
      },
      {
        'name': 'get_devices',
        'description': 'Get list of all connected smart home devices. Each device has a "deviceid" field (use this for control_device), "device_name", "device_type", and "properties" array with current values.',
        'input_schema': {'type': 'object', 'properties': {}, 'required': []},
      },
      {
        'name': 'control_device',
        'description': 'Send a command to control a smart home device. You MUST call get_devices first to get the exact "deviceid" value. Send one property change at a time. For multiple changes (e.g. power + brightness), call this tool multiple times.',
        'input_schema': {
          'type': 'object',
          'properties': {
            'device_id': {'type': 'string', 'description': 'The exact "deviceid" value from get_devices response (e.g. "dev_abc123")'},
            'action': {'type': 'string', 'description': 'The property_name to change: "power", "brightness", "color", "volume", "channel", "playback"'},
            'value': {'description': 'The value: for power use "on"/"off", for brightness/volume use integer 0-100, for channel use integer, for color use hex string like "#0000FF", for playback use "play"/"pause"/"stop"'},
          },
          'required': ['device_id', 'action', 'value'],
        },
      },
      {
        'name': 'get_automations',
        'description': 'Get list of all automation rules configured in the smart home.',
        'input_schema': {'type': 'object', 'properties': {}, 'required': []},
      },
      {
        'name': 'set_mood',
        'description': 'Update the user\'s current emotional state. Use this when the user tells you how they feel, OR when they say the previous emotion detection (from face scan) was wrong and want to correct it. This will update the Emotion Hub and trigger new mood-based music recommendations.',
        'input_schema': {
          'type': 'object',
          'properties': {
            'mood': {
              'type': 'string',
              'description': 'One of: happy, sad, melancholy, angry, calm, excited, neutral, fear, surprise, disgust',
              'enum': ['happy', 'sad', 'melancholy', 'angry', 'calm', 'excited', 'neutral', 'fear', 'surprise', 'disgust'],
            },
            'confidence': {
              'type': 'number',
              'description': 'How certain you are (0.0-1.0). Use 1.0 if user explicitly stated their mood.',
            },
          },
          'required': ['mood', 'confidence'],
        },
      },
    ];

    const systemPrompt = '''You're the smart home assistant the user lives with — talk like a friend, not a manual.

Voice & tone:
- Warm, casual, human. Short sentences. Use the user's language (Turkish or English) naturally and match their register.
- One thought per line. No headings, no bullet lists for normal chit-chat — only use a list when the user asks for one or there are clearly 3+ parallel items.
- Don't restate the request before answering. Don't end with "Let me know if you need anything else!" — just stop when the answer is done.
- React like a person. If something turned on, "Done — lights are on." If you couldn't find a device, "Hmm, I don't see a TV in this home."
- Avoid robotic phrasing: never say "I have successfully executed", "As an AI", "I will now". Avoid emoji unless the user uses them first.
- When confirming an action, lead with the result, not the process.

How tools work (don't mention these to the user):
- For ANY device control, call get_devices FIRST to grab the exact "deviceid" — never guess from the name.
- Use the "deviceid" value exactly as returned (e.g. "dev_abc123").
- For multiple property changes on one device, call control_device once per property.
- power → "on" / "off". brightness/volume → 0-100. color → hex like "#FF8800". playback → "play" / "pause" / "stop".
- Always send the control_device command when asked, even if the cached state looks right — state can be stale.
- If the user describes how they feel ("I'm sad", "scanner got it wrong, I'm calm"), call set_mood and casually confirm.

When reporting sensor data, give the number with its unit and a tiny human take ("23°C — pretty comfortable" rather than "Temperature: 23 degrees Celsius").''';

    var currentMessages = List<Map<String, dynamic>>.from(messages);

    for (int attempt = 0; attempt < 5; attempt++) {
      // Stream the response so the UI can render text as it arrives.
      // The streamed result includes both content blocks and stop_reason
      // so we can keep the existing tool-use loop intact.
      final response = await _callApiStream(
        system: systemPrompt,
        messages: currentMessages,
        tools: tools,
        onTextDelta: onTextDelta,
      );

      if (response == null) {
        return 'Connection error. Please check your internet connection.';
      }

      final stopReason = response['stop_reason'];
      final content = response['content'] as List<dynamic>;

      if (stopReason == 'tool_use') {
        final assistantContent = content;
        currentMessages.add({'role': 'assistant', 'content': assistantContent});

        List<Map<String, dynamic>> toolResults = [];

        for (final block in assistantContent) {
          if (block['type'] == 'tool_use') {
            final toolName = block['name'] as String;
            final toolId = block['id'] as String;
            final input = block['input'] as Map<String, dynamic>;

            onToolAction?.call(_describeAction(toolName, input));

            // Handle set_mood directly via callback — no API call needed
            if (toolName == 'set_mood' && onSetMood != null) {
              final mood = (input['mood'] ?? '').toString();
              final conf = (input['confidence'] is num)
                  ? (input['confidence'] as num).toDouble()
                  : 1.0;
              onSetMood(mood, conf);
              toolResults.add({
                'type': 'tool_result',
                'tool_use_id': toolId,
                'content': jsonEncode({
                  'success': true,
                  'mood': mood,
                  'confidence': conf,
                }),
              });
              continue;
            }

            final result = await _executeTool(toolName, input, homeId);
            toolResults.add({
              'type': 'tool_result',
              'tool_use_id': toolId,
              'content': result,
            });
          }
        }

        currentMessages.add({'role': 'user', 'content': toolResults});
      } else {
        final textBlocks = content.where((b) => b['type'] == 'text');
        if (textBlocks.isNotEmpty) {
          return textBlocks.map((b) => b['text']).join('\n');
        }
        return 'Done.';
      }
    }

    return 'Too many tool calls. Please try a simpler request.';
  }

  static String _describeAction(String toolName, Map<String, dynamic> input) {
    switch (toolName) {
      case 'get_sensor_data': return 'Reading sensor data...';
      case 'get_devices': return 'Fetching devices...';
      case 'control_device': return 'Controlling: ${input['action']} → ${input['value']}';
      case 'get_automations': return 'Fetching automations...';
      case 'set_mood': return 'Updating mood: ${input['mood']}';
      default: return 'Processing...';
    }
  }

  static Future<String> _executeTool(String name, Map<String, dynamic> input, String homeId) async {
    try {
      switch (name) {
        case 'get_sensor_data':
          final data = await ApiService.fetchSensors(homeId);
          if (data == null) return jsonEncode({'error': 'Failed to fetch sensor data'});
          return jsonEncode(data);

        case 'get_devices':
          final devices = await ApiService.fetchDevices(homeId);
          if (devices == null) return jsonEncode({'error': 'Failed to fetch devices'});
          return jsonEncode({'devices': devices});

        case 'control_device':
          final deviceId = input['device_id'] as String;
          final action = input['action'] as String;
          final value = input['value'];
          debugPrint('AI Agent: control_device($deviceId, $action, $value) homeId=$homeId');
          final success = await ApiService.sendCommand(
            homeId: homeId,
            deviceId: deviceId,
            action: action,
            value: value,
          );
          debugPrint('AI Agent: control_device result: $success');
          return jsonEncode({'success': success, 'device_id': deviceId, 'action': action, 'value': value});

        case 'get_automations':
          final automations = await ApiService.fetchAutomations(homeId);
          if (automations == null) return jsonEncode({'error': 'Failed to fetch automations'});
          return jsonEncode({'automations': automations});

        default:
          return jsonEncode({'error': 'Unknown tool: $name'});
      }
    } catch (e) {
      return jsonEncode({'error': e.toString()});
    }
  }

  /// Streams the Anthropic /v1/messages response and reassembles it into
  /// the same shape the non-streaming call returns ({ content, stop_reason }),
  /// so the calling code can stay unchanged.
  ///
  /// SSE event types we care about:
  ///  - content_block_start  → opens a new block (text or tool_use)
  ///  - content_block_delta  → appends text or tool input json
  ///  - content_block_stop   → finalizes the block
  ///  - message_delta        → carries stop_reason
  ///  - message_stop         → terminator
  static Future<Map<String, dynamic>?> _callApiStream({
    required String system,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    void Function(String delta)? onTextDelta,
  }) async {
    try {
      final request = http.Request('POST', Uri.parse(_apiUrl));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'x-api-key': _apiKey,
        'anthropic-version': '2023-06-01',
      });
      request.body = jsonEncode({
        'model': _model,
        'max_tokens': 1024,
        'stream': true,
        'system': system,
        'messages': messages,
        'tools': tools,
      });

      final streamed = await http.Client().send(request);
      if (streamed.statusCode != 200) {
        final body = await streamed.stream.bytesToString();
        debugPrint('Claude API error: ${streamed.statusCode} $body');
        return null;
      }

      // Reassembled response — mirrors the non-streaming JSON shape.
      final blocks = <Map<String, dynamic>>[];
      final partialJson = <int, StringBuffer>{}; // index → tool input json
      String? stopReason;

      // Buffer SSE lines: each event is "event: …\ndata: {…}\n\n".
      String buffer = '';
      await for (final chunk in streamed.stream
          .transform(const Utf8Decoder())) {
        buffer += chunk;
        while (true) {
          final i = buffer.indexOf('\n\n');
          if (i == -1) break;
          final raw = buffer.substring(0, i);
          buffer = buffer.substring(i + 2);

          String? data;
          for (final line in raw.split('\n')) {
            if (line.startsWith('data: ')) data = line.substring(6);
          }
          if (data == null || data.isEmpty) continue;

          Map<String, dynamic> evt;
          try {
            evt = jsonDecode(data) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }

          final type = evt['type'];
          if (type == 'content_block_start') {
            final idx = evt['index'] as int;
            final cb = Map<String, dynamic>.from(
                evt['content_block'] as Map<String, dynamic>);
            // Make sure indices align even if blocks arrive out of order.
            while (blocks.length <= idx) {
              blocks.add({'type': 'text', 'text': ''});
            }
            if (cb['type'] == 'text') {
              blocks[idx] = {'type': 'text', 'text': cb['text'] ?? ''};
            } else if (cb['type'] == 'tool_use') {
              blocks[idx] = {
                'type': 'tool_use',
                'id': cb['id'],
                'name': cb['name'],
                'input': cb['input'] ?? <String, dynamic>{},
              };
              partialJson[idx] = StringBuffer();
            }
          } else if (type == 'content_block_delta') {
            final idx = evt['index'] as int;
            final delta = evt['delta'] as Map<String, dynamic>;
            if (delta['type'] == 'text_delta') {
              final text = (delta['text'] ?? '').toString();
              if (idx < blocks.length && blocks[idx]['type'] == 'text') {
                blocks[idx]['text'] = (blocks[idx]['text'] ?? '') + text;
              }
              if (text.isNotEmpty) onTextDelta?.call(text);
            } else if (delta['type'] == 'input_json_delta') {
              partialJson[idx] ??= StringBuffer();
              partialJson[idx]!.write(delta['partial_json'] ?? '');
            }
          } else if (type == 'content_block_stop') {
            final idx = evt['index'] as int;
            final pj = partialJson[idx];
            if (pj != null && idx < blocks.length &&
                blocks[idx]['type'] == 'tool_use') {
              try {
                final parsed = jsonDecode(pj.toString());
                if (parsed is Map<String, dynamic>) {
                  blocks[idx]['input'] = parsed;
                }
              } catch (_) {/* leave as initial */}
            }
          } else if (type == 'message_delta') {
            final delta = evt['delta'] as Map<String, dynamic>?;
            stopReason = delta?['stop_reason']?.toString() ?? stopReason;
          } else if (type == 'message_stop') {
            // done — break out of stream consumption naturally.
          }
        }
      }

      return {
        'content': blocks,
        'stop_reason': stopReason ?? 'end_turn',
      };
    } catch (e) {
      debugPrint('Claude API stream error: $e');
      return null;
    }
  }
}
