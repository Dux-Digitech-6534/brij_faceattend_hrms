import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/dashboard_data.dart';
import '../../features/history/attendance_history_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/profile/profile_sync_screen.dart';

enum AppTab { home, history, profile }

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    required this.current,
    required this.dashboardData,
    super.key,
  });

  final AppTab current;
  final DashboardData dashboardData;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: current.index,
      height: 72,
      elevation: 0,
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primarySoft,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (index) {
        final tab = AppTab.values[index];
        if (tab == current) return;
        Widget page;
        switch (tab) {
          case AppTab.home:
            page = HomeScreen(initialData: dashboardData);
          case AppTab.history:
            page = AttendanceHistoryScreen(initialData: dashboardData);
          case AppTab.profile:
            page = ProfileSyncScreen(initialData: dashboardData);
        }
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute<void>(builder: (_) => page));
      },
      destinations: const [
        NavigationDestination(
          selectedIcon: Icon(Icons.home_rounded),
          icon: Icon(Icons.home_outlined),
          label: 'Home',
        ),
        NavigationDestination(
          selectedIcon: Icon(Icons.history_rounded),
          icon: Icon(Icons.history_outlined),
          label: 'History',
        ),
        NavigationDestination(
          selectedIcon: Icon(Icons.person_rounded),
          icon: Icon(Icons.person_outline_rounded),
          label: 'Profile',
        ),
      ],
    );
  }
}
