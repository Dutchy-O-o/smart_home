import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../providers/home_provider.dart';
import '../../services/api_service.dart';
import 'automation_create_screen.dart';
import 'automation_history_sheet.dart';

enum _Filter { all, active, ai, sensor }

class AutomationsListScreen extends ConsumerStatefulWidget {
  const AutomationsListScreen({super.key});

  @override
  ConsumerState<AutomationsListScreen> createState() =>
      _AutomationsListScreenState();
}

class _AutomationsListScreenState extends ConsumerState<AutomationsListScreen> {
  bool _isLoading = true;
  List<dynamic> _automations = [];
  String _errorMessage = '';
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _fetchAutomations();
  }

  Future<void> _fetchAutomations() async {
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = (selectedHome?['home_id'] ??
            selectedHome?['id'] ??
            selectedHome?['homeid'])
        ?.toString();

    if (homeId == null || homeId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Home ID not found.';
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final data = await ApiService.fetchAutomations(homeId);

    if (mounted) {
      setState(() {
        if (data != null) {
          _automations = data;
        } else {
          _errorMessage = 'Failed to load automations.';
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _openCreate({Map<String, dynamic>? existing}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AutomationCreateScreen(existingData: existing),
      ),
    );
    if (mounted) _fetchAutomations();
    if (result == true && mounted) _fetchAutomations();
  }

  void _showHistorySheet() {
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = (selectedHome?['home_id'] ??
            selectedHome?['id'] ??
            selectedHome?['homeid'])
        ?.toString();

    if (homeId == null || homeId.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (_) => AutomationHistorySheet(homeId: homeId),
    );
  }

  bool _isAi(dynamic auto) {
    final cond = (auto['trigger_condition'] ?? '').toString().toLowerCase();
    return cond.contains('emotion') || cond.contains('mood');
  }

  List<dynamic> get _filtered {
    return _automations.where((a) {
      switch (_filter) {
        case _Filter.all:
          return true;
        case _Filter.active:
          return a['is_enabled'] == true;
        case _Filter.ai:
          return _isAi(a);
        case _Filter.sensor:
          return !_isAi(a);
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (!_isLoading && _automations.isNotEmpty) ...[
              const SizedBox(height: 4),
              _buildStats(),
              const SizedBox(height: 16),
              _buildFilters(),
              const SizedBox(height: 8),
            ],
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryBlue,
        elevation: 4,
        onPressed: () => _openCreate(),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'New',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.maybePop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderCol(context)),
              ),
              child: Icon(Icons.arrow_back,
                  size: 20, color: AppColors.text(context)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Automations',
                  style: TextStyle(
                    color: AppColors.text(context),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Manage your smart triggers',
                  style: TextStyle(
                    color: AppColors.textSub(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _showHistorySheet,
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderCol(context)),
              ),
              child: Icon(Icons.history,
                  size: 20, color: AppColors.textSub(context)),
            ),
          ),
          GestureDetector(
            onTap: _isLoading ? null : _fetchAutomations,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderCol(context)),
              ),
              child: Icon(Icons.refresh,
                  size: 20, color: AppColors.textSub(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    final active =
        _automations.where((a) => a['is_enabled'] == true).length;
    final ai = _automations.where(_isAi).length;
    final total = _automations.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _statTile('Total', '$total', AppColors.primaryBlue, Icons.layers),
          const SizedBox(width: 10),
          _statTile('Active', '$active', AppColors.accentGreen,
              Icons.flash_on),
          const SizedBox(width: 10),
          _statTile('AI', '$ai', AppColors.accentOrange, Icons.face_retouching_natural),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.card(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderCol(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text(context),
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      )),
                  Text(label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSub(context),
                        fontSize: 10.5,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return SizedBox(
      height: 36,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip('All', _Filter.all),
          _filterChip('Active', _Filter.active),
          _filterChip('AI', _Filter.ai),
          _filterChip('Sensor', _Filter.sensor),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _Filter f) {
    final selected = _filter == f;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = f),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryBlue
                : AppColors.card(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.primaryBlue
                  : AppColors.borderCol(context),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.text(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }

    if (_errorMessage.isNotEmpty && _automations.isEmpty) {
      return _buildErrorState();
    }

    if (_automations.isEmpty) {
      return _buildEmptyState();
    }

    final list = _filtered;
    if (list.isEmpty) {
      return Center(
        child: Text(
          'No results in this filter.',
          style: TextStyle(color: AppColors.textSub(context), fontSize: 14),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryBlue,
      onRefresh: _fetchAutomations,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        itemCount: list.length,
        itemBuilder: (context, i) => _buildAutomationCard(list[i]),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppColors.accentRed.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_off,
                  color: AppColors.accentRed, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text(context), fontSize: 15),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: _fetchAutomations,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primaryBlue.withValues(alpha: 0.3),
                    AppColors.primaryBlue.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome,
                  color: AppColors.primaryBlue, size: 44),
            ),
            const SizedBox(height: 20),
            Text(
              'No automations yet',
              style: TextStyle(
                color: AppColors.text(context),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Trigger your devices automatically based on\nsensor data or mood.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSub(context), fontSize: 13),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                elevation: 0,
              ),
              onPressed: () => _openCreate(),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Create your first automation',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutomationCard(dynamic auto) {
    final name = auto['rule_name'] ?? 'Untitled';
    final isEnabled = auto['is_enabled'] ?? false;
    final condition = (auto['trigger_condition'] ?? '').toString();
    final actions = (auto['actions'] as List<dynamic>?) ?? [];
    final isAI = _isAi(auto);
    final accent = isAI ? AppColors.accentOrange : AppColors.primaryBlue;

    return Dismissible(
      key: Key(auto['rule_id']?.toString() ?? UniqueKey().toString()),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmAndDelete(auto),
      onDismissed: (_) {
        setState(() => _automations.remove(auto));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"$name" deleted'),
              backgroundColor: AppColors.card(context),
            ),
          );
        }
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.accentRed,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, color: Colors.white),
            SizedBox(width: 6),
            Text('Delete',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      child: GestureDetector(
        onTap: () => _openCreate(existing: auto),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isEnabled
                  ? accent.withValues(alpha: 0.35)
                  : AppColors.borderCol(context),
              width: isEnabled ? 1.2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isAI ? Icons.face_retouching_natural : Icons.sensors,
                        color: accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              color: AppColors.text(context),
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 6, height: 6,
                                decoration: BoxDecoration(
                                  color: isEnabled
                                      ? AppColors.accentGreen
                                      : AppColors.textSub(context),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isEnabled ? 'Active' : 'Disabled',
                                style: TextStyle(
                                  color: isEnabled
                                      ? AppColors.accentGreen
                                      : AppColors.textSub(context),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        color: AppColors.textSub(context), size: 22),
                  ],
                ),
                const SizedBox(height: 14),
                _conditionPill(condition, accent),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: actions.map<Widget>(_actionChip).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _conditionPill(String condition, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, size: 13, color: accent),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              condition.isEmpty ? 'No condition' : condition,
              style: TextStyle(
                color: accent,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip(dynamic act) {
    final det = act['details'] ?? {};
    final name = (act['device_name'] ?? '?').toString();
    String label;
    if (det['power'] == 'off' || det['state'] == 'off') {
      label = 'Off';
    } else {
      final parts = <String>['On'];
      if (det['brightness'] != null) parts.add('${det['brightness']}%');
      if (det['volume'] != null) parts.add('Vol ${det['volume']}');
      if (det['playback'] != null) parts.add('${det['playback']}');
      if (det['position'] != null) parts.add('${det['position']}%');
      label = parts.join(' · ');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bg(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderCol(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: TextStyle(
              color: AppColors.text(context),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            ' → ',
            style: TextStyle(
                color: AppColors.textSub(context), fontSize: 11),
          ),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSub(context),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmAndDelete(dynamic auto) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete automation',
            style: TextStyle(color: AppColors.text(context))),
        content: Text(
          'This automation will be permanently deleted. Are you sure?',
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
            child: const Text('Delete',
                style: TextStyle(color: AppColors.accentRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    final ruleId = auto['rule_id'];
    if (ruleId == null) return false;
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = (selectedHome?['home_id'] ??
            selectedHome?['id'] ??
            selectedHome?['homeid'])
        ?.toString();
    if (homeId == null) return false;

    final ok = await ApiService.deleteAutomation(homeId, ruleId.toString());
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delete failed.'),
          backgroundColor: AppColors.accentRed,
        ),
      );
    }
    return ok;
  }
}
