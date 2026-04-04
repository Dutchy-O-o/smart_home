import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';


class MonitoringScreen extends StatefulWidget {
  const MonitoringScreen({super.key});

  @override
  State<MonitoringScreen> createState() => _MonitoringScreenState();
}

class _MonitoringScreenState extends State<MonitoringScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 1. HEADER & STATUS BAR ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.menu, color: AppColors.iconDefault(context)),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Monitoring Station",
                            style: TextStyle(
                              color: AppColors.text(context),
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "System Online v2.4.1",
                            style: TextStyle(color: AppColors.textSub(context), fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.card(context),
                    child: Icon(Icons.person, size: 20, color: AppColors.iconDefault(context)),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),

              // --- 2. CONNECTIVITY INDICATORS ---
              Row(
                children: [
                  _buildStatusCapsule("Live - MQTT Connected", AppColors.accentGreen, true),
                  const SizedBox(width: 12),
                  _buildStatusCapsule("Ping: 24ms", Colors.grey, false),
                ],
              ),

              const SizedBox(height: 24),

              // --- 3. LIVE CAMERA FEED SECTION ---
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                  image: DecorationImage(
                    image: const NetworkImage("https://images.unsplash.com/photo-1550989460-0adf9ea622e2?q=80&w=600&auto=format&fit=crop"),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.4), BlendMode.darken),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text("REC", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            "CAM_01_LIVING_ROOM",
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.black, blurRadius: 4)]),
                          ),
                        ],
                      ),
                    ),
                    const Positioned(
                      top: 16,
                      right: 16,
                      child: Icon(Icons.fullscreen, color: Colors.white),
                    ),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withOpacity(0.8),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.volume_up, color: Colors.white, size: 20),
                              SizedBox(width: 16),
                              Icon(Icons.camera_alt, color: Colors.white, size: 20),
                              SizedBox(width: 16),
                              Icon(Icons.mic, color: Colors.white, size: 20),
                            ],
                          ),
                          const Text(
                            "19:42:05 PM",
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // --- 4. CRITICAL ALERT CARD ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2C1E24),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.accentRed.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.accentRed.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.warning_amber_rounded, color: AppColors.accentRed),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("CRITICAL ALERT", style: TextStyle(color: AppColors.accentRed, fontWeight: FontWeight.bold, fontSize: 12)),
                            Text("Gas Threshold Exceeded", style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.phone, color: Colors.white),
                        label: const Text("Emergency 911"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentRed,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // --- 5. SENSOR DATA CARDS ---
              _buildSensorChartCard(
                title: "Gas Sensor",
                value: "45",
                unit: "ppm",
                trend: "+5%",
                isTrendPositive: true,
                icon: Icons.cloud,
                chartColor: AppColors.primaryBlue,
              ),
              const SizedBox(height: 16),
              _buildSensorChartCard(
                title: "Vibration",
                value: "12",
                unit: "Hz",
                trend: "- 0%",
                isTrendPositive: false,
                icon: Icons.vibration,
                chartColor: Colors.grey,
              ),

              const SizedBox(height: 30),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "ACTIONS",
                    style: TextStyle(
                        color: AppColors.textSub(context),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // Refresh Butonu (Yuvarlak ve belirgin)
                      Container(
                        width: 60,

                        height: 60,
                        decoration: BoxDecoration(
                          color: AppColors.card(context),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.borderCol(context)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: IconButton(
                          icon: Icon(Icons.refresh, color: AppColors.iconDefault(context), size: 28),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Sensors refreshed.")),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: SizedBox(
                          height: 60,

                          child: ElevatedButton.icon(
                            onPressed: () {
                              // Alarm tetikleme
                            },
                            icon: const Icon(Icons.notifications_active, size: 24, color: Colors.white),
                            label: const Text(
                              "Trigger Alarm",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryBlue,
                              elevation: 4,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                              shadowColor: AppColors.primaryBlue.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      
    );
  }

  Widget _buildStatusCapsule(String text, Color dotColor, bool isGreen) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isGreen ? dotColor.withOpacity(0.3) : Colors.transparent),
      ),
      child: Row(
        children: [
          if (isGreen) ...[
            Icon(Icons.circle, size: 8, color: dotColor),
            const SizedBox(width: 6),
          ] else ...[
            Icon(Icons.wifi, size: 14, color: dotColor),
             const SizedBox(width: 6),
          ],
          Text(text, style: TextStyle(color: isGreen ? dotColor : AppColors.textSub(context), fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSensorChartCard({
    required String title,
    required String value,
    required String unit,
    required String trend,
    required bool isTrendPositive,
    required IconData icon,
    required Color chartColor,
  }) {
    return Container(
      height: 200, 
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: AppColors.textSub(context), size: 20),
                  const SizedBox(width: 8),
                  Text(title, style: TextStyle(color: AppColors.textSub(context))),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isTrendPositive ? AppColors.accentGreen.withOpacity(0.1) : AppColors.textSub(context).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  trend,
                  style: TextStyle(
                    color: isTrendPositive ? AppColors.accentGreen : AppColors.textSub(context),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: TextStyle(color: AppColors.text(context), fontSize: 32, fontWeight: FontWeight.bold)),
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4),
                child: Text(unit, style: TextStyle(color: AppColors.textSub(context), fontSize: 16)),
              ),
            ],
          ),

          const Spacer(),

          SizedBox(
            height: 50,
            width: double.infinity,
            child: CustomPaint(
              painter: ChartPainter(color: chartColor),
            ),
          ),
          
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("00:00", style: TextStyle(color: AppColors.textSub(context), fontSize: 10)),
              Text("12:00", style: TextStyle(color: AppColors.textSub(context), fontSize: 10)),
              Text("Now", style: TextStyle(color: AppColors.textSub(context), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class ChartPainter extends CustomPainter {
  final Color color;
  ChartPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    var path = Path();
    path.moveTo(0, size.height);
    path.quadraticBezierTo(
      size.width * 0.25, size.height * 0.6,
      size.width * 0.5, size.height * 0.8, 
    );
    path.quadraticBezierTo(
      size.width * 0.75, size.height * 1.1,
      size.width, size.height * 0.3, 
    );

    canvas.drawPath(path, paint);

    var fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    var fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [color.withOpacity(0.3), color.withOpacity(0.0)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
  } 

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}