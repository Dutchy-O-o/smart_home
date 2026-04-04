import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../auth/login_screen.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/home_provider.dart';
import '../../providers/theme_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _pushNotifications = true;
  bool _isLoading = true;

  String _userName = '';
  String _userEmail = '';
  String _userId = '';
  bool _emailVerified = false;

  @override
  void initState() {
    super.initState();
    _fetchUserAttributes();
  }

  Future<void> _fetchUserAttributes() async {
    try {
      final attributes = await Amplify.Auth.fetchUserAttributes();
      String email = '';
      String name = '';
      String sub = '';
      bool verified = false;

      for (final attr in attributes) {
        if (attr.userAttributeKey == AuthUserAttributeKey.email) {
          email = attr.value;
        }
        if (attr.userAttributeKey == AuthUserAttributeKey.name) {
          name = attr.value;
        }
        if (attr.userAttributeKey == AuthUserAttributeKey.emailVerified) {
          verified = attr.value == 'true';
        }
        if (attr.userAttributeKey.key == 'sub') {
          sub = attr.value;
        }
      }

      if (mounted) {
        setState(() {
          _userEmail = email;
          _userName = name.isNotEmpty ? name : email.split('@').first;
          _userId = sub;
          _emailVerified = verified;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _userName = 'User';
          _userEmail = '';
          _isLoading = false;
        });
      }
    }
  }

  // --- EDIT NAME ---
  Future<void> _editName() async {
    final controller = TextEditingController(text: _userName);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Edit Name", style: TextStyle(color: AppColors.text(ctx))),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: AppColors.text(ctx)),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.bg(ctx),
            hintText: "Your name",
            hintStyle: TextStyle(color: AppColors.textSub(ctx)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Cancel", style: TextStyle(color: AppColors.textSub(ctx))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("Save", style: TextStyle(color: AppColors.primaryBlue)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != _userName) {
      try {
        await Amplify.Auth.updateUserAttribute(
          userAttributeKey: AuthUserAttributeKey.name,
          value: newName,
        );
        if (mounted) {
          setState(() => _userName = newName);
          _showSnack("Name updated successfully.", AppColors.accentGreen);
        }
      } catch (e) {
        if (mounted) _showSnack("Failed to update name.", AppColors.accentRed);
      }
    }
  }

  // --- CHANGE PASSWORD ---
  Future<void> _changePassword() async {
    final oldPwController = TextEditingController();
    final newPwController = TextEditingController();
    final confirmPwController = TextEditingController();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.card(ctx),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text("Change Password", style: TextStyle(color: AppColors.text(ctx), fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text("Enter your current password and choose a new one.", style: TextStyle(color: AppColors.textSub(ctx), fontSize: 13)),
                const SizedBox(height: 20),
                _buildPasswordField(oldPwController, "Current Password"),
                const SizedBox(height: 12),
                _buildPasswordField(newPwController, "New Password"),
                const SizedBox(height: 12),
                _buildPasswordField(confirmPwController, "Confirm New Password"),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      if (newPwController.text != confirmPwController.text) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("Passwords do not match."), backgroundColor: AppColors.accentRed),
                        );
                        return;
                      }
                      if (newPwController.text.length < 8) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text("Password must be at least 8 characters."), backgroundColor: AppColors.accentRed),
                        );
                        return;
                      }
                      try {
                        await Amplify.Auth.updatePassword(
                          oldPassword: oldPwController.text,
                          newPassword: newPwController.text,
                        );
                        Navigator.pop(ctx, true);
                      } on AuthException catch (e) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(e.message), backgroundColor: AppColors.accentRed),
                        );
                      }
                    },
                    child: const Text("Update Password", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );

    if (result == true && mounted) {
      _showSnack("Password changed successfully.", AppColors.accentGreen);
    }
  }

  // --- LEGAL INFO MODAL ---
  void _showLegalSheet(String title, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 20),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(title, style: TextStyle(color: AppColors.text(context), fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                child: Text(
                  content,
                  style: TextStyle(color: AppColors.textSub(context), fontSize: 14, height: 1.6),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("I Understand", style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- LOGOUT ---
  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Log Out", style: TextStyle(color: AppColors.text(context))),
        content: Text("Are you sure you want to log out?", style: TextStyle(color: AppColors.textSub(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel", style: TextStyle(color: AppColors.textSub(context))),
          ),
          TextButton(
            onPressed: () async {
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

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedHome = ref.watch(selectedHomeProvider);
    final homeName = selectedHome?['home_name'] ?? 'No Home Selected';
    final homeRole = (selectedHome?['role'] ?? '').toString().toUpperCase();
    final isDark = ref.watch(themeProvider) == ThemeMode.dark;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryBlue))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- HEADER ---
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_ios, color: AppColors.iconDefault(context), size: 20),
                          onPressed: () => ref.read(tabIndexProvider.notifier).setTab(0),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              "Profile & Settings",
                              style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ========== USER PROFILE ==========
                    Center(
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundColor: AppColors.primaryBlue.withOpacity(0.15),
                                child: Text(
                                  _userName.isNotEmpty ? _userName[0].toUpperCase() : '?',
                                  style: const TextStyle(
                                    color: AppColors.primaryBlue,
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: _editName,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: AppColors.primaryBlue,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.edit, color: Colors.white, size: 16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(_userName, style: TextStyle(color: AppColors.text(context), fontSize: 24, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_userEmail, style: TextStyle(color: AppColors.textSub(context), fontSize: 14)),
                              if (_emailVerified) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.verified, color: AppColors.accentGreen, size: 16),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Active home badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.card(context),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.home_rounded, color: AppColors.primaryBlue, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  homeName,
                                  style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                if (homeRole.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: homeRole == 'ADMIN'
                                          ? AppColors.primaryBlue.withOpacity(0.2)
                                          : AppColors.accentOrange.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      homeRole,
                                      style: TextStyle(
                                        color: homeRole == 'ADMIN' ? AppColors.primaryBlue : AppColors.accentOrange,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ========== ACCOUNT ==========
                    Text("ACCOUNT", style: TextStyle(color: AppColors.textSub(context), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(color: AppColors.card(context), borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: [
                          _buildTile(Icons.person, Colors.blue, "Edit Display Name", onTap: _editName),
                          Divider(color: AppColors.borderCol(context), height: 1),
                          _buildTile(Icons.lock, Colors.blue, "Change Password", onTap: _changePassword),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ========== PREFERENCES ==========
                    Text("PREFERENCES", style: TextStyle(color: AppColors.textSub(context), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(color: AppColors.card(context), borderRadius: BorderRadius.circular(16)),
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
                            title: Text("Push Notifications", style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold)),
                            subtitle: Text("Security & sensor alerts", style: TextStyle(color: AppColors.textSub(context), fontSize: 12)),
                            value: _pushNotifications,
                            onChanged: (val) => setState(() => _pushNotifications = val),
                          ),
                          Divider(color: AppColors.borderCol(context), height: 1),
                          SwitchListTile(
                            activeColor: AppColors.primaryBlue,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            secondary: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), shape: BoxShape.circle),
                              child: const Icon(Icons.dark_mode, color: Colors.amber),
                            ),
                            title: Text("Dark Mode", style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold)),
                            subtitle: Text("Toggle app theme", style: TextStyle(color: AppColors.textSub(context), fontSize: 12)),
                            value: isDark,
                            onChanged: (_) => ref.read(themeProvider.notifier).toggle(),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ========== LEGAL & INFO ==========
                    Text("LEGAL & INFO", style: TextStyle(color: AppColors.textSub(context), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(color: AppColors.card(context), borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: [
                          _buildTile(Icons.description, AppColors.primaryBlue, "Terms of Service", onTap: () {
                            _showLegalSheet("Terms of Service", _termsOfServiceText);
                          }),
                          Divider(color: AppColors.borderCol(context), height: 1),
                          _buildTile(Icons.privacy_tip, AppColors.accentGreen, "Privacy Policy", onTap: () {
                            _showLegalSheet("Privacy Policy", _privacyPolicyText);
                          }),
                          Divider(color: AppColors.borderCol(context), height: 1),
                          _buildTile(Icons.info_outline, Colors.grey, "About", onTap: () {
                            _showLegalSheet("About Smart Home", _aboutText);
                          }),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ========== ACCOUNT ID ==========
                    if (_userId.isNotEmpty)
                      Center(
                        child: GestureDetector(
                          onLongPress: () {
                            _showSnack("User ID copied.", AppColors.primaryBlue);
                          },
                          child: Text(
                            "ID: ${_userId.substring(0, _userId.length > 8 ? 8 : _userId.length)}...",
                            style: TextStyle(color: AppColors.textSub(context), fontSize: 11),
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // ========== LOGOUT ==========
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
                    Center(child: Text("v1.0.4 (MQTT-Build)", style: TextStyle(color: AppColors.textSub(context), fontSize: 12))),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }

  // --- REUSABLE WIDGETS ---

  Widget _buildTile(IconData icon, Color color, String title, {required VoidCallback onTap}) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold, fontSize: 14)),
      trailing: Icon(Icons.arrow_forward_ios, color: AppColors.textSub(context), size: 14),
    );
  }

  Widget _buildPasswordField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      obscureText: true,
      style: TextStyle(color: AppColors.text(context)),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.bg(context),
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textSub(context)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  // --- STATIC CONTENT ---

  static const String _termsOfServiceText = """
1. Acceptance of Terms
By downloading, installing, or using the Smart Home application, you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the application.

2. Description of Service
Smart Home provides IoT-based home automation and monitoring services, including but not limited to:
- Real-time sensor data monitoring (temperature, humidity, gas, vibration)
- Remote device control via MQTT protocol
- AI-powered emotion-based automation
- Push notification alerts for security events
- Multi-user home sharing via QR code invitations

3. User Responsibilities
- You are responsible for maintaining the confidentiality of your account credentials.
- You agree not to reverse-engineer, tamper with, or modify any connected hardware including Raspberry Pi units and sensor modules.
- You are responsible for ensuring your home network meets minimum security standards (WPA2 or higher).

4. Data & Sensor Accuracy
Sensor readings are provided on an "as-is" basis. While we strive for accuracy, Smart Home does not guarantee the precision of any sensor data and should not be used as a sole safety system for gas leak or earthquake detection. Always maintain independent safety systems.

5. Service Availability
We aim for 99.9% uptime but do not guarantee uninterrupted service. Cloud infrastructure outages, network failures, or hardware malfunctions may temporarily affect service availability.

6. Limitation of Liability
Smart Home and its developers shall not be held liable for any damages, injuries, or losses resulting from missed alerts, sensor malfunctions, network failures, or unauthorized access to your smart home system.

7. Termination
We reserve the right to terminate or suspend your account at any time for violation of these terms. You may delete your account at any time through the application.

8. Changes to Terms
We may update these terms periodically. Continued use of the application after changes constitutes acceptance of the updated terms.

Last updated: April 2026""";

  static const String _privacyPolicyText = """
1. Information We Collect

Personal Information:
- Email address (for account creation and authentication)
- Display name (optional, stored in AWS Cognito)
- FCM token (for push notification delivery)

Sensor & Device Data:
- Temperature, humidity, gas level, and vibration readings from your connected sensors
- Device states (on/off, brightness, volume settings)
- Automation rules you create

Usage Data:
- Login timestamps and session information
- Home membership and role information

2. How We Use Your Data
- To provide and maintain the Smart Home service
- To send real-time security alerts and notifications
- To enable AI-based emotion detection and automation
- To allow multi-user home sharing functionality

3. Data Storage & Security
- Authentication is handled via AWS Cognito with SRP (Secure Remote Password) protocol
- All API communications are encrypted via HTTPS/TLS
- Sensor data is stored in PostgreSQL databases hosted on AWS RDS
- Real-time commands use encrypted MQTT channels via AWS IoT Core

4. Data Sharing
We do NOT sell, trade, or share your personal data with third parties. Your data is only accessible to:
- You and other members of your shared home
- AWS infrastructure services required to operate the platform

5. Data Retention
- Sensor data is retained for historical analysis as long as your account is active
- Upon account deletion, all associated data is permanently removed within 30 days

6. Your Rights
- Access: You can view all your data through the application
- Correction: You can update your profile information at any time
- Deletion: You can request complete data deletion by contacting support

7. Cookies & Tracking
The Smart Home application does not use cookies or third-party tracking services.

8. Children's Privacy
Smart Home is not intended for use by children under 13. We do not knowingly collect data from minors.

9. Contact
For privacy-related inquiries, please reach out through our support channels.

Last updated: April 2026""";

  static const String _aboutText = """
Smart Home v1.0.4 (MQTT-Build)

A next-generation IoT home automation platform that combines real-time sensor monitoring, intelligent device control, and AI-powered emotional awareness.

Core Technology Stack:
- Flutter (Cross-platform mobile framework)
- AWS Cognito (Authentication & user management)
- AWS Lambda (Serverless backend functions)
- AWS IoT Core (Real-time MQTT messaging)
- PostgreSQL on AWS RDS (Data persistence)
- Firebase Cloud Messaging (Push notifications)
- Raspberry Pi (Local hardware bridge)

Key Features:
- Real-time temperature, humidity, gas, and vibration monitoring
- Remote control of smart home devices (lights, curtains, AC, speakers)
- AI Emotion Hub with automated mood-based home adjustments
- QR code-based home sharing and guest management
- Custom automation rules with trigger-action pairs
- Instant push notifications for security events

Communication Protocol:
All device commands flow through AWS IoT Core using the MQTT protocol, ensuring sub-second latency between your phone and your Raspberry Pi hub. Sensor data is collected every 5 seconds and stored in the cloud for historical analysis.

Built with care for a connected, intelligent home experience.""";
}
