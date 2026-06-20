import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_formats.dart';
import '../../core/utils/erp_error.dart';
import '../../data/models/dashboard_data.dart';
import '../../data/models/employee_face_status.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/premium_action_button.dart';
import '../../shared/widgets/premium_card.dart';
import '../../shared/widgets/powered_by_footer.dart';
import '../../shared/widgets/status_pill.dart';
import '../auth/login_screen.dart';
import '../face_registration/employee_face_registration_screen.dart';
import '../home/home_screen.dart';

class ProfileSyncScreen extends StatefulWidget {
  const ProfileSyncScreen({required this.initialData, super.key});

  final DashboardData initialData;

  @override
  State<ProfileSyncScreen> createState() => _ProfileSyncScreenState();
}

class _ProfileSyncScreenState extends State<ProfileSyncScreen> {
  late DashboardData _data = widget.initialData;
  bool _syncing = false;
  bool _loggingOut = false;
  bool _loadingFaceProfile = true;
  EmployeeFaceStatus? _faceStatus;
  String? _faceProfileError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _sync(showSnack: false),
    );
  }

  Future<void> _loadFaceProfile() async {
    setState(() {
      _loadingFaceProfile = true;
      _faceProfileError = null;
    });
    try {
      final status = await AppScope.of(context).apiClient.getMyFaceStatus();
      if (!mounted) return;
      setState(() => _faceStatus = status);
    } catch (error) {
      if (!mounted) return;
      setState(() => _faceProfileError = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loadingFaceProfile = false);
    }
  }

  Future<void> _sync({bool showSnack = true}) async {
    setState(() => _syncing = true);
    try {
      final data = await AppScope.of(context).repository.loadDashboard();
      if (!mounted) return;
      setState(() => _data = data);
      await _loadFaceProfile();
      if (showSnack) _showSnack('ERPNext profile and shift data synced.');
    } catch (error) {
      if (!mounted) return;
      await _handleSyncError(error);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _handleSyncError(Object error) async {
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

  Future<void> _openAdminFaceRegistration() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EmployeeFaceRegistrationScreen(initialData: _data),
      ),
    );
    if (changed == true) await _loadFaceProfile();
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      await AppScope.of(context).repository.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } finally {
      if (mounted) setState(() => _loggingOut = false);
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
    final employee = _data.employee;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => HomeScreen(initialData: _data),
          ),
        );
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profile & Sync'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _syncing ? null : () => _sync(),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        bottomNavigationBar: AppBottomNav(
          current: AppTab.profile,
          dashboardData: _data,
        ),
        body: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _sync,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 86),
            children: [
              PremiumCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 78,
                      height: 78,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.primary, AppColors.secondary],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        employee.initials,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      employee.employeeName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      employee.designation ?? employee.department ?? _data.user,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.faint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    StatusPill(
                      label: employee.hasAssignedShift
                          ? 'Shift assigned'
                          : 'Shift not assigned',
                      foreground: employee.hasAssignedShift
                          ? AppColors.green
                          : AppColors.amber,
                      background:
                          (employee.hasAssignedShift
                                  ? AppColors.green
                                  : AppColors.amber)
                              .withValues(alpha: 0.1),
                      icon: employee.hasAssignedShift
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Employee Details',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _InfoLine(label: 'Employee ID', value: employee.name),
                    _InfoLine(
                      label: 'ERP User',
                      value: employee.userId ?? _data.user,
                    ),
                    _InfoLine(
                      label: 'Company email',
                      value: employee.companyEmail ?? 'Not available',
                    ),
                    _InfoLine(
                      label: 'Personal email',
                      value: employee.personalEmail ?? 'Not available',
                    ),
                    _InfoLine(
                      label: 'Designation',
                      value: employee.designation ?? 'Not available',
                    ),
                    _InfoLine(
                      label: 'Department',
                      value: employee.department ?? 'Not available',
                    ),
                    _InfoLine(
                      label: 'Company',
                      value: employee.company ?? 'Not available',
                    ),
                    _InfoLine(
                      label: 'Default shift',
                      value: employee.resolvedShift ?? 'Not assigned',
                    ),
                    _InfoLine(
                      label: 'Status',
                      value: employee.status ?? 'Active',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _FaceProfileCard(
                status: _faceStatus,
                loading: _loadingFaceProfile,
                error: _faceProfileError,
              ),
              const SizedBox(height: 16),
              if (_data.isFaceRegistrationAdmin) ...[
                PremiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Admin Tools',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 12),
                      PremiumActionButton(
                        label: 'Employee Face Registration',
                        icon: Icons.admin_panel_settings_rounded,
                        colors: const [AppColors.primary, AppColors.secondary],
                        onPressed: _openAdminFaceRegistration,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              PremiumCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PremiumActionButton(
                      label: 'Logout',
                      icon: Icons.logout_rounded,
                      colors: const [Color(0xFFFF6680), AppColors.red],
                      isLoading: _loggingOut,
                      onPressed: _logout,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const PoweredByFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaceProfileCard extends StatelessWidget {
  const _FaceProfileCard({
    required this.status,
    required this.loading,
    required this.error,
  });

  final EmployeeFaceStatus? status;
  final bool loading;
  final String? error;

  bool get _registered => status?.faceRegistered ?? false;

  @override
  Widget build(BuildContext context) {
    final color = _registered ? AppColors.green : AppColors.amber;
    final title = _registered ? 'Face Registered' : 'Face Not Registered';
    final registeredOn = status?.registeredOn;
    final subtitle = error != null
        ? error!
        : _registered
        ? registeredOn == null
              ? 'Face profile is active.'
              : 'Registered on ${DateFormats.historyDate.format(registeredOn.toLocal())} at ${DateFormats.shortTime.format(registeredOn.toLocal())}'
        : 'Face not registered. Please contact HR/Admin.';

    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _registered
                      ? Icons.verified_user_rounded
                      : Icons.face_retouching_off_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: error != null ? AppColors.red : AppColors.faint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              else
                StatusPill(
                  label: _registered ? 'Active' : 'Required',
                  foreground: color,
                  background: color.withValues(alpha: 0.1),
                ),
            ],
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
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
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
