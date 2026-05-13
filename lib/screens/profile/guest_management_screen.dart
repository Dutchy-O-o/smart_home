import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../constants/app_colors.dart';
import '../../services/api_service.dart';
import '../../theme/app_spacing.dart';

/// Profile → Guest Management screen.
///
/// Lists every home where the caller has role='admin', expands to show the
/// members of each home, and lets the admin revoke any guest. Uses the new
/// `/{homeID}/members` and `DELETE /{homeID}/members/{userID}` Lambdas
/// (see backend/GUEST_MANAGEMENT_DEPLOY.md).
///
/// Degrades gracefully when the endpoints aren't deployed yet: instead of
/// crashing we show "Backend not deployed" empty state with a hint.
class GuestManagementScreen extends ConsumerStatefulWidget {
  const GuestManagementScreen({super.key});

  @override
  ConsumerState<GuestManagementScreen> createState() =>
      _GuestManagementScreenState();
}

class _GuestManagementScreenState extends ConsumerState<GuestManagementScreen> {
  bool _loadingHomes = true;
  String? _loadHomesError;
  List<Map<String, dynamic>> _adminHomes = [];

  /// homeId → fetch status. `null` while pending, list when loaded,
  /// empty list when 404/403.
  final Map<String, List<Map<String, dynamic>>?> _membersByHome = {};
  final Map<String, bool> _loadingMembers = {};
  final Map<String, bool> _expanded = {};
  bool _endpointUnavailable = false;

  @override
  void initState() {
    super.initState();
    _loadAdminHomes();
  }

  Future<void> _loadAdminHomes() async {
    setState(() {
      _loadingHomes = true;
      _loadHomesError = null;
    });
    try {
      final session = await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
      final token = session.userPoolTokensResult.value.idToken.raw;
      final res = await http.get(
        Uri.parse('${ApiService.baseUrl}/homes'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (res.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _loadingHomes = false;
          _loadHomesError = 'Could not load your homes (HTTP ${res.statusCode}).';
        });
        return;
      }

      final body = jsonDecode(res.body);
      final all = (body['homes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final admin = all.where((h) {
        final r = (h['role'] ?? '').toString().toLowerCase();
        return r == 'admin';
      }).toList();

      if (!mounted) return;
      setState(() {
        _adminHomes = admin;
        _loadingHomes = false;
      });

      // Auto-expand a single home so the admin sees their guests immediately.
      if (admin.length == 1) {
        final id = _homeId(admin.first);
        if (id != null) _toggleHome(id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingHomes = false;
        _loadHomesError = 'Network error: $e';
      });
    }
  }

  String? _homeId(Map<String, dynamic> home) =>
      (home['home_id'] ?? home['id'] ?? home['homeid'])?.toString();

  Future<void> _toggleHome(String homeId) async {
    setState(() => _expanded[homeId] = !(_expanded[homeId] ?? false));
    if (_expanded[homeId] == true && _membersByHome[homeId] == null) {
      await _fetchMembers(homeId);
    }
  }

  Future<void> _fetchMembers(String homeId) async {
    setState(() => _loadingMembers[homeId] = true);
    final members = await ApiService.fetchHomeMembers(homeId);
    if (!mounted) return;
    setState(() {
      _loadingMembers[homeId] = false;
      _membersByHome[homeId] = members ?? const [];
      // If the very first home returned null (not deployed / 403), surface
      // the friendly banner. Don't overwrite once we've seen success.
      if (members == null && _membersByHome.values.every((v) {
        return v == null || v.isEmpty;
      })) {
        _endpointUnavailable = true;
      }
    });
  }

