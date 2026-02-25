import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../widgets/sensor_card.dart';
import '../auth/login_screen.dart';
import '../ai_hub/emotion_hub_screen.dart'; 
import '../security/monitoring_screen.dart';
import '../devices/device_control_screen.dart'; // Devices ekranı için import
import '../notifications/notification_screen.dart'; // Alerts ekranı için import
import '../profile/profile_screen.dart'; // Profile ekranı için import

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Dimmer Switch durumu
  bool isDimmerOn = true;

  void _handleLogout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  // Alt Menü Navigasyon Fonksiyonu
  void _onBottomNavTapped(int index) {
    if (index == 0) {
      // Zaten Dashboard'dayız, bir şey yapma
    } else if (index == 1) {
      // AI Emotion Hub'a git
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const EmotionHubScreen()),
      );
    } else if (index == 2) {
      // Güvenlik (Monitoring) ekranına git
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const MonitoringScreen()),
      );
    } else if (index == 3) {
      // Devices ekranına git
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const DeviceControlScreen()),
      );
    } else if (index == 4) {
      // Alerts ekranına git
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const NotificationScreen()),
      );
    } else if (index == 5) {
      // Profile ekranına git
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ProfileScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 1. HEADER & ÇIKIŞ BUTONU ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ProfileScreen()),
                          );
                        },
                        child: const CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.cardDark,
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text("Welcome Back", style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
                          Text("Dave", style: TextStyle(color: AppColors.textWhite, fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.cardDark,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.circle, size: 8, color: AppColors.accentGreen),
                            SizedBox(width: 6),
                            Text("MQTT", style: TextStyle(color: AppColors.textWhite, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.wifi, color: Colors.white, size: 20),
                      const SizedBox(width: 12),
                      InkWell(
                        onTap: _handleLogout,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.accentRed.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.logout, color: AppColors.accentRed, size: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 24),

              // --- 2. SYSTEM STATUS CARD ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF152238),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sentiment_satisfied_alt, color: AppColors.primaryBlue, size: 36),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text("System Online", style: TextStyle(color: AppColors.primaryBlue, fontSize: 16, fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text(
                            "The house feels cozy and secure. No anomalies detected in the last hour.",
                            style: TextStyle(color: AppColors.textGrey, fontSize: 12, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // --- 3. ENVIRONMENTAL METRICS ---
              Row(
                children: const [
                  Expanded(
                    child: SensorCard(
                      title: "Temperature",
                      value: "22",
                      unit: "°C",
                      icon: Icons.thermostat,
                      iconColor: AppColors.accentOrange,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: SensorCard(
                      title: "Humidity",
                      value: "45",
                      unit: "%",
                      icon: Icons.water_drop,
                      iconColor: AppColors.primaryBlue,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // --- 4. SECURITY STATUS ---
              const Text("Security Status", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _onBottomNavTapped(2), // Security sayfasına yönlendir
                      child: const SensorCard(
                        title: "Gas Sensor",
                        value: "SAFE",
                        icon: Icons.cloud,
                        iconColor: AppColors.accentGreen,
                        status: "• NORMAL",
                        statusColor: AppColors.accentGreen,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _onBottomNavTapped(2), // Security sayfasına yönlendir
                      child: const SensorCard(
                        title: "Vibration",
                        value: "STABLE",
                        icon: Icons.vibration,
                        iconColor: AppColors.accentGreen,
                        status: "• NO RISK",
                        statusColor: AppColors.accentGreen,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // --- 5. QUICK ACCESS ---
              const Text("Quick Access", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildQuickAccessBtn(Icons.lightbulb, "Lights", AppColors.primaryBlue),
                  _buildQuickAccessBtn(Icons.curtains, "Curtains", Colors.white24),
                  _buildQuickAccessBtn(Icons.ac_unit, "AC On", Colors.white24, iconColor: AppColors.primaryBlue),
                  _buildQuickAccessBtn(Icons.palette, "Mood", Colors.white24, iconColor: Colors.pinkAccent, onTap: () {
                    _onBottomNavTapped(1); // Mood sayfasına yönlendir
                  }),
                ],
              ),

              const SizedBox(height: 24),

              // --- 6. DEVICE CONTROL CARD ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.wb_sunny, color: Colors.amber, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text("Living Room Dimmer", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          Text("80% Brightness", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    ),
                    Switch(
                      value: isDimmerOn,
                      activeColor: AppColors.primaryBlue,
                      onChanged: (val) {
                        setState(() {
                          isDimmerOn = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      
      // --- BOTTOM NAVIGATION BAR (YENİLENDİ) ---
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppColors.cardDark,
        selectedItemColor: AppColors.primaryBlue, // Dashboard'da olduğumuz için Mavi
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        currentIndex: 0, // İlk eleman (Dashboard) seçili
        onTap: _onBottomNavTapped,
        showSelectedLabels: true, // Yazılar görünsün
        showUnselectedLabels: true, // Yazılar görünsün
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'Dash'),
          BottomNavigationBarItem(icon: Icon(Icons.sentiment_satisfied_alt), label: 'Emotion'),
          BottomNavigationBarItem(icon: Icon(Icons.security), label: 'Security'),
          BottomNavigationBarItem(icon: Icon(Icons.devices), label: 'Devices'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildQuickAccessBtn(IconData icon, String label, Color bg, {Color iconColor = Colors.white, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: bg == AppColors.primaryBlue ? AppColors.primaryBlue : AppColors.cardDark,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Icon(icon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: AppColors.textGrey, fontSize: 12)),
        ],
      ),
    );
  }
}