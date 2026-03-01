import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../dashboard/dashboard_screen.dart';
import '../ai_hub/emotion_hub_screen.dart';
import '../security/monitoring_screen.dart';
import '../devices/device_control_screen.dart';
import '../notifications/notification_screen.dart';
import '../auth/login_screen.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _pushNotifications = true;

  // Alt Menü Navigasyonu (6. Eleman: Profile)
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
      Navigator.push(context, MaterialPageRoute(builder: (context) => const MonitoringScreen()));
    } else if (index == 3) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const DeviceControlScreen()));
    } else if (index == 4) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationScreen()));
    } else if (index == 5) {
      // Zaten Profile ekranındayız
    }
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardDark,
        title: const Text("Log Out", style: TextStyle(color: Colors.white)),
        content: const Text("Are you sure you want to log out?", style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              // perform actual sign out via provider before leaving
              await ref.read(authProvider.notifier).signOut();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text("Log Out", style: TextStyle(color: AppColors.accentRed)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HEADER & NAV ---
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        "Profile & Settings",
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 40), // Başlığı ortalamak için boşluk
                ],
              ),
              const SizedBox(height: 20),

              // --- USER PROFILE SECTION ---
              Center(
                child: Column(
                  children: [
                    Stack(
                      children: [
                        const CircleAvatar(
                          radius: 50,
                          backgroundImage: NetworkImage("https://img.freepik.com/free-photo/portrait-white-man-isolated_53876-40306.jpg"),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: AppColors.primaryBlue,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.edit, color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text("Alex Doe", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const Text("alex.doe@iot-mail.com", style: TextStyle(color: Colors.grey, fontSize: 14)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.cardDark,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.circle, color: AppColors.accentGreen, size: 10),
                          SizedBox(width: 8),
                          Text("System: Happy & Secure", style: TextStyle(color: AppColors.accentGreen, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // --- GENERAL SETTINGS ---
              const Text("GENERAL", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(color: AppColors.cardDark, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    _buildListTile(Icons.person, Colors.blue, "Account Details", onTap: () {}),
                    const Divider(color: Colors.white10, height: 1),
                    _buildListTile(Icons.lock, Colors.blue, "Security & Password", onTap: () {}),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // --- SMART HOME PREFERENCES ---
              const Text("SMART HOME PREFERENCES", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(color: AppColors.cardDark, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    SwitchListTile(
                      activeColor: AppColors.primaryBlue,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      secondary: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.purple.withOpacity(0.2), shape: BoxShape.circle),
                        child: const Icon(Icons.notifications, color: Colors.purple),
                      ),
                      title: const Text("Push Notifications", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: const Text("Alerts for security events", style: TextStyle(color: Colors.grey, fontSize: 12)),
                      value: _pushNotifications,
                      onChanged: (val) => setState(() => _pushNotifications = val),
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    _buildListTile(Icons.sentiment_satisfied, Colors.pink, "Emotional Feedback", trailingText: "High", onTap: () {}),
                    const Divider(color: Colors.white10, height: 1),
                    _buildListTile(Icons.dark_mode, Colors.amber, "App Theme", trailingText: "Dark", onTap: () {}),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // --- CONNECTED NODES ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text("CONNECTED NODES", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                  Text("MANAGE", style: TextStyle(color: AppColors.primaryBlue, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildNodeCard("Living Room Pi", "MQTT Master", Icons.memory, Colors.green, true),
                    const SizedBox(width: 12),
                    _buildNodeCard("Garage Cam", "ESP32-Cam", Icons.videocam, Colors.blue, true),
                    const SizedBox(width: 12),
                    _buildNodeCard("Entry Sensor", "Offline", Icons.sensors, Colors.grey, false),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // --- LOGOUT ---
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _handleLogout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentRed.withOpacity(0.1),
                    foregroundColor: AppColors.accentRed,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: const BorderSide(color: AppColors.accentRed),
                  ),
                  child: const Text("Log Out", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
              const Center(child: Text("v1.0.4 (MQTT-Build)", style: TextStyle(color: Colors.grey, fontSize: 12))),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppColors.cardDark,
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        currentIndex: 5, // 6. Eleman (Profile)
        onTap: _onBottomNavTapped,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'Dash'),
          BottomNavigationBarItem(icon: Icon(Icons.sentiment_satisfied_alt), label: 'Emotion'),
          BottomNavigationBarItem(icon: Icon(Icons.security), label: 'Security'),
          BottomNavigationBarItem(icon: Icon(Icons.devices), label: 'Devices'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'), // YENİ
        ],
      ),
    );
  }

  Widget _buildListTile(IconData icon, Color color, String title, {String? trailingText, required VoidCallback onTap}) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null) Text(trailingText, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          if (trailingText != null) const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 14),
        ],
      ),
    );
  }

  Widget _buildNodeCard(String title, String subtitle, IconData icon, Color color, bool isOnline) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 24),
              Icon(Icons.circle, size: 8, color: isOnline ? AppColors.accentGreen : Colors.grey),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}