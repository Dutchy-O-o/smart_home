import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_colors.dart';
import '../providers/navigation_provider.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/ai_hub/emotion_hub_screen.dart';
import '../screens/ai_agent/ai_chat_screen.dart';
import '../screens/automations/automations_list_screen.dart';
import '../screens/devices/device_control_screen.dart';
import '../screens/notifications/notification_screen.dart';
import '../screens/profile/profile_screen.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(tabIndexProvider);

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: const [
          DashboardScreen(),      // 0
          EmotionHubScreen(),     // 1
          AiChatScreen(),         // 2
          AutomationsListScreen(),// 3
          DeviceControlScreen(),  // 4
          NotificationScreen(),   // 5
          ProfileScreen(),        // 6
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppColors.navBar(context),
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: AppColors.textSub(context),
        type: BottomNavigationBarType.fixed,
        currentIndex: currentIndex,
        onTap: (index) => ref.read(tabIndexProvider.notifier).setTab(index),
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'Dash'),
          BottomNavigationBarItem(icon: Icon(Icons.sentiment_satisfied_alt), label: 'Emotion'),
          BottomNavigationBarItem(icon: Icon(Icons.smart_toy), label: 'AI'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'Automate'),
          BottomNavigationBarItem(icon: Icon(Icons.devices), label: 'Devices'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: 'Alerts'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
