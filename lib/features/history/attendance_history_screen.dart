import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/dashboard_data.dart';
import '../../data/models/employee_checkin.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/premium_card.dart';
import '../../shared/widgets/status_pill.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({required this.initialData, super.key});

  final DashboardData initialData;

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  late DashboardData _data = widget.initialData;

  Future<void> _refresh() async {
    try {
      final data = await AppScope.of(context).repository.loadDashboard();
      if (!mounted) return;
      setState(() => _data = data);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: AppColors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance History'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        current: AppTab.history,
        dashboardData: _data,
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
          children: [
            PremiumCard(
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_month_rounded,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _data.employee.employeeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_data.history.length} synced checkins',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.faint,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(
                    label: 'ERPNext',
                    foreground: AppColors.green,
                    background: AppColors.green.withValues(alpha: 0.1),
                    icon: Icons.cloud_done_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_data.history.isEmpty)
              const _EmptyHistory()
            else
              ..._data.history.map((item) => _HistoryItem(item: item)),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Column(
        children: [
          const Icon(
            Icons.event_busy_rounded,
            color: AppColors.faint,
            size: 42,
          ),
          const SizedBox(height: 12),
          Text(
            'No attendance records found',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Your ERPNext Employee Checkin history will appear here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.faint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.item});

  final EmployeeCheckin item;

  @override
  Widget build(BuildContext context) {
    final color = item.isIn ? AppColors.green : AppColors.red;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PremiumCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                item.isIn ? Icons.login_rounded : Icons.logout_rounded,
                color: color,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        item.logType.toUpperCase(),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(width: 8),
                      if (item.faceVerified == true)
                        const StatusPill(
                          label: 'Face',
                          foreground: AppColors.primary,
                          background: AppColors.primarySoft,
                          icon: Icons.verified_user_rounded,
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${item.dateLabel} at ${item.timeLabel}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (item.latitude != null && item.longitude != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${item.latitude!.toStringAsFixed(5)}, ${item.longitude!.toStringAsFixed(5)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.faint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
