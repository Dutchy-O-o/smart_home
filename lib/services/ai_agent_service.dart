import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/env.dart';
import 'api_service.dart';

/// JSON-Schema tool definitions sent to Claude. Pulled out to a top-level
/// constant so unit tests can assert structure without standing up the
/// full Anthropic request loop.
@visibleForTesting
final List<Map<String, dynamic>> aiAgentTools = [
  {
    'name': 'get_sensor_data',
    'description':
        'Get current sensor readings (temperature, humidity, gas level, vibration) from the smart home sensors.',
    'input_schema': {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
  },
  {
    'name': 'get_devices',
    'description':
        'Get list of all connected smart home devices. Each device has a "deviceid" field (use this for control_device), "device_name", "device_type", and "properties" array with current values.',
    'input_schema': {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
  },
  {
    'name': 'control_device',
    'description':
        'Send a command to control a smart home device. You MUST call get_devices first to get the exact "deviceid" value. Send one property change at a time. For multiple changes (e.g. power + target_temp), call this tool multiple times.\n\nSupported properties per device type:\n• Light/LED strip: power, brightness, color\n• Speaker: power, volume, playback\n• TV: power, volume, channel\n• Air Conditioner (device_type "ac" or "climate"): power, target_temp, mode, fan_speed\n• Oven / stove (device_type "oven" or "stove"): power, target_temp, mode, timer',
    'input_schema': {
      'type': 'object',
      'properties': {
        'device_id': {
          'type': 'string',
          'description':
              'The exact "deviceid" value from get_devices response (e.g. "dev_abc123")',
        },
        'action': {
          'type': 'string',
          'description': 'The property_name to change.',
          'enum': [
            'power',
            'brightness',
            'color',
            'volume',
            'channel',
            'playback',
            'target_temp',
            'mode',
            'fan_speed',
            'timer',
          ],
        },
        'value': {
          'description':
              'The value, always passed as a string:\n'
                  '• power → "on" / "off"\n'
                  '• brightness, volume → "0"-"100"\n'
                  '• channel → integer string\n'
                  '• color → hex like "#0000FF"\n'
                  '• playback → "play" / "pause" / "stop"\n'
                  '• target_temp on AC → "16"-"30" (°C)\n'
                  '• target_temp on Oven → "50"-"250" (°C, step 10)\n'
                  '• mode on AC → "cool" / "heat" / "auto" / "fan" / "dry"\n'
                  '• mode on Oven → "bake" / "broil" / "fan" / "defrost"\n'
                  '• fan_speed (AC only) → "low" / "mid" / "high" / "auto"\n'
                  '• timer (Oven only) → "0"-"180" minutes (step 5)',
        },
      },
      'required': ['device_id', 'action', 'value'],
    },
  },
  {
    'name': 'get_automations',
    'description':
        'Get list of all automation rules configured in the smart home.',
    'input_schema': {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
  },
  {
    'name': 'set_mood',
    'description':
        "Update the user's current emotional state. Use this when the user tells you how they feel, OR when they say the previous emotion detection (from face scan) was wrong and want to correct it. This will update the Emotion Hub and trigger new mood-based music recommendations.",
    'input_schema': {
      'type': 'object',
      'properties': {
        'mood': {
          'type': 'string',
          'description':
              'One of: happy, sad, melancholy, angry, calm, excited, neutral, fear, surprise, disgust',
          'enum': [
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
          ],
        },
        'confidence': {
          'type': 'number',
          'description':
              'How certain you are (0.0-1.0). Use 1.0 if user explicitly stated their mood.',
        },
      },
      'required': ['mood', 'confidence'],
    },
  },
];

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

  static String get _apiKey => Env.claudeApiKey;
  static bool get isConfigured => Env.hasClaudeKey;

  static Future<String> chat({
    required List<Map<String, dynamic>> messages,
    required String homeId,
    void Function(String action)? onToolAction,
    void Function(String mood, double confidence)? onSetMood,
    /// Raw control_device tool-call hook. Fires before the AWS round trip
    /// so the UI can push an optimistic value into [deviceOverridesProvider]
    /// — the Pi firmware doesn't echo AC/oven detail properties yet, so
    /// without this overlay the devices screen would snap back to the
    /// polled DB state and the user would think the assistant did nothing.
    void Function(String deviceId, String action, dynamic value)?
        onControlDevice,
    /// Called with each text delta as the model streams its reply. The
    /// caller appends to its bubble for a typewriter effect. Tool-use
    /// turns don't emit text deltas — only the final response does.
    void Function(String delta)? onTextDelta,
  }) async {
    if (!isConfigured) {
      return 'API key is not configured. Set it in lib/config/env.dart';
    }

    final tools = aiAgentTools;

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
- AC (device_type "ac"/"climate") supports target_temp ("16"-"30"), mode ("cool"/"heat"/"auto"/"fan"/"dry"), fan_speed ("low"/"mid"/"high"/"auto").
- Oven (device_type "oven"/"stove") supports target_temp ("50"-"250", step 10), mode ("bake"/"broil"/"fan"/"defrost"), timer ("0"-"180" minutes, step 5).
- Always send the control_device command when asked, even if the cached state looks right — state can be stale.
- When the user asks for a feature that exists on the device type (e.g. fan or defrost on the oven), JUST DO IT — don't say "the device doesn't support it". The schemas above are authoritative.
- If multiple devices match the user's request (e.g. two AC units, or an oven called "Oven" with device_type "stove"), pick the most likely one based on the user's wording, or list them and ask which one if it's truly ambiguous.
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

            // Fire optimistic device-state hook so the devices screen can
            // overlay the new value before AWS / Pi round trip completes.
            if (toolName == 'control_device' && onControlDevice != null) {
              final devId = (input['device_id'] ?? '').toString();
              final act = (input['action'] ?? '').toString();
              if (devId.isNotEmpty && act.isNotEmpty) {
                onControlDevice(devId, act, input['value']);
              }
            }

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

  /// Builds the small italic chip text that flashes under the assistant
  /// bubble while a tool call is in flight. Robotic strings like
  /// "Controlling: target_temp → 26" break immersion during a demo, so we
  /// map each (action, value) pair to a natural English phrase. Unknown
  /// combinations fall through to a generic "Sending command..." line
  /// rather than leaking the raw property name.
  static String _describeAction(String toolName, Map<String, dynamic> input) {
    switch (toolName) {
      case 'get_sensor_data':
        return 'Reading sensor data...';
      case 'get_devices':
        return 'Fetching devices...';
      case 'get_automations':
        return 'Fetching automations...';
      case 'set_mood':
        return 'Updating mood: ${(input['mood'] ?? '').toString()}';
      case 'control_device':
        return _describeControl(input);
      default:
        return 'Working on it...';
    }
  }

  /// Sentence-form, log-friendly version of [_describeControl]. The chat
  /// screen uses this for the alerts feed entry it writes when the
  /// assistant touches a device — full sentences so a user scrolling
  /// notifications reads "Set the temperature to 26°C" rather than a
  /// key-value blob like "Temperature 26°C".
  static String describeControlForLog(String action, dynamic rawValue) {
    final value = rawValue?.toString() ?? '';
    switch (action) {
      case 'power':
        return value == 'on'
            ? 'Turned the device on.'
            : 'Turned the device off.';
      case 'target_temp':
        return 'Set the temperature to $value°C.';
      case 'mode':
        return 'Switched to ${_modeLabel(value)} mode.';
      case 'fan_speed':
        return 'Set the fan speed to ${_fanLabel(value)}.';
      case 'brightness':
        return 'Set the brightness to $value%.';
      case 'volume':
        return 'Set the volume to $value%.';
      case 'color':
        return 'Changed the light color.';
      case 'timer':
        return value == '0'
            ? 'Cleared the timer.'
            : 'Started a $value-minute timer.';
      case 'channel':
        return 'Switched to channel $value.';
      case 'playback':
        switch (value) {
          case 'play':
            return 'Started playing music.';
          case 'pause':
            return 'Paused playback.';
          case 'stop':
            return 'Stopped playback.';
        }
        return 'Sent a playback command.';
    }
    return 'Updated $action to $value.';
  }

  static String _describeControl(Map<String, dynamic> input) {
    final action = (input['action'] ?? '').toString();
    final raw = input['value'];
    final value = raw?.toString() ?? '';
    switch (action) {
      case 'power':
        return value == 'on' ? 'Turning on...' : 'Turning off...';
      case 'target_temp':
        return 'Setting temperature to $value°C...';
      case 'mode':
        return 'Switching to ${_modeLabel(value)} mode...';
      case 'fan_speed':
        return 'Setting fan to ${_fanLabel(value)}...';
      case 'brightness':
        return 'Setting brightness to $value%...';
      case 'volume':
        return 'Setting volume to $value%...';
      case 'color':
        return 'Changing color...';
      case 'timer':
        return value == '0'
            ? 'Clearing timer...'
            : 'Setting timer to $value min...';
      case 'channel':
        return 'Switching to channel $value...';
      case 'playback':
        switch (value) {
          case 'play':
            return 'Starting playback...';
          case 'pause':
            return 'Pausing playback...';
          case 'stop':
            return 'Stopping playback...';
        }
        return 'Sending playback command...';
    }
    return 'Sending command...';
  }

  static String _modeLabel(String mode) {
    switch (mode) {
      case 'cool':
        return 'cool';
      case 'heat':
        return 'heat';
      case 'fan':
        return 'fan';
      case 'dry':
        return 'dry';
      case 'auto':
        return 'auto';
      case 'bake':
        return 'bake';
      case 'broil':
        return 'broil';
      case 'defrost':
        return 'defrost';
    }
    return mode;
  }

  static String _fanLabel(String v) {
    switch (v) {
      case 'low':
        return 'low';
      case 'mid':
        return 'medium';
      case 'high':
        return 'high';
      case 'auto':
        return 'auto';
    }
    return v;
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
