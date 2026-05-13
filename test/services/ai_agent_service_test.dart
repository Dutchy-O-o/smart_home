import 'package:flutter_test/flutter_test.dart';

import 'package:akilli_ev/services/ai_agent_service.dart';

/// These tests pin the tool-loop's *contract* with Claude: tool names,
/// supported property enums, schema shape. They don't hit the network —
/// the real value here is catching silent regressions when someone
/// edits a property name without thinking through every callsite.
///
/// E.g. if a future refactor drops 'fan_speed' from the action enum, the
/// AC card will keep dispatching the command but Claude will refuse to
/// emit it. That kind of bug is invisible in normal QA — these tests
/// flush it out at CI time.
void main() {
  group('aiAgentTools — top-level shape', () {
    test('exposes exactly the 5 expected tools', () {
      final names = aiAgentTools.map((t) => t['name']).toSet();
      expect(names, {
        'get_sensor_data',
        'get_devices',
        'control_device',
        'get_automations',
        'set_mood',
      });
    });

    test('every tool has a name, description, and input_schema', () {
      for (final tool in aiAgentTools) {
        expect(tool['name'], isA<String>());
        expect((tool['name'] as String).isNotEmpty, isTrue);
        expect(tool['description'], isA<String>());
        expect((tool['description'] as String).isNotEmpty, isTrue);
        expect(tool['input_schema'], isA<Map>());
      }
    });
  });

  group('aiAgentTools — control_device action enum', () {
    Map<String, dynamic> _controlDevice() =>
        aiAgentTools.firstWhere((t) => t['name'] == 'control_device');

    test('lists every property the UI can dispatch', () {
      final actionEnum =
          ((_controlDevice()['input_schema'] as Map)['properties']
                  as Map)['action']['enum'] as List;
      // Must include the legacy props and the AC/oven additions — these
      // pair up with device_control_screen.dart card handlers.
      const expected = {
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
      };
      expect(actionEnum.toSet(), expected);
    });

    test('required fields are device_id, action, value', () {
      final required = (_controlDevice()['input_schema'] as Map)['required']
          as List;
      expect(required.toSet(), {'device_id', 'action', 'value'});
    });

    test('description spells out AC and Oven property lists', () {
      final desc = _controlDevice()['description'] as String;
      // Keep the AI grounded — these substrings are the contract.
      expect(desc, contains('Air Conditioner'));
      expect(desc, contains('target_temp'));
      expect(desc, contains('fan_speed'));
      expect(desc, contains('Oven'));
      expect(desc, contains('timer'));
    });

    test('value description spells out every enum value mapping', () {
      final valueDesc = ((_controlDevice()['input_schema'] as Map)['properties']
              as Map)['value']['description'] as String;
      // AC modes
      for (final m in ['cool', 'heat', 'auto', 'fan', 'dry']) {
        expect(valueDesc, contains(m), reason: 'AC mode "$m" missing');
      }
      // Oven modes
      for (final m in ['bake', 'broil', 'defrost']) {
        expect(valueDesc, contains(m), reason: 'Oven mode "$m" missing');
      }
      // Fan speeds
      for (final s in ['low', 'mid', 'high']) {
        expect(valueDesc, contains(s), reason: 'Fan speed "$s" missing');
      }
    });
  });

  group('aiAgentTools — set_mood', () {
    test('mood enum matches the moods Emotion Hub recognizes', () {
      final moodTool = aiAgentTools.firstWhere((t) => t['name'] == 'set_mood');
      final moodEnum = ((moodTool['input_schema'] as Map)['properties']
              as Map)['mood']['enum'] as List;
      expect(moodEnum.toSet(), {
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
      });
    });

    test('required fields are mood and confidence', () {
      final moodTool = aiAgentTools.firstWhere((t) => t['name'] == 'set_mood');
      final required =
          (moodTool['input_schema'] as Map)['required'] as List;
      expect(required.toSet(), {'mood', 'confidence'});
    });
  });

  group('AiAgentService — config gate', () {
    test('isConfigured is false in unit-test runs (no --dart-define key)', () {
      // No CLAUDE_API_KEY is injected when running `flutter test` — so the
      // service must report unconfigured rather than throw.
      expect(AiAgentService.isConfigured, isFalse);
    });

    test('chat() short-circuits with a friendly message when unconfigured',
        () async {
      final result = await AiAgentService.chat(
        messages: const [],
        homeId: 'irrelevant',
      );
      expect(result, contains('API key is not configured'));
    });
  });
}
