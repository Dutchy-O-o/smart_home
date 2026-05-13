import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/home_provider.dart';
import '../../providers/mood_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/api_service.dart';
import '../../services/scene_presets.dart';
import '../../services/usage_stats_service.dart';
import '../auth/login_screen.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';
import 'guest_management_screen.dart';

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

  /// Tucked-away submenu that still surfaces the legal-required pages
  /// (Terms of Service + Open-Source Licenses) in case Apple/Google ever
  /// asks for them, without cluttering the main profile screen.
  void _showAboutSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color:
                          AppColors.textSub(ctx).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'About this app',
                  style: TextStyle(
                    color: AppColors.text(ctx),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Smart Home v1.0',
                  style: TextStyle(
                    color: AppColors.textSub(ctx),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.description,
                      color: Colors.teal),
                  title: Text('Terms of Service',
                      style: TextStyle(color: AppColors.text(ctx))),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showTerms();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.article_outlined,
                      color: Colors.teal),
                  title: Text('Open-Source Licenses',
                      style: TextStyle(color: AppColors.text(ctx))),
                  onTap: () {
                    Navigator.pop(ctx);
                    showLicensePage(
                      context: context,
                      applicationName: 'Smart Home',
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
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
          padding: const EdgeInsets.all(AppSpacing.xl),
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

    ref.read(moodProvider.notifier).clear();
    await ref.read(authProvider.notifier).signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      AppMotion.fadeSlideRoute(const LoginScreen()),
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
    final selectedHome = ref.watch(selectedHomeProvider);
    final isAdmin =
        (selectedHome?['role']?.toString().toLowerCase() ?? '') == 'admin';

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: AppColors.brandGradient,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryBlue.withValues(alpha: 0.40),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Profile & Settings',
                            style: TextStyle(
                              color: AppColors.text(context),
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              height: 1.05,
                            ),
                          ),
                          Text(
                            'Account · preferences · about',
                            style: TextStyle(
                              color: AppColors.textSub(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Hero avatar block — gradient orb with soft halo, name, email,
              // and a subtle verified pill so the profile feels like *yours*
              // rather than an account form.
              Center(
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // Soft outer halo
                        Container(
                          width: 132,
                          height: 132,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppColors.primaryBlue.withValues(alpha: 0.35),
                                AppColors.primaryBlue.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                        // Gradient avatar orb
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: AppColors.brandGradient,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryBlue
                                    .withValues(alpha: 0.45),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                              BoxShadow(
                                color: AppColors.teal.withValues(alpha: 0.25),
                                blurRadius: 30,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 44,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                        // Verified badge
                        Positioned(
                          right: 18,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: AppColors.bg(context),
                              shape: BoxShape.circle,
                            ),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: const BoxDecoration(
                                color: AppColors.accentGreen,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      displayName,
                      style: TextStyle(
                        color: AppColors.text(context),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: TextStyle(
                          color: AppColors.textSub(context),
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primaryBlue.withValues(alpha: 0.20),
                            AppColors.primaryViolet.withValues(alpha: 0.14),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.primaryBlue.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.workspace_premium_rounded,
                              color: AppColors.primaryBlue, size: 13),
                          const SizedBox(width: 4),
                          Text(
                            'SMART HOME MEMBER',
                            style: TextStyle(
                              color: AppColors.primaryBlue,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
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

              if (isAdmin) ...[
                const SizedBox(height: 24),
                _sectionLabel('HOME ACCESS'),
                _card([
                  _GuestManagementTile(home: selectedHome ?? const {}),
                ]),
              ],

              const SizedBox(height: 24),

              _sectionLabel('PREFERENCES'),
              _card([
                SwitchListTile(
                  activeThumbColor: AppColors.primaryBlue,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  secondary: _iconBadge(
                      Icons.notifications_active, AppColors.primaryViolet),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _iconBadge(
                          themeMode == ThemeMode.dark
                              ? Icons.dark_mode
                              : themeMode == ThemeMode.light
                                  ? Icons.light_mode
                                  : Icons.brightness_auto,
                          Colors.amber),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Appearance',
                              style: TextStyle(
                                color: AppColors.text(context),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _ThemeSegmented(
                              mode: themeMode,
                              onChanged: (m) =>
                                  ref.read(themeProvider.notifier).setMode(m),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ]),

              const SizedBox(height: 24),

              _sectionLabel('YOUR SMART HOME'),
              const SizedBox(height: 10),
              const _UsageStatsPanel(),
              const SizedBox(height: 8),
              _card([
                _tile(
                  icon: Icons.gavel_outlined,
                  color: AppColors.textSub(context),
                  title: 'About this app',
                  onTap: _showAboutSheet,
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
                      borderRadius: BorderRadius.circular(AppRadius.sm),
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
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.borderCol(context)),
        ),
        child: Column(children: children),
      );

  Widget _divider() => Divider(
        color: AppColors.borderCol(context),
        height: 1,
      );

  Widget _iconBadge(IconData icon, Color color) => Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
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

/// 3-way Auto / Light / Dark segmented control for the appearance picker.
/// Highlighted segment uses the brand gradient and a shadow.
class _ThemeSegmented extends StatelessWidget {
  const _ThemeSegmented({required this.mode, required this.onChanged});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.bg(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.borderCol(context)),
      ),
      child: Row(
        children: [
          _seg(context, ThemeMode.system, Icons.brightness_auto, 'Auto'),
          _seg(context, ThemeMode.light, Icons.light_mode, 'Light'),
          _seg(context, ThemeMode.dark, Icons.dark_mode, 'Dark'),
        ],
      ),
    );
  }

  Widget _seg(BuildContext c, ThemeMode m, IconData icon, String label) {
    final active = mode == m;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 36,
          decoration: BoxDecoration(
            gradient: active
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: AppColors.brandGradient,
                  )
                : null,
            borderRadius: BorderRadius.circular(AppRadius.xs),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.40),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14,
                  color: active ? Colors.white : AppColors.textSub(c)),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : AppColors.textSub(c),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// 2x2 grid of personal usage stats — devices in this home, days
/// active, top scene, AI conversations. Replaces the old "Legal"
/// section in profile so users see something that's actually about
/// them, not boilerplate.
class _UsageStatsPanel extends ConsumerStatefulWidget {
  const _UsageStatsPanel();

  @override
  ConsumerState<_UsageStatsPanel> createState() => _UsageStatsPanelState();
}

class _UsageStatsPanelState extends ConsumerState<_UsageStatsPanel> {
  int _deviceCount = 0;
  int _daysActive = 1;
  String _topScene = '—';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = (selectedHome?['home_id'] ??
            selectedHome?['id'] ??
            selectedHome?['homeid'])
        ?.toString();

    final results = await Future.wait([
      UsageStatsService.daysActive(),
      UsageStatsService.sceneCounts(),
      if (homeId != null && homeId.isNotEmpty)
        ApiService.fetchDevices(homeId)
      else
        Future.value(<dynamic>[]),
    ]);

    if (!mounted) return;

    final days = results[0] as int;
    final counts = results[1] as Map<String, int>;
    final devices = (results[2] as List?) ?? const [];

    String topKey = '';
    int topVal = 0;
    counts.forEach((k, v) {
      if (v > topVal) {
        topVal = v;
        topKey = k;
      }
    });
    final topLabel = topKey.isEmpty
        ? '—'
        : ScenePresets.byKey(topKey).label;

    setState(() {
      _deviceCount = devices.length;
      _daysActive = days;
      _topScene = topLabel;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.95,
      children: [
        _statTile(
          context,
          icon: Icons.devices_rounded,
          color: AppColors.primaryBlue,
          color2: AppColors.primaryViolet,
          label: 'Devices',
          value: _deviceCount.toString(),
          numeric: _deviceCount,
        ),
        _statTile(
          context,
          icon: Icons.calendar_today_rounded,
          color: AppColors.accentGreen,
          color2: AppColors.teal,
          label: 'Days active',
          value: _daysActive.toString(),
          numeric: _daysActive,
        ),
        _statTile(
          context,
          icon: Icons.auto_awesome_rounded,
          color: AppColors.accentAmber,
          color2: AppColors.accentOrange,
          label: 'Top scene',
          value: _topScene,
        ),
      ],
    );
  }

  Widget _statTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required Color color2,
    required String label,
    required String value,
    int? numeric,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.card(context),
            Color.alphaBlend(
              color.withValues(alpha: isDark ? 0.18 : 0.10),
              AppColors.card(context),
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.30),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, color2],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.50),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              numeric != null
                  ? TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: numeric.toDouble()),
                      duration: const Duration(milliseconds: 750),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => Text(
                        v.round().toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.text(context),
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          letterSpacing: -0.5,
                        ),
                      ),
                    )
                  : Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text(context),
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                        letterSpacing: -0.3,
                      ),
                    ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textSub(context),
                  fontSize: 11,
                  height: 1.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Profile tile that opens [GuestManagementScreen]. Pre-fetches the
/// member count for the currently-selected home so the subtitle can show
/// "X guests" — discoverable without entering the screen.
class _GuestManagementTile extends ConsumerStatefulWidget {
  const _GuestManagementTile({required this.home});

  final Map<String, dynamic> home;

  @override
  ConsumerState<_GuestManagementTile> createState() =>
      _GuestManagementTileState();
}

class _GuestManagementTileState extends ConsumerState<_GuestManagementTile> {
  int? _guestCount;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchCount());
  }

  Future<void> _fetchCount() async {
    final homeId = (widget.home['home_id'] ??
            widget.home['id'] ??
            widget.home['homeid'])
        ?.toString();
    if (homeId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final members = await ApiService.fetchHomeMembers(homeId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _guestCount = members
          ?.where((m) => (m['role'] ?? '').toString().toLowerCase() != 'admin')
          .length;
    });
  }

  @override
  Widget build(BuildContext context) {
    String subtitle;
    if (_loading) {
      subtitle = 'Loading members…';
    } else if (_guestCount == null) {
      subtitle = 'See who has access · revoke guests';
    } else if (_guestCount == 0) {
      subtitle = 'No guests yet · invite via QR';
    } else if (_guestCount == 1) {
      subtitle = '1 guest · tap to manage';
    } else {
      subtitle = '$_guestCount guests · tap to manage';
    }

    return ListTile(
      onTap: () {
        Navigator.push(
          context,
          AppMotion.fadeSlideRoute(const GuestManagementScreen()),
        ).then((_) => _fetchCount());
      },
      leading: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.primaryViolet.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.group_rounded,
            color: AppColors.primaryViolet, size: 20),
      ),
      title: Text(
        'Guest Management',
        style: TextStyle(
          color: AppColors.text(context),
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: AppColors.textSub(context),
          fontSize: 12,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_guestCount != null && _guestCount! > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryViolet.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primaryViolet.withValues(alpha: 0.40),
                ),
              ),
              child: Text(
                '$_guestCount',
                style: TextStyle(
                  color: AppColors.primaryViolet,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_forward_ios,
            color: AppColors.textSub(context),
            size: 14,
          ),
        ],
      ),
    );
  }
}
