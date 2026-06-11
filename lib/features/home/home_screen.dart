import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_formats.dart';
import '../../core/utils/erp_error.dart';
import '../../data/models/attendance_day_status.dart';
import '../../data/models/dashboard_data.dart';
import '../../data/models/employee_checkin.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/premium_action_button.dart';
import '../../shared/widgets/premium_card.dart';
import '../../shared/widgets/status_pill.dart';
import '../attendance/face_attendance_screen.dart';
import '../auth/login_screen.dart';
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
  bool _openingAttendance = false;
  DateTime _istNow = DateFormats.istNow();
  DateTime? _lastBackPressedAt;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _istNow = DateFormats.istNow());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    try {
      final data = await AppScope.of(context).repository.loadDashboard();
      if (!mounted) return;
      setState(() => _data = data);
    } catch (error) {
      if (!mounted) return;
      await _handleRefreshError(error);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<AttendanceDayStatus?> _refreshTodayStatus() async {
    try {
      final status = await AppScope.of(
        context,
      ).repository.loadTodayStatus(_data.employee);
      if (!mounted) return null;
      setState(() => _data = _data.copyWith(todayStatus: status));
      return status;
    } catch (error) {
      if (!mounted) return null;
      _showSnack(friendlyErrorMessage(error), isError: true);
      return null;
    }
  }

  Future<void> _openRegisterFace() async {
    final registered = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            RegisterFaceScreen(employee: _data.employee, user: _data.user),
      ),
    );
    if (registered == true) await _refresh();
  }

  Future<void> _openAttendance(String requestedLogType) async {
    if (_openingAttendance) return;
    setState(() => _openingAttendance = true);
    try {
      if (!_data.employee.hasAssignedShift) {
        _showSnack('Shift not assigned. Please contact HR.', isError: true);
        return;
      }

      final todayStatus = await _refreshTodayStatus();
      if (!mounted || todayStatus == null) return;
      if (!todayStatus.canSubmit(requestedLogType)) {
        _showSnack(
          todayStatus.duplicateMessage(requestedLogType),
          isError: todayStatus.completed ? false : true,
        );
        return;
      }

      final faceProfile = await AppScope.of(
        context,
      ).faceProfileService.getFaceProfile(_data.employee.name);
      if (!mounted) return;

      if (faceProfile == null || !faceProfile.hasEmbedding) {
        _showSnack(
          'Face not registered. Please register your face first.',
          isError: true,
        );
        await _openRegisterFace();
        return;
      }

      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => FaceAttendanceScreen(
            employee: _data.employee,
            logType: requestedLogType,
            initialFaceProfile: faceProfile,
          ),
        ),
      );
      if (changed == true) {
        await _refresh();
      }
    } catch (error) {
      if (!mounted) return;
      _showSnack(friendlyErrorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _openingAttendance = false);
    }
  }

  Future<void> _handleRefreshError(Object error) async {
    if (!isInactiveEmployeeError(error)) {
      _showSnack(friendlyErrorMessage(error), isError: true);
      return;
    }

    await AppScope.of(context).repository.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) =>
            const LoginScreen(initialMessage: inactiveEmployeeMessage),
      ),
      (_) => false,
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.red : AppColors.text,
      ),
    );
  }

  void _handleDashboardBack() {
    final now = DateTime.now();
    final previous = _lastBackPressedAt;
    _lastBackPressedAt = now;
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _showSnack('Press back again to exit');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleDashboardBack();
      },
      child: Scaffold(
        bottomNavigationBar: AppBottomNav(
          current: AppTab.home,
          dashboardData: _data,
        ),
        body: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 86),
              child: Column(
                children: [
                  _Header(data: _data, refreshing: _isRefreshing),
                  const SizedBox(height: 16),
                  _TodayCard(
                    data: _data,
                    istNow: _istNow,
                    isLoading: _openingAttendance || _isRefreshing,
                    onMarkIn: () => _openAttendance('IN'),
                    onMarkOut: () => _openAttendance('OUT'),
                    onRegisterFace: _openRegisterFace,
                  ),
                  const SizedBox(height: 14),
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
                    onRegisterFace: _openRegisterFace,
                  ),
                  const SizedBox(height: 16),
                  _ShiftCard(data: _data),
                  const SizedBox(height: 16),
                  _RecentActivity(history: _data.history),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data, required this.refreshing});

  final DashboardData data;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.secondary],
        ),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.24),
                  ),
                  borderRadius: BorderRadius.circular(8),
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
                      data.employee.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: refreshing ? 'Syncing' : 'Live',
                foreground: Colors.white,
                background: Colors.white.withValues(alpha: 0.16),
                icon: refreshing
                    ? Icons.sync_rounded
                    : Icons.cloud_done_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            runSpacing: 8,
            spacing: 8,
            children: [
              _HeaderChip(
                icon: Icons.work_outline_rounded,
                label: data.employee.designation ?? 'Designation not set',
              ),
              _HeaderChip(
                icon: Icons.apartment_rounded,
                label:
                    data.employee.department ??
                    data.employee.company ??
                    AppConfig.brandName,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.data,
    required this.istNow,
    required this.isLoading,
    required this.onMarkIn,
    required this.onMarkOut,
    required this.onRegisterFace,
  });

  final DashboardData data;
  final DateTime istNow;
  final bool isLoading;
  final VoidCallback onMarkIn;
  final VoidCallback onMarkOut;
  final VoidCallback onRegisterFace;

  @override
  Widget build(BuildContext context) {
    final status = data.todayStatus;
    final firstIn = status.firstIn;
    final lastOut = status.lastOut;
    final statusColor = status.completed
        ? AppColors.green
        : status.canMarkOut
        ? AppColors.amber
        : AppColors.red;
    final hasShift = data.employee.hasAssignedShift;
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
                      '${DateFormats.dayMonth.format(istNow)}  |  IST ${DateFormats.istClock.format(istNow)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.faint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: status.title,
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
          if (!hasShift) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.amber.withValues(alpha: 0.22),
                ),
              ),
              child: Text(
                'Shift not assigned. Please contact HR.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.amber,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (status.completed) ...[
            _InlineNotice(
              icon: Icons.task_alt_rounded,
              message: "Today's attendance completed.",
              color: AppColors.green,
            ),
          ] else if (status.canMarkIn) ...[
            PremiumActionButton(
              label: 'Mark In',
              icon: Icons.login_rounded,
              colors: const [AppColors.primary, AppColors.secondary],
              isLoading: isLoading,
              onPressed: hasShift && !isLoading ? onMarkIn : null,
            ),
          ] else if (status.canMarkOut) ...[
            PremiumActionButton(
              label: 'Mark Out',
              icon: Icons.logout_rounded,
              colors: const [AppColors.primary, AppColors.secondary],
              isLoading: isLoading,
              onPressed: hasShift && !isLoading ? onMarkOut : null,
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: isLoading ? null : onRegisterFace,
            icon: const Icon(Icons.face_retouching_natural_rounded),
            label: Text(
              data.employee.faceRegistered ? 'Update Face' : 'Register Face',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
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
        borderRadius: BorderRadius.circular(8),
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
  const _QuickAccess({
    required this.onHistory,
    required this.onProfile,
    required this.onRegisterFace,
  });

  final VoidCallback onHistory;
  final VoidCallback onProfile;
  final VoidCallback onRegisterFace;

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
            icon: Icons.face_retouching_natural_rounded,
            label: 'Face',
            onTap: onRegisterFace,
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
          _InfoLine(label: 'Shift', value: data.employee.displayShift),
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