  /// Promote a guest to admin or demote an admin to guest. Optimistic UI
  /// update with rollback on failure — same pattern as _revokeGuest so
  /// the screen feels instant. Backend refuses to demote the last admin
  /// (409 with a friendly message).
  Future<void> _changeRole(
    String homeId,
    Map<String, dynamic> member,
    String homeName,
    String newRole,
  ) async {
    final userId = member['user_id']?.toString();
    if (userId == null) return;
    final label = (member['name'] ?? member['email'] ?? 'this member').toString();
    final verb = newRole == 'admin' ? 'Promote' : 'Demote';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text(
          '$verb $label?',
          style: TextStyle(color: AppColors.text(context)),
        ),
        content: Text(
          newRole == 'admin'
              ? '$label will gain admin rights: device control, automations, and inviting new members.'
              : "$label will lose admin rights and become a regular guest.",
          style: TextStyle(color: AppColors.textSub(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSub(context))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              verb,
              style: TextStyle(
                color: newRole == 'admin'
                    ? AppColors.primaryBlue
                    : AppColors.accentAmber,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    // Optimistic: flip the role locally so the chip updates immediately.
    final prevRole = (member['role'] ?? '').toString();
    setState(() {
      final list = List<Map<String, dynamic>>.from(_membersByHome[homeId] ?? []);
      final idx = list.indexWhere((m) => m['user_id'] == userId);
      if (idx >= 0) {
        list[idx] = {...list[idx], 'role': newRole};
      }
      _membersByHome[homeId] = list;
    });

    final result = await ApiService.updateMemberRole(
      homeId: homeId,
      userId: userId,
      newRole: newRole,
    );
    if (!mounted) return;

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          newRole == 'admin'
              ? '$label promoted to admin'
              : '$label demoted to guest',
        ),
        backgroundColor: AppColors.accentGreen,
      ));
    } else {
      // Rollback on failure (e.g. 409 last-admin protection).
      setState(() {
        final list =
            List<Map<String, dynamic>>.from(_membersByHome[homeId] ?? []);
        final idx = list.indexWhere((m) => m['user_id'] == userId);
        if (idx >= 0) {
          list[idx] = {...list[idx], 'role': prevRole};
        }
        _membersByHome[homeId] = list;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.errorMessage ?? "Couldn't change role."),
        backgroundColor: AppColors.accentRed,
      ));
    }
  }

  Future<void> _revokeGuest(
      String homeId, Map<String, dynamic> guest, String homeName) async {
    final guestLabel = (guest['name'] ?? guest['email'] ?? 'this guest').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text('Revoke access?',
            style: TextStyle(color: AppColors.text(context))),
        content: Text(
          '$guestLabel will lose access to "$homeName" immediately.',
          style: TextStyle(color: AppColors.textSub(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSub(context))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke',
                style: TextStyle(
                    color: AppColors.accentRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    final userId = guest['user_id']?.toString();
    if (userId == null) return;

    // Optimistic removal so the UI feels instant; if the API rejects we
    // add it back and surface the reason.
    final removed = guest;
    final list = List<Map<String, dynamic>>.from(_membersByHome[homeId] ?? []);
    final idx = list.indexWhere((m) => m['user_id'] == userId);
    setState(() {
      if (idx >= 0) list.removeAt(idx);
      _membersByHome[homeId] = list;
    });

    final result = await ApiService.revokeGuestAccess(
      homeId: homeId,
      userId: userId,
    );

    if (!mounted) return;
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Removed $guestLabel'),
        backgroundColor: AppColors.accentGreen,
      ));
    } else {
      // Restore on failure.
      setState(() {
        final restored = List<Map<String, dynamic>>.from(_membersByHome[homeId] ?? []);
        if (idx >= 0 && idx <= restored.length) {
          restored.insert(idx, removed);
        } else {
          restored.add(removed);
        }
        _membersByHome[homeId] = restored;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.errorMessage ?? 'Could not remove member.'),
        backgroundColor: AppColors.accentRed,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.text(context)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryBlue,
          backgroundColor: AppColors.card(context),
          onRefresh: () async {
            _membersByHome.clear();
            _loadingMembers.clear();
            _expanded.clear();
            _endpointUnavailable = false;
            await _loadAdminHomes();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              if (_loadingHomes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryBlue,
                      strokeWidth: 2.5,
                    ),
                  ),
                )
              else if (_loadHomesError != null)
                _errorCard(_loadHomesError!)
              else if (_adminHomes.isEmpty)
                _emptyState()
              else ...[
                if (_endpointUnavailable) _backendUnavailableBanner(),
                for (int i = 0; i < _adminHomes.length; i++)
                  _buildHomeSection(_adminHomes[i])
                      .animate(delay: (80 * i).ms)
                      .fadeIn(duration: 360.ms)
                      .slideY(begin: 0.08, end: 0),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
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
          child: const Icon(Icons.group_rounded, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Guest Management',
                style: TextStyle(
                  color: AppColors.text(context),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.05,
                ),
              ),
              Text(
                'People with access to your homes',
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
    );
  }

  Widget _buildHomeSection(Map<String, dynamic> home) {
    final homeId = _homeId(home) ?? '';
    final homeName = (home['home_name'] ?? 'Home').toString();
    final expanded = _expanded[homeId] ?? false;
    final members = _membersByHome[homeId];
    final loading = _loadingMembers[homeId] == true;
    final guests = members?.where((m) {
          final r = (m['role'] ?? '').toString().toLowerCase();
          return r != 'admin';
        }).toList() ??
        const [];
    final admins = members?.where((m) {
          final r = (m['role'] ?? '').toString().toLowerCase();
          return r == 'admin';
        }).toList() ??
        const [];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderCol(context)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _toggleHome(homeId),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.primaryBlue,
                          AppColors.primaryViolet,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color:
                              AppColors.primaryBlue.withValues(alpha: 0.40),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.home_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          homeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.text(context),
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          members == null
                              ? (loading ? 'Loading…' : 'Tap to load members')
                              : '${guests.length} guest${guests.length == 1 ? '' : 's'} · ${admins.length} admin${admins.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: AppColors.textSub(context),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 220),
                    turns: expanded ? 0.5 : 0,
                    child: Icon(Icons.expand_more_rounded,
                        color: AppColors.textSub(context)),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 240),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(
              children: [
                Divider(height: 1, color: AppColors.borderCol(context)),
                if (loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: AppColors.primaryBlue,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  )
                else if (members == null)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      "Couldn't load members for this home.",
                      style: TextStyle(
                        color: AppColors.textSub(context),
                        fontSize: 12.5,
                      ),
                    ),
                  )
                else if (admins.isEmpty && guests.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'No members yet.',
                      style: TextStyle(
                        color: AppColors.textSub(context),
                        fontSize: 12.5,
                      ),
                    ),
                  )
                else
                  Column(
                    children: [
                      for (final m in admins)
                        _memberRow(m, homeId, homeName, isAdmin: true),
                      if (admins.isNotEmpty && guests.isNotEmpty)
                        Divider(
                          height: 1,
                          color: AppColors.borderCol(context)
                              .withValues(alpha: 0.5),
                          indent: 70,
                        ),
                      for (final m in guests)
                        _memberRow(m, homeId, homeName, isAdmin: false),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberRow(
    Map<String, dynamic> member,
    String homeId,
    String homeName, {
    required bool isAdmin,
  }) {
    final name = (member['name'] ?? '').toString();
    final email = (member['email'] ?? '').toString();
    final userId = (member['user_id'] ?? '').toString();
    final isYou = member['is_you'] == true;
    final initial = name.isNotEmpty
        ? name[0].toUpperCase()
        : (email.isNotEmpty ? email[0].toUpperCase() : '?');
    final displayLabel = name.isNotEmpty
        ? name
        : (email.isNotEmpty ? email : _shortUserId(userId));
    final subtitle = name.isNotEmpty && email.isNotEmpty ? email : null;

    final accent = isAdmin ? AppColors.primaryBlue : AppColors.accentAmber;
    final accent2 = isAdmin ? AppColors.primaryViolet : AppColors.accentOrange;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, accent2],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.40),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.text(context),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isYou) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'YOU',
                          style: TextStyle(
                            color: AppColors.primaryBlue,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSub(context),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.40),
                        ),
                      ),
                      child: Text(
                        isAdmin ? 'ADMIN' : 'GUEST',
                        style: TextStyle(
                          color: accent,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    if (_joinedAgo(member['joined_at']) != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '· ${_joinedAgo(member['joined_at'])}',
                        style: TextStyle(
                          color: AppColors.textSub(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (!isYou)
            _MemberActionMenu(
              isAdmin: isAdmin,
              onPromote: isAdmin
                  ? null
                  : () => _changeRole(homeId, member, homeName, 'admin'),
              onDemote: isAdmin
                  ? () => _changeRole(homeId, member, homeName, 'guest')
                  : null,
              onRevoke: isAdmin
                  ? null
                  : () => _revokeGuest(homeId, member, homeName),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _shortUserId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 8)}…${id.substring(id.length - 4)}';
  }

  /// "joined 2 days ago" / "joined yesterday" / "joined today" / null when
  /// the value is missing or malformed. Server returns ISO 8601 strings;
  /// we parse defensively because a future schema change could surface
  /// null here.
  String? _joinedAgo(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString();
    if (s.isEmpty) return null;
    final dt = DateTime.tryParse(s);
    if (dt == null) return null;
    final diff = DateTime.now().toUtc().difference(dt.toUtc());
    if (diff.inMinutes < 60) return 'joined just now';
    if (diff.inHours < 24) return 'joined ${diff.inHours}h ago';
    if (diff.inDays == 1) return 'joined yesterday';
    if (diff.inDays < 30) return 'joined ${diff.inDays}d ago';
    if (diff.inDays < 365) return 'joined ${(diff.inDays / 30).floor()}mo ago';
    return 'joined ${(diff.inDays / 365).floor()}y ago';
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryBlue.withValues(alpha: 0.18),
                  AppColors.primaryViolet.withValues(alpha: 0.10),
                ],
              ),
            ),
            child: Icon(Icons.shield_outlined,
                color: AppColors.primaryBlue, size: 44),
          ),
          const SizedBox(height: 18),
          Text(
            "You're not an admin of any home",
            style: TextStyle(
              color: AppColors.text(context),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Only home admins can manage guests. Ask the admin to share QR codes from their app.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSub(context),
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accentRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.accentRed.withValues(alpha: 0.40),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.accentRed),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppColors.text(context),
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: _loadAdminHomes,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _backendUnavailableBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accentAmber.withValues(alpha: 0.15),
            AppColors.accentOrange.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.accentAmber.withValues(alpha: 0.40),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.accentAmber),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Guest list endpoint isn't deployed yet. Deploy the two Lambdas in backend/GUEST_MANAGEMENT_DEPLOY.md to enable management.",
              style: TextStyle(
                color: AppColors.text(context),
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Three-dot action menu shown on each member row. Adapts the available
/// actions to the member's current role: guests can be promoted or revoked,
/// admins can only be demoted (revoke flow doesn't touch admins — they
/// must be demoted first). Hidden entirely for the calling user (handled
/// at the call site).
class _MemberActionMenu extends StatelessWidget {
  const _MemberActionMenu({
    required this.isAdmin,
    this.onPromote,
    this.onDemote,
    this.onRevoke,
  });

  final bool isAdmin;
  final VoidCallback? onPromote;
  final VoidCallback? onDemote;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Member actions',
      icon: Icon(Icons.more_vert_rounded, color: AppColors.textSub(context)),
      color: AppColors.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.borderCol(context)),
      ),
      onSelected: (value) {
        switch (value) {
          case 'promote':
            onPromote?.call();
            break;
          case 'demote':
            onDemote?.call();
            break;
          case 'revoke':
            onRevoke?.call();
            break;
        }
      },
      itemBuilder: (ctx) => [
        if (onPromote != null)
          PopupMenuItem<String>(
            value: 'promote',
            child: Row(
              children: [
                Icon(Icons.arrow_upward_rounded,
                    color: AppColors.primaryBlue, size: 18),
                const SizedBox(width: 10),
                Text(
                  'Promote to admin',
                  style: TextStyle(
                    color: AppColors.text(ctx),
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        if (onDemote != null)
          PopupMenuItem<String>(
            value: 'demote',
            child: Row(
              children: [
                Icon(Icons.arrow_downward_rounded,
                    color: AppColors.accentAmber, size: 18),
                const SizedBox(width: 10),
                Text(
                  'Demote to guest',
                  style: TextStyle(
                    color: AppColors.text(ctx),
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        if (onRevoke != null) ...[
          const PopupMenuDivider(height: 6),
          PopupMenuItem<String>(
            value: 'revoke',
            child: Row(
              children: [
                Icon(Icons.person_remove_rounded,
                    color: AppColors.accentRed, size: 18),
                const SizedBox(width: 10),
                Text(
                  'Revoke access',
                  style: TextStyle(
                    color: AppColors.accentRed,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
