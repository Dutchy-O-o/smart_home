import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../providers/alert_provider.dart';

class NotificationScreen extends ConsumerWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(alertFilterProvider);
    final alerts = ref.watch(filteredAlertsProvider);
    final allAlerts = ref.watch(alertListProvider);

    final criticalCount = allAlerts.where((a) => a.level == AlertLevel.critical && !a.isRead).length;

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            // --- HEADER ---
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Notification Center",
                    style: TextStyle(
                      color: AppColors.text(context),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ref.read(alertListProvider.notifier).markAllRead();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("All notifications marked as read.")),
                      );
                    },
                    child: const Text(
                      "Mark all read",
                      style: TextStyle(color: AppColors.primaryBlue),
                    ),
                  ),
                ],
              ),
            ),

            // --- FILTERS ---
            SizedBox(
              height: 100,
              child: Column(
                children: [
                  // TYPE FILTER
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Text("TYPE", style: TextStyle(color: AppColors.textSub(context), fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 12),
                        _buildFilterBtn(context, "All", filter.type == "All", () => ref.read(alertFilterProvider.notifier).setType("All")),
                        _buildFilterBtn(context, "Security", filter.type == "Security", () => ref.read(alertFilterProvider.notifier).setType("Security")),
                        _buildFilterBtn(context, "Emotion", filter.type == "Emotion", () => ref.read(alertFilterProvider.notifier).setType("Emotion")),
                        _buildFilterBtn(context, "Device", filter.type == "Device", () => ref.read(alertFilterProvider.notifier).setType("Device")),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // LEVEL FILTER
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Text("LEVEL", style: TextStyle(color: AppColors.textSub(context), fontSize: 10, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        _buildFilterBtn(context, "Any", filter.level == "Any", () => ref.read(alertFilterProvider.notifier).setLevel("Any")),
                        _buildLevelBtn(context, "Critical", AppColors.accentRed, filter.level == "Critical", () => ref.read(alertFilterProvider.notifier).setLevel("Critical")),
                        _buildLevelBtn(context, "Warning", AppColors.accentOrange, filter.level == "Warning", () => ref.read(alertFilterProvider.notifier).setLevel("Warning")),
                        _buildLevelBtn(context, "Info", AppColors.primaryBlue, filter.level == "Info", () => ref.read(alertFilterProvider.notifier).setLevel("Info")),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // --- NOTIFICATION LIST ---
            Expanded(
              child: alerts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_off_outlined, color: AppColors.textSub(context), size: 64),
                          const SizedBox(height: 16),
                          Text(
                            filter.type == "All" && filter.level == "Any"
                                ? "No notifications yet.\nAlerts from your sensors will appear here."
                                : "No notifications match this filter.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSub(context), fontSize: 15),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      itemCount: alerts.length + 1, // +1 for header
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "${alerts.length} Alert${alerts.length == 1 ? '' : 's'}",
                                  style: TextStyle(color: AppColors.text(context), fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                if (criticalCount > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentRed.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: AppColors.accentRed.withOpacity(0.5)),
                                    ),
                                    child: Text(
                                      "$criticalCount CRITICAL",
                                      style: const TextStyle(color: AppColors.accentRed, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }

                        final alert = alerts[index - 1];
                        return _buildAlertCard(context, ref, alert);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // --- ALERT CARD ---
  Widget _buildAlertCard(BuildContext context, WidgetRef ref, AlertItem alert) {
    final color = _colorForLevel(alert.level);
    final icon = _iconForType(alert.type, alert.level);

    return Dismissible(
      key: Key(alert.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => ref.read(alertListProvider.notifier).dismiss(alert.id),
      background: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.accentRed.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.2),
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
                                Text(alert.time, style: TextStyle(color: AppColors.textSub(context), fontSize: 11)),
                                if (!alert.isRead)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Container(
                                      width: 8, height: 8,
                                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),

                        // Security alert actions
                        if (alert.level == AlertLevel.critical) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              OutlinedButton(
                                onPressed: () {
                                  ref.read(alertListProvider.notifier).markRead(alert.id);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Alarm silenced.")),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.text(context),
                                  side: BorderSide(color: AppColors.borderCol(context)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  minimumSize: const Size(0, 36),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text("Silence Alarm", style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- FILTER WIDGETS ---
  Widget _buildFilterBtn(BuildContext context, String text, bool isActive, VoidCallback onTap) {
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
          text,
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.textSub(context),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildLevelBtn(BuildContext context, String text, Color color, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? color : color.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 6),
            Text(
              text,
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

  // --- HELPERS ---
  Color _colorForLevel(AlertLevel level) {
    switch (level) {
      case AlertLevel.critical: return AppColors.accentRed;
      case AlertLevel.warning: return AppColors.accentOrange;
      case AlertLevel.info: return AppColors.primaryBlue;
    }
  }

  IconData _iconForType(AlertType type, AlertLevel level) {
    if (level == AlertLevel.critical) return Icons.warning_amber_rounded;
    switch (type) {
      case AlertType.security: return Icons.security;
      case AlertType.emotion: return Icons.sentiment_satisfied_alt;
      case AlertType.device: return Icons.devices;
    }
  }
}
