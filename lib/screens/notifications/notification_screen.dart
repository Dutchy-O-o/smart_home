import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../dashboard/dashboard_screen.dart';
import '../ai_hub/emotion_hub_screen.dart';
import '../security/monitoring_screen.dart';
import '../devices/device_control_screen.dart';
import '../profile/profile_screen.dart';
import '../automations/automations_list_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  String _selectedType = "All";
  String _selectedLevel = "Any";

  void _onBottomNavTapped(int index) {
    if (index == 0) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
        (route) => false,
      );
    } else if (index == 1) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const EmotionHubScreen()));
    } else if (index == 2) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const AutomationsListScreen()));
    } else if (index == 3) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const MonitoringScreen()));
    } else if (index == 4) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const DeviceControlScreen()));
    } else if (index == 5) {
      // Already on Alerts
    } else if (index == 6) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // --- 1. HEADER SECTION ---
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Notification Center",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("All notifications marked as read.")),
                      );
                    },
                    child: const Text(
                      "Mark all read",
                      style: TextStyle(color: AppColors.primaryBlue),
                    ),
                  ),
                ],
              ),
            ),

            // --- 2. FILTERS ---
            SizedBox(
              height: 100,
              child: Column(
                children: [
                  // TYPE FILTER
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Text("TYPE", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 12),
                        _buildFilterBtn("All", _selectedType == "All", () => setState(() => _selectedType = "All")),
                        _buildFilterBtn("Security", _selectedType == "Security", () => setState(() => _selectedType = "Security")),
                        _buildFilterBtn("Emotion", _selectedType == "Emotion", () => setState(() => _selectedType = "Emotion")),
                        _buildFilterBtn("Device", _selectedType == "Device", () => setState(() => _selectedType = "Device")),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // LEVEL FILTER
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Text("LEVEL", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        _buildFilterBtn("Any", _selectedLevel == "Any", () => setState(() => _selectedLevel = "Any")),
                        _buildLevelBtn("Critical", AppColors.accentRed, _selectedLevel == "Critical", () => setState(() => _selectedLevel = "Critical")),
                        _buildLevelBtn("Warning", AppColors.accentOrange, _selectedLevel == "Warning", () => setState(() => _selectedLevel = "Warning")),
                        _buildLevelBtn("Info", AppColors.primaryBlue, _selectedLevel == "Info", () => setState(() => _selectedLevel = "Info")),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // --- 3. NOTIFICATION LIST ---
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                children: [
                  // TODAY HEADER
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Today", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accentRed.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.accentRed.withOpacity(0.5)),
                        ),
                        child: const Text(
                          "3 CRITICAL ALERTS",
                          style: TextStyle(color: AppColors.accentRed, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // CARD 1: Earthquake (Critical)
                  _buildNotificationCard(
                    title: "Earthquake Tremor Detected",
                    time: "Just now",
                    description: "Emergency Protocols Active. Seismic activity detected in local grid via MQTT.",
                    color: AppColors.accentRed,
                    icon: Icons.landslide,
                    isCritical: true,
                    hasButtons: true,
                    onPrimaryAction: () {
                      // View Camera Logic -> Monitoring Screen
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const MonitoringScreen()));
                    },
                    onSecondaryAction: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Alarm silenced.")));
                    },
                  ),

                  // CARD 2: Gas Leak (Warning)
                  _buildNotificationCard(
                    title: "Gas Leak Detected",
                    time: "5m ago",
                    description: "Kitchen Sensor: High Methane Levels (400ppm). Ventilation triggered automatically.",
                    color: AppColors.accentOrange,
                    icon: Icons.gas_meter,
                    isCritical: false,
                  ),

                  // CARD 3: Mood (Info)
                  _buildNotificationCard(
                    title: "Home Mood Updated",
                    time: "1h ago",
                    description: "Lighting adjusted to 'Relaxed' due to quiet activity detection in Living Room.",
                    color: AppColors.primaryBlue,
                    icon: Icons.sentiment_satisfied_alt,
                    isCritical: false,
                  ),

                  const SizedBox(height: 24),
                  const Text("Yesterday", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),

                  // CARD 4: Device Malfunction (Grey)
                  _buildNotificationCard(
                    title: "Bedroom Blind Motor",
                    time: "2:30 PM",
                    description: "Malfunction - Device not responding MQTT ping. Check power supply.",
                    color: Colors.grey,
                    icon: Icons.blinds_closed,
                    isCritical: false,
                    hasRefresh: true,
                  ),
                  
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppColors.cardDark,
        selectedItemColor: AppColors.accentRed,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        currentIndex: 5,
        onTap: _onBottomNavTapped,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'Dash'),
          BottomNavigationBarItem(icon: Icon(Icons.sentiment_satisfied_alt), label: 'Emotion'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'Automate'),
          BottomNavigationBarItem(icon: Icon(Icons.security), label: 'Security'),
          BottomNavigationBarItem(icon: Icon(Icons.devices), label: 'Devices'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildFilterBtn(String text, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryBlue : AppColors.cardDark,
          borderRadius: BorderRadius.circular(20),
          border: isActive ? null : Border.all(color: Colors.grey.shade800),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.grey,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildLevelBtn(String text, Color color, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? color : color.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard({
    required String title,
    required String time,
    required String description,
    required Color color,
    required IconData icon,
    bool isCritical = false,
    bool hasButtons = false,
    bool hasRefresh = false,
    VoidCallback? onPrimaryAction,
    VoidCallback? onSecondaryAction,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(

          child: Row(
            children: [
              Container(
                width: 6,
                color: color,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(icon, color: color, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  description,
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(time, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                              if (isCritical)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Icon(Icons.warning, color: AppColors.accentRed.withOpacity(0.6), size: 16),
                                ),
                              if (hasRefresh)
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.refresh, color: AppColors.primaryBlue),
                                  onPressed: () {
                                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Checking status...")));
                                  },
                                ),
                            ],
                          )
                        ],
                      ),
                      
                      // Action Buttons (Varsa)
                      if (hasButtons) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            ElevatedButton(
                              onPressed: onPrimaryAction,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: color,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                                minimumSize: const Size(0, 36),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text("View Camera", style: TextStyle(fontSize: 12)),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: onSecondaryAction,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[800],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                                minimumSize: const Size(0, 36),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text("Silence Alarm", style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        )
                      ]
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}