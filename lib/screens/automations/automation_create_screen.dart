import 'dart:ui';
import 'package:flutter/material.dart';
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
  String? _selectedDeviceId;
  bool _actionPower = true;
  double _actionBrightness = 80;

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
        if (condition.contains('sad')) _selectedEmotion = 'sad';
        else if (condition.contains('angry')) _selectedEmotion = 'angry';
        else if (condition.contains('neutral')) _selectedEmotion = 'neutral';
        else _selectedEmotion = 'happy';
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
      if (widget.existingData!['actions'] != null && widget.existingData!['actions'].isNotEmpty) {
        var firstAction = widget.existingData!['actions'][0];
        _selectedDeviceId = firstAction['deviceID']?.toString();
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
      });
    }
  }

  Map<String, dynamic>? get _selectedDevice {
    if (_selectedDeviceId == null || _availableDevices.isEmpty) return null;
    try {
      return _availableDevices.firstWhere((dev) => dev['deviceid'].toString() == _selectedDeviceId);
    } catch (_) {
      return null;
    }
  }

  String get _deviceType {
    return _selectedDevice?['device_type']?.toString().toLowerCase() ?? '';
  }
  
  String get _deviceName {
    return _selectedDevice?['device_name']?.toString().toLowerCase() ?? '';
  }

  bool get _isLed => _deviceType == 'led' || _deviceType == 'light' || _deviceType == 'smartbulb' || _deviceName.contains('led') || _deviceName.contains('light');
  bool get _isSpeaker => _deviceType == 'speaker' || _deviceType == 'audio' || _deviceName.contains('speaker');
  bool get _isBlinds => _deviceType == 'blinds' || _deviceType == 'curtain' || _deviceName.contains('blind');

  // Action states for specific devices
  String _actionColor = '#FFFFFF';
  int _actionVolume = 50;
  String _actionPlayback = 'play';
  int _actionPosition = 100;

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

    if (_selectedDeviceId == null && widget.existingData == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a target device.', style: TextStyle(color: Colors.white)), backgroundColor: AppColors.accentOrange));
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

    List<Map<String, dynamic>> actions = [
      {
        "device_id": _selectedDeviceId ?? 'unknown-device',
        "details": <String, dynamic>{
          "state": _actionPower ? "on" : "off"
        }
      }
    ];

    if (_isLed) {
      actions[0]["details"]["brightness"] = _actionBrightness.toInt();
      actions[0]["details"]["color"] = _actionColor;
    } else if (_isSpeaker) {
      actions[0]["details"]["volume"] = _actionVolume.toInt();
      actions[0]["details"]["playback"] = _actionPlayback;
    } else if (_isBlinds) {
      actions[0]["details"]["position"] = _actionPosition.toInt();
    }

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

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Automation Settings", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Row(
            children: [
              Text(_isActive ? "ACTIVE" : "INACTIVE", style: TextStyle(color: _isActive ? AppColors.accentGreen : Colors.white54, fontSize: 13, fontWeight: FontWeight.w800)),
              Switch(
                value: _isActive,
                activeColor: AppColors.accentGreen,
                inactiveThumbColor: Colors.grey,
                inactiveTrackColor: Colors.white12,
                onChanged: (val) => setState(() => _isActive = val),
              ),
              const SizedBox(width: 12),
            ],
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                cursorColor: AppColors.primaryBlue,
                decoration: const InputDecoration(
                  hintText: 'Otomasyon Adı (Örn: Gece Modu)',
                  hintStyle: TextStyle(color: Colors.white30, fontWeight: FontWeight.normal),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accentOrange.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bolt, color: AppColors.accentOrange, size: 22),
                ),
                const SizedBox(width: 16),
                const Text("Trigger (IF)", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            
            const SizedBox(height: 16),
            
            _buildGlassCard(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _triggerType = 'ai'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _triggerType == 'ai' ? AppColors.primaryBlue : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text("Yapay Zeka (Duygu)", style: TextStyle(color: _triggerType == 'ai' ? Colors.white : Colors.white54, fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _triggerType = 'sensor'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _triggerType == 'sensor' ? AppColors.primaryBlue : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text("Sensor Data", style: TextStyle(color: _triggerType == 'sensor' ? Colors.white : Colors.white54, fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _triggerType == 'ai' ? _buildEmotionGrid() : _buildSensorInputs(),
            ),
            
            const SizedBox(height: 40),

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: AppColors.primaryBlue, size: 24),
                ),
                const SizedBox(width: 16),
                const Text("Aksiyon (O ZAMAN)", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            
            const SizedBox(height: 16),
            _buildActionCard(),

            const SizedBox(height: 48),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isSaving ? null : _saveAutomation,
                child: _isSaving
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("Otomasyonu Kaydet", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildEmotionGrid() {
    final emotions = [
      {'id': 'happy', 'label': 'Happy', 'icon': '😊', 'color': Colors.amber},
      {'id': 'sad', 'label': 'Sad', 'icon': '😢', 'color': Colors.blueGrey},
      {'id': 'angry', 'label': 'Angry', 'icon': '😠', 'color': Colors.redAccent},
      {'id': 'neutral', 'label': 'Neutral', 'icon': '😐', 'color': Colors.teal},
    ];

    return _buildGlassCard(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: emotions.length,
        itemBuilder: (context, index) {
          final emo = emotions[index];
          bool isSelected = _selectedEmotion == emo['id'];
          Color baseColor = emo['color'] as Color;
          
          return GestureDetector(
            onTap: () => setState(() => _selectedEmotion = emo['id'] as String),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isSelected ? baseColor.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isSelected ? baseColor : Colors.transparent, width: 2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(emo['icon'] as String, style: TextStyle(fontSize: isSelected ? 36 : 30)),
                  const SizedBox(height: 8),
                  Text(emo['label'] as String, style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSensorInputs() {
    return _buildGlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Sensor Selection", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                dropdownColor: AppColors.cardDark,
                value: _sensorType,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                items: const [
                  DropdownMenuItem(value: 'temperature', child: Text('Temperature (°C)')),
                  DropdownMenuItem(value: 'humidity', child: Text('Humidity (%)')),
                  DropdownMenuItem(value: 'gas_level', child: Text('Gas / Air Quality')),
                ],
                onChanged: (val) => setState(() => _sensorType = val!),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text("Condition & Value", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      dropdownColor: AppColors.cardDark,
                      value: _sensorOperator,
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                      items: const [
                        DropdownMenuItem(value: '>=', child: Text('Greater than (>=)')),
                        DropdownMenuItem(value: '<=', child: Text('Less than (<=)')),
                        DropdownMenuItem(value: '==', child: Text('Equal to (==)')),
                      ],
                      onChanged: (val) => setState(() => _sensorOperator = val!),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
                  child: TextField(
                    controller: _sensorValueController,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      hintText: '28',
                      hintStyle: TextStyle(color: Colors.white30, fontWeight: FontWeight.normal),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard() {
    return _buildGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.devices_other, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Hedef Cihaz", style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 4),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        isDense: true,
                        dropdownColor: AppColors.cardDark,
                        hint: const Text('Select Device', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        value: _selectedDeviceId,
                        icon: const Icon(Icons.expand_more, color: Colors.white),
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        items: _availableDevices.map((dev) {
                          return DropdownMenuItem<String>(
                            value: dev['deviceid'].toString(),
                            child: Text(dev['device_name'].toString(), overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) {
                           setState(() {
                             _selectedDeviceId = val;
                             // Reset state to defaults on change
                             _actionPower = true;
                             _actionColor = '#FFFFFF';
                             _actionBrightness = 80;
                             _actionVolume = 50;
                             _actionPlayback = 'play';
                             _actionPosition = 100;
                           });
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _actionPower,
                activeColor: AppColors.primaryBlue,
                onChanged: (val) => setState(() => _actionPower = val),
              ),
            ],
          ),
          
          if (_selectedDeviceId != null) ...[
            if (_isLed) ...[
              const SizedBox(height: 24),
              Divider(color: Colors.white.withOpacity(0.05), height: 1),
              const SizedBox(height: 16),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildColorSelector(Colors.redAccent, '#FF0000'),
                  _buildColorSelector(Colors.greenAccent, '#00FF00'),
                  _buildColorSelector(Colors.blueAccent, '#0000FF'),
                  _buildColorSelector(Colors.white, '#FFFFFF'),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.brightness_low, color: Colors.grey, size: 20),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(trackHeight: 4, activeTrackColor: AppColors.primaryBlue, thumbColor: AppColors.primaryBlue),
                      child: Slider(
                        value: _actionBrightness,
                        min: 0,
                        max: 100,
                        onChanged: (val) => setState(() => _actionBrightness = val),
                      ),
                    ),
                  ),
                  const Icon(Icons.brightness_high, color: Colors.grey, size: 20),
                ],
              ),
            ] else if (_isSpeaker) ...[
              const SizedBox(height: 24),
              Divider(color: Colors.white.withOpacity(0.05), height: 1),
              const SizedBox(height: 16),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPlaybackButton(Icons.play_arrow, 'play'),
                  _buildPlaybackButton(Icons.pause, 'pause'),
                  _buildPlaybackButton(Icons.stop, 'stop'),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.volume_down, color: Colors.grey, size: 20),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(trackHeight: 4, activeTrackColor: Colors.pinkAccent, thumbColor: Colors.pinkAccent),
                      child: Slider(
                        value: _actionVolume.toDouble(),
                        min: 0,
                        max: 100,
                        onChanged: (val) => setState(() => _actionVolume = val.toInt()),
                      ),
                    ),
                  ),
                  const Icon(Icons.volume_up, color: Colors.grey, size: 20),
                ],
              ),
            ] else if (_isBlinds) ...[
              const SizedBox(height: 24),
              Divider(color: Colors.white.withOpacity(0.05), height: 1),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Text("0%", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(trackHeight: 4, activeTrackColor: Colors.cyanAccent, thumbColor: Colors.white),
                      child: Slider(
                        value: _actionPosition.toDouble(),
                        min: 0,
                        max: 100,
                        onChanged: (val) => setState(() => _actionPosition = val.toInt()),
                      ),
                    ),
                  ),
                  Text("100%", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                ],
              ),
            ]
          ]
        ],
      ),
    );
  }

  Widget _buildColorSelector(Color color, String hex) {
    bool isSelected = _actionColor == hex;
    return GestureDetector(
      onTap: () => setState(() => _actionColor = hex),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
          boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)] : [],
        ),
      ),
    );
  }

  Widget _buildPlaybackButton(IconData icon, String action) {
    bool isSelected = _actionPlayback == action;
    return GestureDetector(
      onTap: () => setState(() => _actionPlayback = action),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.pinkAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.pinkAccent) : null,
        ),
        child: Icon(icon, color: isSelected ? Colors.pinkAccent : Colors.grey, size: 24),
      ),
    );
  }
}
