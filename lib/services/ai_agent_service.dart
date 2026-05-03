import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'api_service.dart';

class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
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

    const systemPrompt = '''You are a helpful smart home AI assistant. You control devices, read sensors, manage automations, and track the user's emotional state.

CRITICAL RULES:
1. To control ANY device, ALWAYS call get_devices FIRST to get the exact "deviceid" field value.
2. Use the "deviceid" value exactly as returned (e.g. "dev_abc123"), NOT the device name.
3. For multiple property changes on one device, call control_device separately for each property.
4. For power changes, use action="power" with value="on" or value="off".
5. For brightness, use action="brightness" with an integer value like 100.
6. ALWAYS send the control_device command when the user asks, even if the device appears to already be in that state. Device state data may be stale. Never skip a command because you think the device is already in the desired state.
7. Report sensor data with proper units.
8. Respond in the same language the user speaks (Turkish or English).
9. Be concise and friendly.
10. If the user mentions feeling something (e.g. "üzgünüm", "I'm happy", "the scanner thought I was sad but I'm calm"), call set_mood to update their emotional state. Always confirm in your reply what you set.''';

    var currentMessages = List<Map<String, dynamic>>.from(messages);

    for (int attempt = 0; attempt < 5; attempt++) {
      final response = await _callApi(
        system: systemPrompt,
        messages: currentMessages,
        tools: tools,
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

  static Future<Map<String, dynamic>?> _callApi({
    required String system,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': _model,
          'max_tokens': 1024,
          'system': system,
          'messages': messages,
          'tools': tools,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        debugPrint('Claude API error: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Claude API connection error: $e');
      return null;
    }
  }
}
