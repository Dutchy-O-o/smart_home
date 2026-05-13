import 'dart:ui';
import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../services/api_service.dart';
import '../../theme/app_spacing.dart';

/// Bottom sheet that lists recent automation runs. Theme-aware (light + dark)
/// and grouped by relative date so a busy user can scan "today" first.
class AutomationHistorySheet extends StatefulWidget {
  final String homeId;

  const AutomationHistorySheet({super.key, required this.homeId});

  @override
  State<AutomationHistorySheet> createState() => _AutomationHistorySheetState();
}

class _AutomationHistorySheetState extends State<AutomationHistorySheet> {
  bool _isLoading = true;
  List<dynamic> _history = [];

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    final history = await ApiService.fetchAutomationHistory(widget.homeId);
    if (mounted) {
      setState(() {
        _history = history ?? [];
        _isLoading = false;
      });
    }
  }

  String _formatTime(DateTime dt) =>
      "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

  String _formatDate(DateTime dt) =>
      "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";

  /// Bucket label for grouping ("Today", "Yesterday", absolute date).
  String _bucketLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entryDay = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(entryDay).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This week';
    return _formatDate(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Group entries by bucket label, preserving original (newest-first) order.
    final grouped = <String, List<dynamic>>{};
    for (final item in _history) {
      final raw = (item['executed_at'] ?? '').toString();
      DateTime? dt;
      try {
        dt = DateTime.parse(raw).toLocal();
      } catch (_) {}
      final label = dt == null ? 'Unknown' : _bucketLabel(dt);
      grouped.putIfAbsent(label, () => []).add({...item, '_dt': dt});
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.78,
          decoration: BoxDecoration(
            color:
                AppColors.bg(context).withValues(alpha: isDark ? 0.92 : 0.96),
            border: Border(
              top: BorderSide(
                color: AppColors.borderCol(context).withValues(alpha: 0.6),
                width: 1.2,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Grab handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: AppColors.textSub(context).withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: AppColors.brandGradient,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color:
                              AppColors.primaryBlue.withValues(alpha: 0.40),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.history_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Execution History",
                          style: TextStyle(
                            color: AppColors.text(context),
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          _isLoading
                              ? 'Loading…'
                              : '${_history.length} automation run${_history.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color: AppColors.textSub(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: AppColors.textSub(context)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primaryBlue,
                          strokeWidth: 2.5,
                        ),
                      )
                    : _history.isEmpty
                        ? _emptyState(context)
                        : ListView(
                            physics: const BouncingScrollPhysics(),
                            children: [
                              for (final entry in grouped.entries) ...[
                                _bucketHeader(entry.key),
                                ...entry.value.map(_runTile),
                                const SizedBox(height: 14),
                              ],
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primaryBlue.withValues(alpha: 0.2),
                    AppColors.primaryViolet.withValues(alpha: 0.12),
                  ],
                ),
              ),
              child: Icon(
                Icons.timelapse_rounded,
                color: AppColors.primaryBlue,
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              "No runs yet",
              style: TextStyle(
                color: AppColors.text(context),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "When your automations fire, you'll see them here.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSub(context),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bucketHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: AppColors.textSub(context),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _runTile(dynamic item) {
    final ruleName = (item['rule_name'] ?? 'Unknown rule').toString();
    final dt = item['_dt'] as DateTime?;
    final timeStr = dt == null ? '' : _formatTime(dt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.borderCol(context),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.accentGreen,
                  Color.alphaBlend(
                    Colors.white.withValues(alpha: 0.25),
                    AppColors.accentGreen,
                  ),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accentGreen.withValues(alpha: 0.40),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ruleName,
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  dt == null ? 'Unknown time' : 'Ran successfully · $timeStr',
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
