import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../providers/home_provider.dart';
import '../../services/api_service.dart';

class AutomationCreateScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existingData;

  const AutomationCreateScreen({super.key, this.existingData});

  @override
  ConsumerState<AutomationCreateScreen> createState() => _AutomationCreateScreenState();
}

class _AutomationCreateScreenState extends ConsumerState<AutomationCreateScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _isActive = true;
  bool _isSaving = false;

  // Trigger State
  String _triggerType = 'ai'; // 'ai' or 'sensor'
  String _selectedEmotion = 'happy'; // 'happy', 'sad', 'angry', 'neutral'
  
  // Sensor State
  String _sensorType = 'temperature';
  String _sensorOperator = '>=';
  final TextEditingController _sensorValueController = TextEditingController();

  // Action State (MVP: List of predefined devices to pick from)
  List<dynamic> _availableDevices = [];
  final List<Map<String, dynamic>> _addedActions = [];

  @override
  void initState() {
    super.initState();
    _fetchDevices();
    
    if (widget.existingData != null) {
      _nameController.text = widget.existingData!['rule_name'] ?? '';
      _isActive = widget.existingData!['is_enabled'] ?? true;
      String condition = widget.existingData!['trigger_condition'] ?? '';
      
      if (condition.contains('emotion')) {
        _triggerType = 'ai';
        if (condition.contains('sad')) {
          _selectedEmotion = 'sad';
        } else if (condition.contains('angry')) {
          _selectedEmotion = 'angry';
        } else if (condition.contains('neutral')) {
          _selectedEmotion = 'neutral';
        } else {
          _selectedEmotion = 'happy';
        }
      } else {
        _triggerType = 'sensor';
        // Basic parser for 'temperature >= 28'
        final parts = condition.split(' ');
        if (parts.length >= 3) {
          _sensorType = parts[0];
          _sensorOperator = parts[1];
          _sensorValueController.text = parts.sublist(2).join(' ').replaceAll("'", "");
        }
      }
      
      // Load action MVP
      if (widget.existingData!['actions'] != null) {
        for (var action in widget.existingData!['actions']) {
          var details = action['details'] ?? {};
          _addedActions.add({
             'device_id': action['device_id']?.toString() ?? '',
             'device_name': action['device_name']?.toString() ?? 'Unknown Device',
             'device_type': 'unknown',
             'power': details['power'] == 'on' || details['state'] == 'on',
             'brightness': num.tryParse(details['brightness']?.toString() ?? '') ?? 80,
             'color': details['color']?.toString() ?? '#FFFFFF',
             'volume': num.tryParse(details['volume']?.toString() ?? '') ?? 50,
             'playback': details['playback']?.toString() ?? 'play',
             'channel': num.tryParse(details['channel']?.toString() ?? '') ?? 1,
          });
        }
      }
    }
  }

  Future<void> _fetchDevices() async {
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = (selectedHome?['home_id'] ?? selectedHome?['id'] ?? selectedHome?['homeid'])?.toString();
    if (homeId == null) return;
    
    final devs = await ApiService.fetchDevices(homeId);
    if (devs != null && mounted) {
      setState(() {
        _availableDevices = devs;
        // Update device types and names for loaded actions
        for (var i = 0; i < _addedActions.length; i++) {
          final matched = devs.where((d) => d['deviceid'].toString() == _addedActions[i]['device_id'].toString()).toList();
          if (matched.isNotEmpty) {
             _addedActions[i]['device_type'] = matched.first['device_type']?.toString().toLowerCase() ?? 'unknown';
             _addedActions[i]['device_name'] = matched.first['device_name']?.toString() ?? 'Device';
          }
        }
      });
    }
  }



  Future<void> _saveAutomation() async {
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = (selectedHome?['home_id'] ?? selectedHome?['id'] ?? selectedHome?['homeid'])?.toString();
    
    if (homeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Home ID not found.', style: TextStyle(color: Colors.white)), backgroundColor: AppColors.cardDark));
      return;
    }

    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter an automation name.', style: TextStyle(color: Colors.white)), backgroundColor: AppColors.accentOrange));
      return;
    }

    if (_addedActions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add at least one device action.', style: TextStyle(color: Colors.white)), backgroundColor: AppColors.accentOrange));
      return;
    }

    String triggerCondition = "";
    if (_triggerType == 'ai') {
      triggerCondition = "emotion == '$_selectedEmotion'";
    } else {
      String val = _sensorValueController.text.trim();
      if (val.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a value for the sensor.', style: TextStyle(color: Colors.white)), backgroundColor: AppColors.accentOrange));
        return;
      }
      triggerCondition = "$_sensorType $_sensorOperator $val";
    }

    setState(() { _isSaving = true; });

    List<Map<String, dynamic>> actions = _addedActions.map((act) {
       Map<String, dynamic> details = <String, dynamic>{
          "power": (act['power'] == true) ? "on" : "off"
       };
       final dtype = act['device_type'].toString();
       final dname = act['device_name'].toString().toLowerCase();
       bool isLed = dtype == 'led' || dtype == 'light' || dtype == 'smartbulb' || dname.contains('led') || dname.contains('light');
       bool isSpk = dtype == 'speaker' || dtype == 'audio' || dname.contains('speaker');
       bool isTv = dtype == 'tv' || dname.contains('tv');

       if (isLed) {
          details["brightness"] = (num.tryParse(act['brightness']?.toString() ?? '') ?? 80).toInt();
          details["color"] = act["color"]?.toString() ?? '#FFFFFF';
       } else if (isSpk) {
          details["volume"] = (num.tryParse(act['volume']?.toString() ?? '') ?? 50).toInt();
          details["playback"] = act["playback"]?.toString() ?? 'play';
       } else if (isTv) {
          details["volume"] = (num.tryParse(act['volume']?.toString() ?? '') ?? 30).toInt();
          details["channel"] = (num.tryParse(act['channel']?.toString() ?? '') ?? 1).toInt();
       }
       return {
          "device_id": act['device_id'],
          "details": details
       };
    }).toList();

    Map<String, dynamic> payload = {
      "rule_name": _nameController.text.trim(),
      "trigger_condition": triggerCondition,
      "is_enabled": _isActive,
      "actions": actions
    };
    
    if (widget.existingData != null && widget.existingData!['rule_id'] != null) {
      payload['rule_id'] = widget.existingData!['rule_id'];
    }

    bool success = await ApiService.saveAutomation(homeId, payload);
    
    if (mounted) {
      setState(() { _isSaving = false; });
      if (success) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Automation saved successfully!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: AppColors.accentGreen));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('An error occurred while saving.', style: TextStyle(color: Colors.white)), backgroundColor: AppColors.accentRed));
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sensorValueController.dispose();
    super.dispose();
  }

  /// Pre-fill the form from a preset. The user can still tweak everything
  /// before saving — presets are a starting point, not a one-tap save.
  void _applyPreset(_AutomationPreset p) {
    HapticFeedback.lightImpact();
    setState(() {
      _nameController.text = p.name;
      _triggerType = p.triggerType;
      if (p.triggerType == 'ai') {
        _selectedEmotion = p.emotion ?? 'happy';
      } else {
        _sensorType = p.sensorType ?? 'temperature';
        _sensorOperator = p.sensorOperator ?? '>=';
        _sensorValueController.text = p.sensorValue ?? '28';
      }
      // Don't auto-add device actions — the user picks targets by name
      // since device IDs vary per home. We only seed the trigger side.
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Filled "${p.name}". Add target devices below.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Soft, theme-aware card. Replaces the old _buildGlassCard which
  // hard-coded a dark background — that broke light mode and made the
  // whole screen feel chunky on small phones.
  Widget _softCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderCol(context)),
      ),
      child: child,
    );
  }

  // Compact section header — replaces the big circle-icon-plus-bold-title
  // pattern that made every section feel like its own page.
  Widget _sectionLabel(String text, IconData icon, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 14),
          const SizedBox(width: 6),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: AppColors.textSub(context),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text(
          widget.existingData != null ? 'Edit Automation' : 'New Automation',
          style: TextStyle(
            color: AppColors.text(context),
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppColors.text(context)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Switch.adaptive(
              value: _isActive,
              activeThumbColor: AppColors.accentGreen,
              onChanged: (val) => setState(() => _isActive = val),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Suggestion strip — only on the new (no existingData) path,
            // so the editing flow stays focused on the existing rule.
            if (widget.existingData == null) ...[
              _sectionLabel('Suggested', Icons.auto_awesome,
                  AppColors.accentGreen),
              const SizedBox(height: 6),
              _SuggestedRow(onPick: _applyPreset),
              const SizedBox(height: 18),
            ],
            _sectionLabel('Name', Icons.label_important_outline,
                AppColors.textSub(context)),
            const SizedBox(height: 6),
            _softCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: TextField(
                controller: _nameController,
                style: TextStyle(
                  color: AppColors.text(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                cursorColor: AppColors.primaryBlue,
                decoration: InputDecoration(
                  hintText: 'e.g. Night Mode',
                  hintStyle: TextStyle(
                    color: AppColors.textSub(context).withValues(alpha: 0.7),
                    fontWeight: FontWeight.normal,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 18),

            _sectionLabel('When', Icons.bolt, AppColors.accentOrange),
            const SizedBox(height: 6),
            _softCard(
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  _SegBtn(
                    label: 'Emotion',
                    icon: Icons.sentiment_satisfied_alt,
                    active: _triggerType == 'ai',
                    onTap: () => setState(() => _triggerType = 'ai'),
                  ),
                  _SegBtn(
                    label: 'Sensor',
                    icon: Icons.sensors,
                    active: _triggerType == 'sensor',
                    onTap: () => setState(() => _triggerType = 'sensor'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: _triggerType == 'ai' ? _buildEmotionGrid() : _buildSensorInputs(),
            ),

            const SizedBox(height: 22),

            _sectionLabel('Then', Icons.play_arrow_rounded, AppColors.primaryBlue),
            const SizedBox(height: 6),
            _buildActionCard(),

            const SizedBox(height: 26),

            _SaveButton(isSaving: _isSaving, onTap: _saveAutomation),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildEmotionGrid() {
    final emotions = [
      {'id': 'angry', 'label': 'Angry', 'icon': '😠', 'color': Colors.redAccent},
      {'id': 'disgust', 'label': 'Disgust', 'icon': '🤢', 'color': Colors.green},
      {'id': 'fear', 'label': 'Fear', 'icon': '😨', 'color': Colors.deepPurple},
      {'id': 'happy', 'label': 'Happy', 'icon': '😊', 'color': Colors.amber},
      {'id': 'neutral', 'label': 'Neutral', 'icon': '😐', 'color': Colors.teal},
      {'id': 'sad', 'label': 'Sad', 'icon': '😢', 'color': Colors.blueGrey},
      {'id': 'surprise', 'label': 'Surprise', 'icon': '😲', 'color': Colors.orangeAccent},
    ];

    return GridView.builder(
      key: const ValueKey('emotion_grid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.92,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: emotions.length,
      itemBuilder: (context, index) {
        final emo = emotions[index];
        final isSelected = _selectedEmotion == emo['id'];
        final baseColor = emo['color'] as Color;

        return GestureDetector(
          onTap: () => setState(() => _selectedEmotion = emo['id'] as String),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isSelected
                  ? baseColor.withValues(alpha: 0.15)
                  : AppColors.card(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? baseColor
                    : AppColors.borderCol(context),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  emo['icon'] as String,
                  style: TextStyle(fontSize: isSelected ? 26 : 22),
                ),
                const SizedBox(height: 4),
                Text(
                  emo['label'] as String,
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.text(context)
                        : AppColors.textSub(context),
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSensorInputs() {
    Widget pillField({required Widget child, EdgeInsets? padding}) => Container(
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderCol(context)),
          ),
          child: child,
        );

    return Column(
      key: const ValueKey('sensor_inputs'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            'SENSOR',
            style: TextStyle(
              color: AppColors.textSub(context),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
        pillField(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: AppColors.card(context),
              value: _sensorType,
              icon: Icon(Icons.expand_more,
                  color: AppColors.textSub(context), size: 18),
              style: TextStyle(
                color: AppColors.text(context),
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
              items: const [
                DropdownMenuItem(
                    value: 'temperature', child: Text('Temperature (°C)')),
                DropdownMenuItem(
                    value: 'humidity', child: Text('Humidity (%)')),
                DropdownMenuItem(
                    value: 'gas_level', child: Text('Gas / Air Quality')),
              ],
              onChanged: (val) => setState(() => _sensorType = val!),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            'CONDITION',
            style: TextStyle(
              color: AppColors.textSub(context),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: pillField(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    dropdownColor: AppColors.card(context),
                    value: _sensorOperator,
                    icon: Icon(Icons.expand_more,
                        color: AppColors.textSub(context), size: 18),
                    style: TextStyle(
                      color: AppColors.text(context),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                    items: const [
                      DropdownMenuItem(value: '>=', child: Text('≥ (greater)')),
                      DropdownMenuItem(value: '<=', child: Text('≤ (less)')),
                      DropdownMenuItem(value: '==', child: Text('= (equal)')),
                    ],
                    onChanged: (val) => setState(() => _sensorOperator = val!),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: pillField(
                padding: EdgeInsets.zero,
                child: TextField(
                  controller: _sensorValueController,
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: '28',
                    hintStyle: TextStyle(
                      color: AppColors.textSub(context).withValues(alpha: 0.6),
                      fontWeight: FontWeight.normal,
                    ),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard() {
    return Column(
      children: [
        if (_addedActions.isNotEmpty)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _addedActions.length,
            itemBuilder: (context, index) => _buildDeviceActionCard(index),
          ),
        const SizedBox(height: 10),
        InkWell(
          onTap: _showAddDeviceModal,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.4),
              ),
              borderRadius: BorderRadius.circular(12),
              color: AppColors.primaryBlue.withValues(alpha: 0.05),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_circle_outline,
                    color: AppColors.primaryBlue, size: 16),
                const SizedBox(width: 6),
                Text(
                  _addedActions.isEmpty
                      ? 'Add target device'
                      : 'Add another device',
                  style: const TextStyle(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showAddDeviceModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textSub(ctx).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                "Select Device",
                style: TextStyle(
                  color: AppColors.text(ctx),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final unaddedDevices = _availableDevices.where((d) {
                       bool isAlreadyAdded = _addedActions.any((a) => a['device_id'].toString() == d['deviceid'].toString());
                       String dType = (d['device_type'] ?? '').toString().toLowerCase();
                       bool isSensor = dType.contains('sensor') || dType.contains('temperature') || dType.contains('humidity') || dType.contains('vibration');
                       return !isAlreadyAdded && !isSensor;
                    }).toList();

                    if (_availableDevices.isEmpty) {
                      return Center(
                        child: Text("No devices found.",
                            style: TextStyle(color: AppColors.textSub(ctx))),
                      );
                    } else if (unaddedDevices.isEmpty) {
                      return Center(
                        child: Text("All devices are already added.",
                            style: TextStyle(color: AppColors.textSub(ctx))),
                      );
                    }

                    return ListView.builder(
                      itemCount: unaddedDevices.length,
                      itemBuilder: (context, index) {
                        final dev = unaddedDevices[index];
                        return ListTile(
                          title: Text(
                            dev['device_name'].toString(),
                            style: TextStyle(color: AppColors.text(ctx)),
                          ),
                          subtitle: Text(
                            dev['device_type'].toString(),
                            style: TextStyle(color: AppColors.textSub(ctx)),
                          ),
                          trailing: const Icon(Icons.add, color: AppColors.primaryBlue),
                          onTap: () {
                            setState(() {
                               _addedActions.add({
                                  'device_id': dev['deviceid'].toString(),
                                  'device_name': dev['device_name'].toString(),
                                  'device_type': dev['device_type'].toString().toLowerCase(),
                                  'power': true,
                                  'brightness': 80,
                                  'color': '#FFFFFF',
                                  'volume': 50,
                                  'playback': 'play',
                                  'channel': 1,
                               });
                            });
                            Navigator.pop(context);
                          },
                        );
                      },
                    );
                  }
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDeviceActionCard(int index) {
    final act = _addedActions[index];
    final dtype = act['device_type'].toString();
    final dname = act['device_name'].toString().toLowerCase();
    bool isLed = dtype == 'led' || dtype == 'light' || dtype == 'smartbulb' || dname.contains('led') || dname.contains('light');
    bool isSpk = dtype == 'speaker' || dtype == 'audio' || dname.contains('speaker');
    bool isTv = dtype == 'tv' || dname.contains('tv');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderCol(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isLed ? Icons.lightbulb : isSpk ? Icons.speaker : isTv ? Icons.tv : Icons.devices_other,
                  color: AppColors.primaryBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  act['device_name'].toString(),
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              Switch.adaptive(
                value: act['power'] as bool,
                activeThumbColor: AppColors.primaryBlue,
                onChanged: (val) {
                  setState(() { _addedActions[index]['power'] = val; });
                },
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    color: AppColors.accentRed, size: 20),
                onPressed: () {
                  setState(() { _addedActions.removeAt(index); });
                },
              )
            ],
          ),
          if (isLed) ...[
            const SizedBox(height: 12),
            _buildHueSpectrum(index, act['color']?.toString() ?? '#FFFFFF'),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.brightness_low,
                    color: AppColors.textSub(context), size: 16),
                Expanded(
                  child: Slider(
                    value: (act['brightness'] as num).toDouble(),
                    min: 0,
                    max: 100,
                    activeColor: AppColors.primaryBlue,
                    onChanged: (val) => setState(() { _addedActions[index]['brightness'] = val.toInt(); }),
                  ),
                ),
                Icon(Icons.brightness_high,
                    color: AppColors.textSub(context), size: 16),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(act['brightness'] as num).toInt()}%',
                    style: TextStyle(
                      color: AppColors.textSub(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ] else if (isSpk) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildPlaybackButton(index, Icons.play_arrow, 'play'),
                _buildPlaybackButton(index, Icons.pause, 'pause'),
                _buildPlaybackButton(index, Icons.stop, 'stop'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.volume_down,
                    color: AppColors.textSub(context), size: 16),
                Expanded(
                  child: Slider(
                    value: (act['volume'] as num).toDouble(),
                    min: 0,
                    max: 100,
                    activeColor: Colors.pinkAccent,
                    onChanged: (val) => setState(() { _addedActions[index]['volume'] = val.toInt(); }),
                  ),
                ),
                Icon(Icons.volume_up,
                    color: AppColors.textSub(context), size: 16),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(act['volume'] as num).toInt()}%',
                    style: TextStyle(
                      color: AppColors.textSub(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ] else if (isTv) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildChannelButton(index, Icons.keyboard_arrow_down, -1),
                Column(
                  children: [
                    Text(
                      "Channel",
                      style: TextStyle(
                        color: AppColors.textSub(context),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${(act['channel'] as num).toInt()}",
                      style: TextStyle(
                        color: AppColors.text(context),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                _buildChannelButton(index, Icons.keyboard_arrow_up, 1),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.volume_down,
                    color: AppColors.textSub(context), size: 16),
                Expanded(
                  child: Slider(
                    value: (act['volume'] as num).toDouble(),
                    min: 0,
                    max: 100,
                    activeColor: AppColors.primaryBlue,
                    onChanged: (val) => setState(() { _addedActions[index]['volume'] = val.toInt(); }),
                  ),
                ),
                Icon(Icons.volume_up,
                    color: AppColors.textSub(context), size: 16),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(act['volume'] as num).toInt()}%',
                    style: TextStyle(
                      color: AppColors.textSub(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ]
        ],
      ),
    );
  }

  // ── Color helpers (mirror device_control_screen) ──────────────────

  Color _parseHex(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length != 6) return Colors.white;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return Colors.white;
    return Color(0xFF000000 | v);
  }

  String _hexFromColor(Color c) {
    final argb = c.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    String two(int n) => n.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '#${two(r)}${two(g)}${two(b)}';
  }

  /// Returns hue 0..360. For grayscale (R==G==B) returns -1, meaning "white".
  double _hueFromHex(String hex) {
    final c = _parseHex(hex);
    final argb = c.toARGB32();
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    if (r == g && g == b) return -1;
    return HSVColor.fromColor(Color.fromARGB(255, r, g, b)).hue;
  }

  void _onHuePicked(int index, double dx, double width) {
    final t = (dx / width).clamp(0.0, 1.0);
    final hue = t * 360.0;
    final color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
    setState(() => _addedActions[index]['color'] = _hexFromColor(color));
  }

  Widget _buildHueSpectrum(int index, String currentHex) {
    final isWhite = _hueFromHex(currentHex) < 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        const whitePillWidth = 44.0;
        const gap = 12.0;
        final barWidth = constraints.maxWidth - whitePillWidth - gap;
        final hue = _hueFromHex(currentHex);
        final indicatorX = hue < 0 ? -1.0 : (hue / 360.0) * barWidth;

        return Row(
          children: [
            SizedBox(
              width: barWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _onHuePicked(index, d.localPosition.dx, barWidth),
                onPanDown: (d) => _onHuePicked(index, d.localPosition.dx, barWidth),
                onPanUpdate: (d) => _onHuePicked(index, d.localPosition.dx, barWidth),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 28,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFFF0000),
                            Color(0xFFFFFF00),
                            Color(0xFF00FF00),
                            Color(0xFF00FFFF),
                            Color(0xFF0000FF),
                            Color(0xFFFF00FF),
                            Color(0xFFFF0000),
                          ],
                        ),
                        border: Border.all(
                            color: AppColors.borderCol(context), width: 1),
                      ),
                    ),
                    if (indicatorX >= 0)
                      Positioned(
                        left: (indicatorX - 8).clamp(0.0, barWidth - 16),
                        child: Container(
                          width: 16,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            border: Border.all(
                                color: AppColors.text(context), width: 3),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: gap),
            GestureDetector(
              onTap: () => setState(() => _addedActions[index]['color'] = '#FFFFFF'),
              child: Container(
                width: whitePillWidth,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isWhite ? AppColors.primaryBlue : Colors.white.withValues(alpha: 0.1),
                    width: isWhite ? 2.5 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  'W',
                  style: TextStyle(
                    color: isWhite ? AppColors.primaryBlue : Colors.grey.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChannelButton(int index, IconData icon, int delta) {
    return GestureDetector(
      onTap: () {
        final cur = (_addedActions[index]['channel'] as num).toInt();
        final next = (cur + delta).clamp(1, 999);
        setState(() => _addedActions[index]['channel'] = next);
      },
      child: Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          color: AppColors.bg(context),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.borderCol(context)),
        ),
        child: Icon(icon, color: AppColors.text(context), size: 24),
      ),
    );
  }

  Widget _buildPlaybackButton(int index, IconData icon, String action) {
    bool isSelected = _addedActions[index]['playback'] == action;
    return GestureDetector(
      onTap: () => setState(() { _addedActions[index]['playback'] = action; }),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.pinkAccent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.pinkAccent) : null,
        ),
        child: Icon(icon, color: isSelected ? Colors.pinkAccent : Colors.grey, size: 20),
      ),
    );
  }
}

/// Compact 2-segment toggle used for the trigger-type picker
/// (Emotion / Sensor). Replaces the heavier blue-pill row that took
/// up a full glass card.
class _SegBtn extends StatelessWidget {
  const _SegBtn({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    colors: [Color(0xFF2196F3), Color(0xFF00BFA5)])
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: active
                    ? Colors.white
                    : AppColors.textSub(context),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: active
                      ? Colors.white
                      : AppColors.textSub(context),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slim, gradient save button for the bottom of the create form.
/// Replaces the 56px-tall solid-orange ElevatedButton that felt heavy.
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.isSaving, required this.onTap});
  final bool isSaving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isSaving ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2196F3), Color(0xFF00BFA5)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline,
                            color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Save automation',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One suggested automation. Only carries enough to seed the form
/// (name + trigger), not target devices — those vary per home so the
/// user picks them after applying the preset.
class _AutomationPreset {
  const _AutomationPreset({
    required this.name,
    required this.icon,
    required this.color,
    required this.subtitle,
    required this.triggerType,
    this.emotion,
    this.sensorType,
    this.sensorOperator,
    this.sensorValue,
  });

  final String name;
  final IconData icon;
  final Color color;
  final String subtitle;
  final String triggerType; // 'ai' | 'sensor'
  final String? emotion;
  final String? sensorType;
  final String? sensorOperator;
  final String? sensorValue;
}

/// Horizontal scroll of suggested presets at the top of the create form.
/// Tap to seed the rest of the form with sensible defaults.
class _SuggestedRow extends StatelessWidget {
  const _SuggestedRow({required this.onPick});

  final void Function(_AutomationPreset p) onPick;

  static final List<_AutomationPreset> _presets = [
    const _AutomationPreset(
      name: 'Cheer me up',
      icon: Icons.sentiment_dissatisfied,
      color: Color(0xFF7E8DAA),
      subtitle: 'When I feel sad',
      triggerType: 'ai',
      emotion: 'sad',
    ),
    const _AutomationPreset(
      name: 'Calm me down',
      icon: Icons.local_fire_department,
      color: Colors.redAccent,
      subtitle: 'When I get angry',
      triggerType: 'ai',
      emotion: 'angry',
    ),
    const _AutomationPreset(
      name: 'Cool the room',
      icon: Icons.ac_unit,
      color: Color(0xFF4FC3F7),
      subtitle: 'Temperature ≥ 28°C',
      triggerType: 'sensor',
      sensorType: 'temperature',
      sensorOperator: '>=',
      sensorValue: '28',
    ),
    const _AutomationPreset(
      name: 'Dehumidify',
      icon: Icons.water_drop,
      color: Color(0xFF26A69A),
      subtitle: 'Humidity ≥ 70%',
      triggerType: 'sensor',
      sensorType: 'humidity',
      sensorOperator: '>=',
      sensorValue: '70',
    ),
    const _AutomationPreset(
      name: 'Air alert',
      icon: Icons.warning_amber_rounded,
      color: Color(0xFFFFA726),
      subtitle: 'Gas / air quality drops',
      triggerType: 'sensor',
      sensorType: 'gas_level',
      sensorOperator: '>=',
      sensorValue: '50',
    ),
    const _AutomationPreset(
      name: 'Party time',
      icon: Icons.celebration,
      color: Color(0xFFE040FB),
      subtitle: 'When I feel happy',
      triggerType: 'ai',
      emotion: 'happy',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: _presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = _presets[i];
          return InkWell(
            onTap: () => onPick(p),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 160,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: p.color.withValues(alpha: 0.4),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.card(context),
                    Color.alphaBlend(
                      p.color.withValues(alpha: 0.10),
                      AppColors.card(context),
                    ),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: p.color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(p.icon, color: p.color, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.text(context),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textSub(context),
                            fontSize: 10.5,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
