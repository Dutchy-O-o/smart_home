import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _pushNotifications = true;
  static const _kPushPrefsKey = 'profile_push_notifications';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _pushNotifications = prefs.getBool(_kPushPrefsKey) ?? true;
      });
    }
  }

  Future<void> _setPush(bool value) async {
    setState(() => _pushNotifications = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPushPrefsKey, value);
  }

  Future<void> _changePassword() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(context),
        title: Text('Change Password',
            style: TextStyle(color: AppColors.text(context))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldCtrl,
              obscureText: true,
              style: TextStyle(color: AppColors.text(context)),
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              style: TextStyle(color: AppColors.text(context)),
              decoration: const InputDecoration(labelText: 'New password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update',
                style: TextStyle(color: AppColors.primaryBlue)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (oldCtrl.text.isEmpty || newCtrl.text.isEmpty) return;
    try {
      await Amplify.Auth.updatePassword(
        oldPassword: oldCtrl.text,
        newPassword: newCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: AppColors.accentRed,
        ),
      );
    }
  }

  Future<void> _changeName(String currentName) async {
    final ctrl = TextEditingController(text: currentName);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(context),
        title: Text('Change Name',
            style: TextStyle(color: AppColors.text(context))),
        content: TextField(
          controller: ctrl,
          style: TextStyle(color: AppColors.text(context)),
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save',
                style: TextStyle(color: AppColors.primaryBlue)),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await Amplify.Auth.updateUserAttribute(
        userAttributeKey: AuthUserAttributeKey.givenName,
        value: ctrl.text.trim(),
      );
      ref.invalidate(userAttributesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: AppColors.accentRed,
        ),
      );
    }
  }

  void _showTerms() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textSub(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Terms of Service',
                style: TextStyle(
                  color: AppColors.text(context),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '''By using Smart Home you agree to the following terms:

1. You are responsible for any device actions triggered via the app.
2. Facial emotion data is processed locally on your Raspberry Pi and never leaves your home network without your explicit consent.
3. Spotify integration is subject to Spotify\'s terms. Tokens are stored locally on this device only.
4. Cognito credentials and FCM tokens are stored on AWS. We do not sell any personal data.
5. Automations are executed on a best-effort basis; always keep a physical backup for safety-critical devices.
6. You may delete your account at any time; doing so removes your homes, devices, and automation rules from AWS.

These terms may be updated. Continued use after an update constitutes acceptance of the new terms.''',
                style: TextStyle(
                  color: AppColors.textSub(context),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(context),
        title: Text('Log Out',
            style: TextStyle(color: AppColors.text(context))),
        content: Text('Are you sure you want to log out?',
            style: TextStyle(color: AppColors.textSub(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out',
                style: TextStyle(color: AppColors.accentRed)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await ref.read(authProvider.notifier).signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final attrsAsync = ref.watch(userAttributesProvider);
    final attrs = attrsAsync.value ?? const <String, String>{};
    final email = attrs['email'] ?? '';
    final givenName = attrs['given_name'] ?? attrs['name'] ?? '';
    final displayName = givenName.isNotEmpty
        ? givenName
        : (email.isNotEmpty ? email.split('@').first : 'User');
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios,
                        color: AppColors.text(context), size: 20),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Profile & Settings',
                        style: TextStyle(
                          color: AppColors.text(context),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
              const SizedBox(height: 20),

              // Avatar initial + name + email
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.15),
                      child: Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: AppColors.primaryBlue,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      displayName,
                      style: TextStyle(
                        color: AppColors.text(context),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: TextStyle(
                          color: AppColors.textSub(context),
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              _sectionLabel('ACCOUNT'),
              _card([
                _tile(
                  icon: Icons.person,
                  color: AppColors.primaryBlue,
                  title: 'Change Name',
                  subtitle: givenName.isNotEmpty ? givenName : 'Not set',
                  onTap: () => _changeName(givenName),
                ),
                _divider(),
                _tile(
                  icon: Icons.lock,
                  color: AppColors.primaryBlue,
                  title: 'Change Password',
                  onTap: _changePassword,
                ),
              ]),

              const SizedBox(height: 24),

              _sectionLabel('PREFERENCES'),
              _card([
                SwitchListTile(
                  activeThumbColor: AppColors.primaryBlue,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  secondary: _iconBadge(
                      Icons.notifications_active, Colors.purple),
                  title: Text(
                    'Push Notifications',
                    style: TextStyle(
                      color: AppColors.text(context),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Alerts for security and home events',
                    style: TextStyle(
                      color: AppColors.textSub(context),
                      fontSize: 12,
                    ),
                  ),
                  value: _pushNotifications,
                  onChanged: _setPush,
                ),
                _divider(),
                SwitchListTile(
                  activeThumbColor: AppColors.primaryBlue,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  secondary: _iconBadge(
                      isDark ? Icons.dark_mode : Icons.light_mode,
                      Colors.amber),
                  title: Text(
                    'Dark Theme',
                    style: TextStyle(
                      color: AppColors.text(context),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    isDark ? 'Dark appearance' : 'Light appearance',
                    style: TextStyle(
                      color: AppColors.textSub(context),
                      fontSize: 12,
                    ),
                  ),
                  value: isDark,
                  onChanged: (_) =>
                      ref.read(themeProvider.notifier).toggle(),
                ),
              ]),

              const SizedBox(height: 24),

              _sectionLabel('LEGAL'),
              _card([
                _tile(
                  icon: Icons.description,
                  color: Colors.teal,
                  title: 'Terms of Service',
                  onTap: _showTerms,
                ),
                _divider(),
                _tile(
                  icon: Icons.article_outlined,
                  color: Colors.teal,
                  title: 'Open-Source Licenses',
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Smart Home',
                  ),
                ),
              ]),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _handleLogout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentRed.withValues(alpha: 0.1),
                    foregroundColor: AppColors.accentRed,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(color: AppColors.accentRed),
                  ),
                  child: const Text(
                    'Log Out',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Smart Home v2.0',
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── helpers ────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
        text,
        style: TextStyle(
          color: AppColors.textSub(context),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      );

  Widget _card(List<Widget> children) => Container(
        margin: const EdgeInsets.only(top: 10),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderCol(context)),
        ),
        child: Column(children: children),
      );

  Widget _divider() => Divider(
        color: AppColors.borderCol(context),
        height: 1,
      );

  Widget _iconBadge(IconData icon, Color color) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 20),
      );

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: _iconBadge(icon, color),
      title: Text(
        title,
        style: TextStyle(
          color: AppColors.text(context),
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                color: AppColors.textSub(context),
                fontSize: 12,
              ),
            )
          : null,
      trailing: Icon(
        Icons.arrow_forward_ios,
        color: AppColors.textSub(context),
        size: 14,
      ),
    );
  }
}
