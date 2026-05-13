import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../providers/alert_provider.dart';
import '../../providers/home_provider.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/empty_state.dart';

class NotificationScreen extends ConsumerStatefulWidget {
  const NotificationScreen({super.key});

  @override
  ConsumerState<NotificationScreen> createState() =>
      _NotificationScreenState();
}

class _NotificationScreenState extends ConsumerState<NotificationScreen> {
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Pull canonical list from AWS on open so notifications survive
      // reinstalls and show across devices. Fire-and-forget — stale
      // local list shows immediately, gets replaced once AWS responds.
      // No-op when the route isn't deployed.
      if (_hydrated) return;
      _hydrated = true;
      final selectedHome = ref.read(selectedHomeProvider);
      final homeId = (selectedHome?['home_id'] ??
              selectedHome?['id'] ??
              selectedHome?['homeid'])
          ?.toString() ??
          '';
      if (homeId.isNotEmpty) {
        ref.read(alertListProvider.notifier).hydrateFromAws(homeId);
      }
    });
  }

  /// Groups alerts into Today / Yesterday / This week / Earlier buckets.
  /// Alert ids are stamped with `millisecondsSinceEpoch` (see main.dart),
  /// so we read the timestamp out of the id when present and fall back to
  /// the legacy [AlertItem.day] string ('today' / non-today) for older
  /// entries.
  static Map<String, List<AlertItem>> _groupByRelativeDay(
      List<AlertItem> alerts) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekStart = today.subtract(const Duration(days: 7));
    final result = <String, List<AlertItem>>{
      'Today': [],
      'Yesterday': [],
      'This week': [],
      'Earlier': [],
    };
    for (final a in alerts) {
      final ts = int.tryParse(a.id);
      DateTime? when;
      if (ts != null) {
        when = DateTime.fromMillisecondsSinceEpoch(ts);
      }
      final whenDay = when == null
          ? null
          : DateTime(when.year, when.month, when.day);
      String bucket;
      if (whenDay == null) {
        bucket = a.day == 'today' ? 'Today' : 'Earlier';
      } else if (whenDay == today) {
        bucket = 'Today';
      } else if (whenDay == yesterday) {
        bucket = 'Yesterday';
      } else if (whenDay.isAfter(weekStart)) {
        bucket = 'This week';
      } else {
        bucket = 'Earlier';
      }
      result[bucket]!.add(a);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(filteredAlertsProvider);
    final filter = ref.watch(alertFilterProvider);

    final groups = _groupByRelativeDay(alerts);
    final criticalCount = (groups['Today'] ?? const [])
        .where((a) => a.level == AlertLevel.critical)
        .length;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              hasAlerts: alerts.isNotEmpty,
              onMarkAllRead: () {
                ref.read(alertListProvider.notifier).markAllRead();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All notifications marked as read.'),
                  ),
                );
              },
              onClearAll: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.card(context),
                    title: Text('Clear all notifications',
                        style: TextStyle(color: AppColors.text(context))),
                    content: Text(
                      'All notifications will be permanently removed.',
                      style: TextStyle(color: AppColors.textSub(context)),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text(
                          'Clear',
                          style: TextStyle(color: AppColors.accentRed),
                        ),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  ref.read(alertListProvider.notifier).clearAll();
                }
              },
            ),
            _FilterRow(filter: filter, ref: ref),
            Expanded(
              child: alerts.isEmpty
                  ? _EmptyState(isFiltered: filter.type != 'All' || filter.level != 'Any')
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      children: [
                        for (final entry in const [
                          'Today',
                          'Yesterday',
                          'This week',
                          'Earlier'
                        ])
                          if ((groups[entry] ?? const []).isNotEmpty) ...[
                            _SectionHeader(
                              title: entry,
                              badgeCount: entry == 'Today' ? criticalCount : 0,
                            ),
                            const SizedBox(height: 16),
                            ...groups[entry]!
                                .map((a) => _DismissibleAlert(
                                    alert: a, ref: ref)),
                            const SizedBox(height: 24),
                          ],
                        const SizedBox(height: 20),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.hasAlerts,
    required this.onMarkAllRead,
    required this.onClearAll,
  });
  final bool hasAlerts;
  final VoidCallback onMarkAllRead;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
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
            child: const Icon(Icons.notifications_active_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications',
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    height: 1.05,
                  ),
                ),
                Text(
                  hasAlerts ? 'Recent activity' : 'All caught up',
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (hasAlerts) ...[
            TextButton(
              onPressed: onMarkAllRead,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryBlue,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              child: const Text(
                'Read all',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_sweep_rounded,
                  color: AppColors.textSub(context)),
              tooltip: 'Clear all',
              onPressed: onClearAll,
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.filter, required this.ref});
  final AlertFilter filter;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text('TYPE',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    )),
                const SizedBox(width: 12),
                for (final t in const ['All', 'Security', 'Emotion', 'Device'])
                  _FilterChip(
                    label: t,
                    isActive: filter.type == t,
                    onTap: () =>
                        ref.read(alertFilterProvider.notifier).setType(t),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text('LEVEL',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    )),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Any',
                  isActive: filter.level == 'Any',
                  onTap: () =>
                      ref.read(alertFilterProvider.notifier).setLevel('Any'),
                ),
                _LevelChip(
                  label: 'Critical',
                  color: AppColors.accentRed,
                  isActive: filter.level == 'Critical',
                  onTap: () => ref
                      .read(alertFilterProvider.notifier)
                      .setLevel('Critical'),
                ),
                _LevelChip(
                  label: 'Warning',
                  color: AppColors.accentOrange,
                  isActive: filter.level == 'Warning',
                  onTap: () => ref
                      .read(alertFilterProvider.notifier)
                      .setLevel('Warning'),
                ),
                _LevelChip(
                  label: 'Info',
                  color: AppColors.primaryBlue,
                  isActive: filter.level == 'Info',
                  onTap: () =>
                      ref.read(alertFilterProvider.notifier).setLevel('Info'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: AppColors.brandGradient,
                )
              : null,
          color: isActive ? null : AppColors.card(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: isActive
              ? null
              : Border.all(color: AppColors.borderCol(context)),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.textSub(context),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.label,
    required this.color,
    required this.isActive,
    required this.onTap,
  });
  final String label;
  final Color color;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isActive ? color : color.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: AppColors.text(context),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.badgeCount});
  final String title;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.text(context),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (badgeCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accentRed.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border:
                  Border.all(color: AppColors.accentRed.withValues(alpha: 0.5)),
            ),
            child: Text(
              '$badgeCount CRITICAL',
              style: const TextStyle(
                color: AppColors.accentRed,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isFiltered});
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.notifications_none,
      title: isFiltered
          ? 'No notifications match this filter.'
          : 'No notifications yet.',
      message: isFiltered
          ? 'Try adjusting filters to see more.'
          : 'You\'ll see security, emotion, and device alerts here.',
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.alert});
  final AlertItem alert;

  static const Map<AlertType, IconData> _typeIcons = {
    AlertType.security: Icons.shield,
    AlertType.emotion: Icons.sentiment_satisfied_alt,
    AlertType.device: Icons.devices_other,
  };

  Color _colorFor() {
    switch (alert.level) {
      case AlertLevel.critical:
        return AppColors.accentRed;
      case AlertLevel.warning:
        return AppColors.accentOrange;
      case AlertLevel.info:
        return AppColors.primaryBlue;
    }
  }

  Color _typeAccent() {
    switch (alert.type) {
      case AlertType.security:
        return AppColors.accentRed;
      case AlertType.emotion:
        return AppColors.accentPink;
      case AlertType.device:
        return AppColors.primaryBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor();
    final icon = _typeIcons[alert.type] ?? Icons.notifications;
    final isCritical = alert.level == AlertLevel.critical;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 6, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Iconic type badge: circular gradient chip with the
                      // type's icon, plus a small dot in the corner showing
                      // severity at a glance.
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  _typeAccent(),
                                  Color.alphaBlend(
                                    Colors.white.withValues(alpha: 0.18),
                                    _typeAccent(),
                                  ),
                                ],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _typeAccent().withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child:
                                Icon(icon, color: Colors.white, size: 22),
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: AppColors.card(context),
                                    width: 2),
                              ),
                            ),
                          ),
                        ],
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
                                    alert.title,
                                    style: TextStyle(
                                      color: AppColors.text(context),
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (alert.count > 1) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: color.withValues(alpha: 0.5),
                                          width: 1),
                                    ),
                                    child: Text(
                                      '×${alert.count}',
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              alert.description,
                              style: TextStyle(
                                color: AppColors.textSub(context),
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
                          Text(
                            alert.time,
                            style: TextStyle(
                              color: AppColors.textSub(context),
                              fontSize: 11,
                            ),
                          ),
                          if (isCritical)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Icon(
                                Icons.warning,
                                color: AppColors.accentRed
                                    .withValues(alpha: 0.6),
                                size: 16,
                              ),
                            ),
                        ],
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

/// Wraps a notification card with swipe-to-dismiss that removes the alert
/// from the provider (and shows a quick undo snackbar).
class _DismissibleAlert extends StatelessWidget {
  const _DismissibleAlert({required this.alert, required this.ref});
  final AlertItem alert;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('alert_${alert.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 16),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.accentRed,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: Colors.white),
            SizedBox(width: 6),
            Text('Dismiss',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                )),
          ],
        ),
      ),
      onDismissed: (_) {
        ref.read(alertListProvider.notifier).dismiss(alert.id);
      },
      child: _NotificationCard(alert: alert),
    );
  }
}
