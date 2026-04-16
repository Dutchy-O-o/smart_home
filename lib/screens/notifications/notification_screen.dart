import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../providers/alert_provider.dart';

class NotificationScreen extends ConsumerWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(filteredAlertsProvider);
    final filter = ref.watch(alertFilterProvider);

    final today = alerts.where((a) => a.day == 'today').toList();
    final earlier = alerts.where((a) => a.day != 'today').toList();
    final criticalCount =
        today.where((a) => a.level == AlertLevel.critical).length;

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
                        if (today.isNotEmpty) ...[
                          _SectionHeader(
                            title: 'Today',
                            badgeCount: criticalCount,
                          ),
                          const SizedBox(height: 16),
                          ...today.map((a) => _DismissibleAlert(alert: a, ref: ref)),
                          const SizedBox(height: 24),
                        ],
                        if (earlier.isNotEmpty) ...[
                          Text(
                            'Earlier',
                            style: TextStyle(
                              color: AppColors.text(context),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ...earlier.map((a) => _DismissibleAlert(alert: a, ref: ref)),
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
      padding: const EdgeInsets.fromLTRB(20, 20, 8, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Notifications',
              style: TextStyle(
                color: AppColors.text(context),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (hasAlerts) ...[
            TextButton(
              onPressed: onMarkAllRead,
              child: const Text(
                'Read all',
                style: TextStyle(color: AppColors.primaryBlue),
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_sweep,
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
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryBlue : AppColors.card(context),
          borderRadius: BorderRadius.circular(20),
          border: isActive ? null : Border.all(color: AppColors.borderCol(context)),
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
          borderRadius: BorderRadius.circular(20),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none,
              size: 64,
              color: AppColors.textSub(context),
            ),
            const SizedBox(height: 16),
            Text(
              isFiltered
                  ? 'No notifications match this filter.'
                  : 'No notifications yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSub(context),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.alert});
  final AlertItem alert;

  static const Map<AlertType, IconData> _typeIcons = {
    AlertType.security: Icons.security,
    AlertType.emotion: Icons.sentiment_satisfied_alt,
    AlertType.device: Icons.devices,
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

  @override
  Widget build(BuildContext context) {
    final color = _colorFor();
    final icon = _typeIcons[alert.type] ?? Icons.notifications;
    final isCritical = alert.level == AlertLevel.critical;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 6, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alert.title,
                              style: TextStyle(
                                color: AppColors.text(context),
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
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
          borderRadius: BorderRadius.circular(16),
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
