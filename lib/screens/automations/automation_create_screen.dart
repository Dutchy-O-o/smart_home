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
             'position': num.tryParse(details['position']?.toString() ?? '') ?? 100,
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
       bool isBld = dtype == 'blinds' || dtype == 'curtain' || dname.contains('blind');

       if (isLed) {
          details["brightness"] = (num.tryParse(act['brightness']?.toString() ?? '') ?? 80).toInt();
          details["color"] = act["color"]?.toString() ?? '#FFFFFF';
       } else if (isSpk) {
          details["volume"] = (num.tryParse(act['volume']?.toString() ?? '') ?? 50).toInt();
          details["playback"] = act["playback"]?.toString() ?? 'play';
       } else if (isBld) {
          details["position"] = (num.tryParse(act['position']?.toString() ?? '') ?? 100).toInt();
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

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.existingData != null ? 'Edit Automation' : 'New Automation', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                  hintText: 'Automation Name (e.g. Night Mode)',
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
                    color: AppColors.accentOrange.withValues(alpha: 0.2),
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
                    color: AppColors.primaryBlue.withValues(alpha: 0.2),
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
      {'id': 'angry', 'label': 'Angry', 'icon': '😠', 'color': Colors.redAccent},
      {'id': 'disgust', 'label': 'Disgust', 'icon': '🤢', 'color': Colors.green},
      {'id': 'fear', 'label': 'Fear', 'icon': '😨', 'color': Colors.deepPurple},
      {'id': 'happy', 'label': 'Happy', 'icon': '😊', 'color': Colors.amber},
      {'id': 'neutral', 'label': 'Neutral', 'icon': '😐', 'color': Colors.teal},
      {'id': 'sad', 'label': 'Sad', 'icon': '😢', 'color': Colors.blueGrey},
      {'id': 'surprise', 'label': 'Surprise', 'icon': '😲', 'color': Colors.orangeAccent},
    ];

    return _buildGlassCard(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1.1,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
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
                color: isSelected ? baseColor.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
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
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
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
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
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
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
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
    return Column(
      children: [
        if (_addedActions.isNotEmpty)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _addedActions.length,
            itemBuilder: (context, index) {
              return _buildDeviceActionCard(index);
            },
          ),
        const SizedBox(height: 16),
        InkWell(
          onTap: _showAddDeviceModal,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.2), style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(16),
              color: Colors.white.withValues(alpha: 0.02),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_circle_outline, color: AppColors.primaryBlue),
                SizedBox(width: 8),
                Text("Add Target Device", style: TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold, fontSize: 16)),
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
      backgroundColor: AppColors.cardDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              const Text("Select Device", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final unaddedDevices = _availableDevices.where((d) => 
                       !_addedActions.any((a) => a['device_id'].toString() == d['deviceid'].toString())
                    ).toList();
                    
                    if (_availableDevices.isEmpty) {
                      return const Center(child: Text("No devices found.", style: TextStyle(color: Colors.white54)));
                    } else if (unaddedDevices.isEmpty) {
                      return const Center(child: Text("All devices are already added.", style: TextStyle(color: Colors.white54)));
                    }

                    return ListView.builder(
                      itemCount: unaddedDevices.length,
                      itemBuilder: (context, index) {
                        final dev = unaddedDevices[index];
                        return ListTile(
                          title: Text(dev['device_name'].toString(), style: const TextStyle(color: Colors.white)),
                          subtitle: Text(dev['device_type'].toString(), style: const TextStyle(color: Colors.white54)),
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
                                  'position': 100,
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
    bool isBld = dtype == 'blinds' || dtype == 'curtain' || dname.contains('blind');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(isLed ? Icons.lightbulb : isSpk ? Icons.speaker : Icons.blinds, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(act['device_name'].toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Switch(
                value: act['power'] as bool,
                activeColor: AppColors.primaryBlue,
                onChanged: (val) {
                  setState(() { _addedActions[index]['power'] = val; });
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () {
                  setState(() { _addedActions.removeAt(index); });
                },
              )
            ],
          ),
          if (isLed) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildColorSelector(index, Colors.redAccent, '#FF0000'),
                _buildColorSelector(index, Colors.greenAccent, '#00FF00'),
                _buildColorSelector(index, Colors.blueAccent, '#0000FF'),
                _buildColorSelector(index, Colors.white, '#FFFFFF'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.brightness_low, color: Colors.grey, size: 16),
                Expanded(
                  child: Slider(
                    value: (act['brightness'] as num).toDouble(),
                    min: 0,
                    max: 100,
                    activeColor: AppColors.primaryBlue,
                    onChanged: (val) => setState(() { _addedActions[index]['brightness'] = val.toInt(); }),
                  ),
                ),
                const Icon(Icons.brightness_high, color: Colors.grey, size: 16),
              ],
            ),
          ] else if (isSpk) ...[
            const SizedBox(height: 16),
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
                const Icon(Icons.volume_down, color: Colors.grey, size: 16),
                Expanded(
                  child: Slider(
                    value: (act['volume'] as num).toDouble(),
                    min: 0,
                    max: 100,
                    activeColor: Colors.pinkAccent,
                    onChanged: (val) => setState(() { _addedActions[index]['volume'] = val.toInt(); }),
                  ),
                ),
                const Icon(Icons.volume_up, color: Colors.grey, size: 16),
              ],
            ),
          ] else if (isBld) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text("0%", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: (act['position'] as num).toDouble(),
                    min: 0,
                    max: 100,
                    activeColor: Colors.cyanAccent,
                    onChanged: (val) => setState(() { _addedActions[index]['position'] = val.toInt(); }),
                  ),
                ),
                Text("100%", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
              ],
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildColorSelector(int index, Color color, String hex) {
    bool isSelected = _addedActions[index]['color'] == hex;
    return GestureDetector(
      onTap: () => setState(() { _addedActions[index]['color'] = hex; }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
          boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)] : [],
        ),
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
