import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../dashboard/dashboard_screen.dart';
import '../ai_hub/emotion_hub_screen.dart';
import '../security/monitoring_screen.dart';
import '../notifications/notification_screen.dart'; // Alerts ekranı için import
import '../profile/profile_screen.dart'; // Profile ekranı için import

class DeviceControlScreen extends StatefulWidget {
  const DeviceControlScreen({super.key});

  @override
  State<DeviceControlScreen> createState() => _DeviceControlScreenState();
}

class _DeviceControlScreenState extends State<DeviceControlScreen> {
  // --- STATE DEĞİŞKENLERİ ---
  bool _isLightOn = true;
  double _brightness = 58.0;
  
  // Seçili Işık Rengi (Varsayılan Mavi)
  Color _selectedLightColor = const Color(0xFF448AFF);

  String _curtainStatus = "Opening: 60%";
  int _targetTemp = 20;
  String _climateMode = "Cool"; 

  // Alt Menü Navigasyonu
  void _onBottomNavTapped(int index) {
    if (index == 0) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
        (route) => false,
      );
    } else if (index == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const EmotionHubScreen()),
      );
    } else if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const MonitoringScreen()),
      );
    } else if (index == 3) {
      // Zaten buradayız (Devices)
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
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 1. HEADER ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Column(
                    children: [
                      const Text(
                        "AI Emotion Hub",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: const [
                          Icon(Icons.circle, size: 8, color: AppColors.accentGreen),
                          SizedBox(width: 4),
                          Text("Living Room • Online",
                              style: TextStyle(color: AppColors.textGrey, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white),
                    onPressed: () {},
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // --- 2. AI MOOD SUGGESTION CARD ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF2C3E50),
                      AppColors.cardDark.withOpacity(0.8)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.auto_awesome, color: Colors.purpleAccent),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text("AI Mood Suggestion",
                                style: TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.bold)),
                            Text("Based on evening routine",
                                style: TextStyle(color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Relax profile applied.")),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text("Apply 'Relax'",
                          style: TextStyle(color: Colors.white)),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- 3. MOOD ANALYSIS (DÜZELTİLDİ: Parlama Yok, Overflow Yok) ---
              const Text("Mood Analysis",
                  style: TextStyle(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    // Başlık
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text("WEEKLY TRENDS",
                                style: TextStyle(color: Colors.grey, fontSize: 10)),
                            Text("Emotion Timeline",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Icon(Icons.show_chart, color: Colors.grey),
                      ],
                    ),
                    
                    const SizedBox(height: 30),
                    
                    // Grafik Çubukları
                    // Yükseklik 160 yapıldı (Bol alan)
                    SizedBox(
                      height: 160, 
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Renk kodlarını biraz daha yumuşak (pastel) seçtim
                          _buildChartBar("M", 40, const Color(0xFFCE93D8)), // Pastel Mor
                          _buildChartBar("T", 65, const Color(0xFF80CBC4)), // Pastel Yeşil
                          _buildChartBar("W", 30, const Color(0xFFCE93D8)), 
                          
                          // Perşembe (Seçili): Parlama YOK. Sadece renk ve harf belli ediyor.
                          // Boyutları küçülttüm (Max 80) ki overflow olmasın.
                          _buildChartBar("T", 80, const Color(0xFFBA68C8), isSelected: true), 
                          
                          _buildChartBar("F", 50, const Color(0xFF80CBC4)),
                          _buildChartBar("S", 70, const Color(0xFFF48FB1)), // Pastel Pembe
                          _buildChartBar("S", 45, const Color(0xFF80CBC4)),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Lejant
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLegend(const Color(0xFFCE93D8), "Relaxed"),
                        const SizedBox(width: 16),
                        _buildLegend(const Color(0xFF80CBC4), "Focused"),
                        const SizedBox(width: 16),
                        _buildLegend(const Color(0xFFF48FB1), "Excited"),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- 4. SMART LIGHTING CONTROL ---
              const Text("Smart Lighting",
                  style: TextStyle(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lightbulb,
                                color: _isLightOn ? _selectedLightColor : Colors.grey, size: 28),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text("Main Ceiling Light",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                                Text("Philips Hue • MQTT",
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                        Switch(
                          value: _isLightOn,
                          activeColor: _selectedLightColor,
                          onChanged: (val) {
                            setState(() => _isLightOn = val);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Renk Seçimi
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildColorDot(const Color(0xFFFF5252)), // Kırmızı
                        _buildColorDot(const Color(0xFFFFB74D)), // Turuncu
                        _buildColorDot(const Color(0xFF69F0AE)), // Yeşil
                        _buildColorDot(const Color(0xFF448AFF)), // Mavi
                        _buildColorDot(const Color(0xFFE040FB)), // Mor
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle, color: Colors.grey[800]),
                          child: const Icon(Icons.add, color: Colors.white, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Icon(Icons.brightness_5,
                            color: Colors.grey, size: 20),
                        Expanded(
                          child: Slider(
                            value: _brightness,
                            min: 0,
                            max: 100,
                            activeColor: _selectedLightColor,
                            inactiveColor: Colors.grey[800],
                            onChanged: (val) {
                              setState(() => _brightness = val);
                            },
                          ),
                        ),
                        Text("${_brightness.toInt()}%",
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- 5. CURTAINS & BLINDS ---
              const Text("Curtains & Blinds",
                  style: TextStyle(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.teal.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.curtains, color: Colors.teal),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Master Curtains",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            Text(_curtainStatus,
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 100,
                            decoration: BoxDecoration(
                              color: Colors.grey[900],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(child: Container(color: Colors.blueGrey.withOpacity(0.3))),
                                Container(width: 20, color: Colors.black),
                                Expanded(child: Container(color: Colors.blueGrey.withOpacity(0.3))),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          children: [
                            _buildControlBtn(Icons.keyboard_arrow_up),
                            const SizedBox(height: 8),
                            _buildControlBtn(Icons.stop, isPrimary: true),
                            const SizedBox(height: 8),
                            _buildControlBtn(Icons.keyboard_arrow_down),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildPresetBtn("Open"),
                        _buildPresetBtn("50%"),
                        _buildPresetBtn("Close"),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- 6. CLIMATE CONTROL ---
              const Text("Climate Control",
                  style: TextStyle(
                      color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.cardDark,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text("Inside Temp",
                                style: TextStyle(color: Colors.grey, fontSize: 12)),
                            Text("22°C",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: const [
                            Text("Humidity",
                                style: TextStyle(color: Colors.grey, fontSize: 12)),
                            Text("45%",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(40),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildTempBtn(Icons.remove, () => setState(() => _targetTemp--)),
                          Column(
                            children: [
                              const Text("SET TO",
                                  style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 1.5)),
                              Text("$_targetTemp°C",
                                  style: const TextStyle(
                                      color: AppColors.primaryBlue,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                          _buildTempBtn(Icons.add, () => setState(() => _targetTemp++)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildModeBtn("Cool", Icons.ac_unit, Colors.blue),
                        _buildModeBtn("Heat", Icons.local_fire_department, Colors.orange),
                        _buildModeBtn("Fan", Icons.air, Colors.grey),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppColors.cardDark,
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        currentIndex: 3,
        onTap: _onBottomNavTapped,
        showSelectedLabels: true,
        showUnselectedLabels: true,
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

  // --- YARDIMCI WIDGET'LAR ---

  Widget _buildChartBar(String day, double height, Color color, {bool isSelected = false}) {
    // PARLAMA DÜZELTİLDİ: Artık border yok.
    // OVERFLOW DÜZELTİLDİ: Container içinde height esnek bırakıldı, 
    // ama Column boyutu kontrollü.
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 8,
          height: height,
          decoration: BoxDecoration(
            color: color, 
            borderRadius: BorderRadius.circular(4),
            // Buradaki border kaldırıldı, artık parlamayacak.
          ),
        ),
        const SizedBox(height: 12),
        Text(day,
            style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12)),
      ],
    );
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }

  Widget _buildColorDot(Color color) {
    bool isSelected = _selectedLightColor == color;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedLightColor = color;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: isSelected ? 40 : 32,
        height: isSelected ? 40 : 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          // Buradaki gölgeyi de kaldırdım, belki o da gözünü alıyordur.
          border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: isSelected 
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }

  Widget _buildControlBtn(IconData icon, {bool isPrimary = false}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isPrimary ? AppColors.primaryBlue : Colors.grey[800],
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white),
    );
  }

  Widget _buildPresetBtn(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  Widget _buildTempBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          color: Colors.white10,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  Widget _buildModeBtn(String text, IconData icon, Color color) {
    bool isSelected = _climateMode == text;
    return GestureDetector(
      onTap: () => setState(() => _climateMode = text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryBlue : Colors.transparent,
          border: Border.all(
              color: isSelected ? AppColors.primaryBlue : Colors.grey[800]!),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey),
            const SizedBox(width: 6),
            Text(text,
                style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}