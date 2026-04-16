import 'package:flutter/material.dart';
import '../../../constants/app_colors.dart';

/// Big circular tap-to-scan button with mood-colored glow.
/// Shows a pulse + loader while [isScanning], otherwise renders the mood emoji
/// centered inside and a small "Scan" pill at the bottom.
class ScanArea extends StatelessWidget {
  const ScanArea({
    super.key,
    required this.moodEmoji,
    required this.moodColor,
    required this.isScanning,
    required this.onTap,
  });

  final String moodEmoji;
  final Color moodColor;
  final bool isScanning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: isScanning ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                moodColor.withValues(alpha: 0.35),
                moodColor.withValues(alpha: 0.05),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: moodColor.withValues(alpha: isScanning ? 0.5 : 0.25),
                blurRadius: isScanning ? 50 : 30,
                spreadRadius: isScanning ? 6 : 2,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.card(context),
                  border: Border.all(color: moodColor.withValues(alpha: 0.6), width: 2),
                ),
                child: ClipOval(
                  child: Container(
                    color: AppColors.card(context),
                    child: Center(
                      child: Text(
                        moodEmoji,
                        style: const TextStyle(fontSize: 80),
                      ),
                    ),
                  ),
                ),
              ),
              if (isScanning)
                Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.5),
                  ),
                  child: Center(
                    child: CircularProgressIndicator(color: moodColor),
                  ),
                ),
              if (!isScanning)
                Positioned(
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: moodColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.camera_alt, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'Scan',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
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
