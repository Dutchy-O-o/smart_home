import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../constants/app_colors.dart';
import '../../providers/home_provider.dart';
import '../../services/api_service.dart';
import 'automation_create_screen.dart';


class AutomationsListScreen extends ConsumerStatefulWidget {
  const AutomationsListScreen({super.key});

  @override
  ConsumerState<AutomationsListScreen> createState() => _AutomationsListScreenState();
}

class _AutomationsListScreenState extends ConsumerState<AutomationsListScreen> {
  bool _isLoading = true;
  List<dynamic> _automations = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchAutomations();
  }

  Future<void> _fetchAutomations() async {
    final selectedHome = ref.read(selectedHomeProvider);
    final homeId = (selectedHome?['home_id'] ?? selectedHome?['id'] ?? selectedHome?['homeid'])?.toString();
    
    if (homeId == null || homeId.isEmpty) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = "Home ID not found."; });
      return;
    }

    setState(() { _isLoading = true; _errorMessage = ''; });

    final data = await ApiService.fetchAutomations(homeId);
    
    if (mounted) {
      setState(() {
        if (data != null) {
          _automations = data;
        } else {
          _errorMessage = "Failed to load automations or connection could not be established.";
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: AppBar(
        title: Text("Home Automations", style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.text(context)),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryBlue,
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AutomationCreateScreen()),
          );
          if (result == true && mounted) {
             _fetchAutomations(); // Reload
          }
        },
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("New Automation", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryBlue));
    }
    
    if (_errorMessage.isNotEmpty && _automations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 16),
            Text(_errorMessage, style: TextStyle(color: AppColors.textSub(context), fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
              onPressed: _fetchAutomations,
              child: const Text("Tekrar Dene"),
            ),
          ],
        ),
      );
    }
    
    if (_automations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome, color: AppColors.textSub(context), size: 64),
            const SizedBox(height: 16),
            Text("You haven't created any automations yet.", style: TextStyle(color: AppColors.textSub(context), fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: _automations.length,
      itemBuilder: (context, index) {
        final auto = _automations[index];
        final name = auto['rule_name'] ?? 'Unnamed Automation';
        final isEnabled = auto['is_enabled'] ?? false;
        final condition = auto['trigger_condition'] ?? '';
        final actions = (auto['actions'] as List<dynamic>?) ?? [];
        
        bool isAI = condition.toString().contains('emotion');
        
        // Build action summary
        String actionSummary = "";
        if (actions.isEmpty) {
          actionSummary = "No actions configured";
        } else {
          List<String> actionTexts = [];
          for (var act in actions) {
            String actText = "\u2022 ${act['device_name']}: ";
            var det = act['details'] ?? {};
            if (det['power'] == 'off' || det['state'] == 'off') {
              actText += "Turn Off";
            } else {
              List<String> props = ["Turn On"];
              if (det['brightness'] != null) props.add("Brightness ${det['brightness']}%");
              if (det['volume'] != null) props.add("Vol ${det['volume']}%");
              if (det['playback'] != null) props.add("${det['playback']}");
              if (det['position'] != null) props.add("Open ${det['position']}%");
              actText += props.join(', ');
            }
            actionTexts.add(actText);
          }
          actionSummary = "Actions:\n${actionTexts.join('\n')}";
        }
        return Dismissible(
          key: Key(auto['rule_id']?.toString() ?? UniqueKey().toString()),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) async {
            // Step 1: Ask for confirmation
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (BuildContext ctx) {
                return AlertDialog(
                  backgroundColor: AppColors.card(context),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Text("Delete Automation", style: TextStyle(color: AppColors.text(context))),
                  content: Text("Are you sure you want to delete this automation?", style: TextStyle(color: AppColors.textSub(context))),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text("CANCEL", style: TextStyle(color: AppColors.textSub(context))),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text("DELETE", style: TextStyle(color: AppColors.accentRed)),
                    ),
                  ],
                );
              },
            );
            if (confirmed != true) return false;

            // Step 2: Call API
            final ruleId = auto['rule_id'];
            if (ruleId == null) return false;

            final selectedHome = ref.read(selectedHomeProvider);
            final homeId = (selectedHome?['home_id'] ?? selectedHome?['id'] ?? selectedHome?['homeid'])?.toString();
            if (homeId == null) return false;

            final success = await ApiService.deleteAutomation(homeId, ruleId.toString());
            if (!success && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Failed to delete automation.', style: TextStyle(color: Colors.white)), backgroundColor: AppColors.accentRed),
              );
            }
            return success;
          },
          onDismissed: (direction) {
            setState(() => _automations.removeAt(index));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('"$name" deleted.', style: const TextStyle(color: Colors.white)),
                  backgroundColor: AppColors.card(context),
                ),
              );
            }
          },
          background: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.accentRed.withOpacity(0.8),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Icon(Icons.delete_outline, color: Colors.white, size: 32),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.card(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderCol(context)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: isAI ? AppColors.accentOrange.withOpacity(0.2) : AppColors.primaryBlue.withOpacity(0.2),
                child: Icon(
                  isAI ? Icons.face : Icons.sensors,
                  color: isAI ? AppColors.accentOrange : AppColors.primaryBlue,
                ),
              ),
              title: Text(name, style: TextStyle(color: AppColors.text(context), fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("IF: $condition", style: const TextStyle(color: AppColors.primaryBlue, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(actionSummary, style: TextStyle(color: AppColors.textSub(context), fontSize: 13, height: 1.4)),
                  ],
                ),
              ),
              trailing: Icon(Icons.edit, color: AppColors.textSub(context), size: 20),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => AutomationCreateScreen(existingData: auto)),
                ).then((_) {
                  // Refresh on back
                  _fetchAutomations();
                });
              },
            ),
          ),
        );
      },
    );
  }
}
