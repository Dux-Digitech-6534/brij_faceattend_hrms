import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_formats.dart';
import '../../data/models/dashboard_data.dart';
import '../../data/models/employee_checkin.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/premium_action_button.dart';
import '../../shared/widgets/premium_card.dart';
import '../../shared/widgets/status_pill.dart';
import '../attendance/face_attendance_screen.dart';
import '../face_registration/register_face_screen.dart';
import '../history/attendance_history_screen.dart';
import '../profile/profile_sync_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.initialData, super.key});

  final DashboardData initialData;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late DashboardData _data = widget.initialData;
  bool _isRefreshing = false;

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    try {
      final data = await AppScope.of(context).repository.loadDashboard();
      if (!mounted) return;
      setState(() => _data = data);
    } catch (error) {
      if (!mounted) return;
      _showSnack('$error', isError: true);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _openAttendance(String logType) async {
    try {
      final faceProfile = await AppScope.of(
        context,
      ).faceProfileService.getFaceProfile(_data.employee.name);
      if (!mounted) return;

      if (faceProfile == null || !faceProfile.hasEmbedding) {
        _showSnack(
          'Face not registered. Please register your face first.',
          isError: true,
        );
        final registered = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) =>
                RegisterFaceScreen(employee: _data.employee, user: _data.user),
          ),
        );
        if (registered == true) await _refresh();
        return;
      }

      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => FaceAttendanceScreen(
            employee: _data.employee,
            logType: logType,
            initialFaceProfile: faceProfile,
          ),
        ),
      );
      if (changed == true) {
        await _refresh();
      }
    } catch (error) {
      if (!mounted) return;
      _showSnack('$error', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.red : AppColors.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayCheckins = _todayCheckins(_data.history, today);
    final firstIn = _firstLog(todayCheckins, 'IN');
    final lastOut = _lastLog(todayCheckins, 'OUT');

    return Scaffold(
      bottomNavigationBar: AppBottomNav(
        current: AppTab.home,
        dashboardData: _data,
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _Header(data: _data, refreshing: _isRefreshing),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              sliver: SliverList.list(
                children: [
                  Transform.translate(
                    offset: const Offset(0, -28),
                    child: _TodayCard(
                      data: _data,
                      date: today,
                      firstIn: firstIn,
                      lastOut: lastOut,
                      onMarkIn: () => _openAttendance('IN'),
                      onMarkOut: () => _openAttendance('OUT'),
                    ),
                  ),
                  const SizedBox(height: 2),
                  _QuickAccess(
                    onHistory: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              AttendanceHistoryScreen(initialData: _data),
                        ),
                      );
                    },
                    onProfile: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => ProfileSyncScreen(initialData: _data),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _ShiftCard(data: _data),
                  const SizedBox(height: 16),
                  _RecentActivity(history: _data.history),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<EmployeeCheckin> _todayCheckins(
    List<EmployeeCheckin> history,
    DateTime today,
  ) {
    return history.where((item) {
      final local = item.time.toLocal();
      return local.year == today.year &&
          local.month == today.month &&
          local.day == today.day;
    }).toList();
  }

  static EmployeeCheckin? _firstLog(
    List<EmployeeCheckin> checkins,
    String logType,
  ) {
    final logs =
        checkins.where((item) => item.logType.toUpperCase() == logType).toList()
          ..sort((a, b) => a.time.compareTo(b.time));
    if (logs.isEmpty) return null;
    return logs.first;
  }

  static EmployeeCheckin? _lastLog(
    List<EmployeeCheckin> checkins,
    String logType,
  ) {
    final logs =
        checkins.where((item) => item.logType.toUpperCase() == logType).toList()
          ..sort((a, b) => b.time.compareTo(a.time));
    if (logs.isEmpty) return null;
    return logs.first;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data, required this.refreshing});

  final DashboardData data;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 18,
        20,
        56,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.secondary],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              data.employee.initials,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.employee.employeeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.employee.designation ??
                      data.employee.department ??
                      data.user,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          StatusPill(
            label: refreshing ? 'Syncing' : 'Live',
            foreground: Colors.white,
            background: Colors.white.withValues(alpha: 0.16),
            icon: refreshing ? Icons.sync_rounded : Icons.cloud_done_rounded,
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.data,
    required this.date,
    required this.firstIn,
    required this.lastOut,
    required this.onMarkIn,
    required this.onMarkOut,
  });

  final DashboardData data;
  final DateTime date;
  final EmployeeCheckin? firstIn;
  final EmployeeCheckin? lastOut;
  final VoidCallback onMarkIn;
  final VoidCallback onMarkOut;

  @override
  Widget build(BuildContext context) {
    final statusColor = data.isCurrentlyIn ? AppColors.green : AppColors.red;
    final statusText = data.isCurrentlyIn ? 'IN' : 'OUT';
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormats.dayMonth.format(date),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.faint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: statusText,
                foreground: statusColor,
                background: statusColor.withValues(alpha: 0.11),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'In time',
                  value: firstIn?.timeLabel ?? '--:--',
                  icon: Icons.login_rounded,
                  color: AppColors.green,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Metric(
                  label: 'Out time',
                  value: lastOut?.timeLabel ?? '--:--',
                  icon: Icons.logout_rounded,
                  color: AppColors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PremiumActionButton(
                  label: 'Mark In',
                  icon: Icons.play_arrow_rounded,
                  colors: const [Color(0xFF00D090), AppColors.green],
                  onPressed: onMarkIn,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PremiumActionButton(
                  label: 'Mark Out',
                  icon: Icons.stop_rounded,
                  colors: const [Color(0xFFFF6680), AppColors.red],
                  onPressed: onMarkOut,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.faint,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _QuickAccess extends StatelessWidget {
  const _QuickAccess({required this.onHistory, required this.onProfile});

  final VoidCallback onHistory;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickTile(
            icon: Icons.history_rounded,
            label: 'History',
            onTap: onHistory,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickTile(
            icon: Icons.sync_rounded,
            label: 'Sync',
            onTap: onProfile,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickTile(
            icon: Icons.verified_user_outlined,
            label: 'Profile',
            onTap: onProfile,
          ),
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  const _ShiftCard({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final holiday = data.holidays.isEmpty ? null : data.holidays.first;
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Shift & Holidays',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoLine(label: 'Shift', value: data.shiftDetails.displayName),
          _InfoLine(label: 'Timing', value: data.shiftDetails.displayTime),
          _InfoLine(
            label: 'Next holiday',
            value: holiday == null
                ? 'No upcoming holiday synced'
                : '${holiday.label} - ${holiday.description ?? holiday.name}',
          ),
        ],
      ),
    );
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.history});

  final List<EmployeeCheckin> history;

  @override
  Widget build(BuildContext context) {
    final items = history.take(4).toList();
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Activity',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(
              'No checkins yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.faint,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            ...items.map((item) => _HistoryLine(item: item)),
        ],
      ),
    );
  }
}

class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.item});

  final EmployeeCheckin item;

  @override
  Widget build(BuildContext context) {
    final color = item.isIn ? AppColors.green : AppColors.red;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              item.isIn ? Icons.login_rounded : Icons.logout_rounded,
              color: color,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.dateLabel,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            '${item.logType}  ${item.timeLabel}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.faint,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.text,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
