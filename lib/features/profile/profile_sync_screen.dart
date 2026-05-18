import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_formats.dart';
import '../../data/models/dashboard_data.dart';
import '../../data/models/face_profile.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/premium_action_button.dart';
import '../../shared/widgets/premium_card.dart';
import '../../shared/widgets/status_pill.dart';
import '../auth/login_screen.dart';
import '../face_registration/register_face_screen.dart';

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
  FaceProfile? _faceProfile;
  String? _faceProfileError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFaceProfile());
  }

  Future<void> _loadFaceProfile() async {
    setState(() {
      _loadingFaceProfile = true;
      _faceProfileError = null;
    });
    try {
      final service = AppScope.of(context).faceProfileService;
      final profile = await service.getFaceProfile(_data.employee.name);
      if (!mounted) return;
      setState(() => _faceProfile = profile);
    } catch (error) {
      if (!mounted) return;
      setState(() => _faceProfileError = '$error');
    } finally {
      if (mounted) setState(() => _loadingFaceProfile = false);
    }
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final data = await AppScope.of(context).repository.loadDashboard();
      if (!mounted) return;
      setState(() => _data = data);
      await _loadFaceProfile();
      _showSnack('ERPNext profile and shift data synced.');
    } catch (error) {
      if (!mounted) return;
      _showSnack('$error', isError: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _openRegisterFace() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            RegisterFaceScreen(employee: _data.employee, user: _data.user),
      ),
    );
    if (changed == true) {
      await _loadFaceProfile();
    }
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
    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Sync')),
      bottomNavigationBar: AppBottomNav(
        current: AppTab.profile,
        dashboardData: _data,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
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
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  employee.employeeName,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
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
                  label: _data.shiftDetails.fetchedFromErp
                      ? 'Shift synced'
                      : 'Shift pending',
                  foreground: _data.shiftDetails.fetchedFromErp
                      ? AppColors.green
                      : AppColors.amber,
                  background:
                      (_data.shiftDetails.fetchedFromErp
                              ? AppColors.green
                              : AppColors.amber)
                          .withValues(alpha: 0.1),
                  icon: Icons.sync_rounded,
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
                _InfoLine(label: 'ERP User', value: _data.user),
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
                  label: 'Branch',
                  value: employee.branch ?? 'Not available',
                ),
                _InfoLine(
                  label: 'Default shift',
                  value: employee.defaultShift ?? 'Not assigned',
                ),
                _InfoLine(
                  label: 'Holiday list',
                  value: employee.holidayList ?? 'Not assigned',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _FaceProfileCard(
            profile: _faceProfile,
            loading: _loadingFaceProfile,
            error: _faceProfileError,
            onRegister: _openRegisterFace,
          ),
          const SizedBox(height: 16),
          PremiumCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sync Settings',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                _InfoLine(label: 'Server', value: AppConfig.baseUrl),
                _InfoLine(
                  label: 'Attendance API',
                  value: AppConfig.useCustomAttendanceEndpoint
                      ? AppConfig.customAttendanceEndpoint
                      : '/api/resource/Employee Checkin',
                ),
                const SizedBox(height: 16),
                PremiumActionButton(
                  label: 'Sync Now',
                  icon: Icons.cloud_sync_rounded,
                  colors: const [AppColors.primary, AppColors.secondary],
                  isLoading: _syncing,
                  onPressed: _sync,
                ),
                const SizedBox(height: 12),
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
        ],
      ),
    );
  }
}

class _FaceProfileCard extends StatelessWidget {
  const _FaceProfileCard({
    required this.profile,
    required this.loading,
    required this.error,
    required this.onRegister,
  });

  final FaceProfile? profile;
  final bool loading;
  final String? error;
  final VoidCallback onRegister;

  bool get _registered => profile != null && profile!.hasEmbedding;

  @override
  Widget build(BuildContext context) {
    final color = _registered ? AppColors.green : AppColors.amber;
    final title = _registered ? 'Face Registered' : 'Face Not Registered';
    final registeredOn = profile?.registeredOn;
    final subtitle = error != null
        ? error!
        : _registered
        ? registeredOn == null
              ? 'Face profile is active.'
              : 'Registered on ${DateFormats.historyDate.format(registeredOn.toLocal())} at ${DateFormats.shortTime.format(registeredOn.toLocal())}'
        : 'Register your face before Mark In or Mark Out.';

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
          const SizedBox(height: 16),
          PremiumActionButton(
            label: _registered ? 'Re-register Face' : 'Register Face',
            icon: _registered
                ? Icons.change_circle_rounded
                : Icons.face_retouching_natural_rounded,
            colors: _registered
                ? const [Color(0xFF00D090), AppColors.green]
                : const [AppColors.primary, AppColors.secondary],
            onPressed: loading ? null : onRegister,
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
