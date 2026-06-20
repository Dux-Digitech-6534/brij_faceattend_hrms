import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_formats.dart';
import '../../core/utils/erp_error.dart';
import '../../data/models/dashboard_data.dart';
import '../../data/models/employee.dart';
import '../../data/models/employee_face_status.dart';
import '../../shared/widgets/premium_action_button.dart';
import '../../shared/widgets/premium_card.dart';
import '../../shared/widgets/status_pill.dart';
import 'register_face_screen.dart';

class EmployeeFaceRegistrationScreen extends StatefulWidget {
  const EmployeeFaceRegistrationScreen({required this.initialData, super.key});

  final DashboardData initialData;

  @override
  State<EmployeeFaceRegistrationScreen> createState() =>
      _EmployeeFaceRegistrationScreenState();
}

class _EmployeeFaceRegistrationScreenState
    extends State<EmployeeFaceRegistrationScreen> {
  final _searchController = TextEditingController();
  List<Employee> _employees = const [];
  Employee? _selected;
  EmployeeFaceStatus? _selectedStatus;
  bool _loadingEmployees = false;
  bool _capturingLocation = false;
  double? _latitude;
  double? _longitude;
  String? _location;
  String? _error;

  bool get _authorized => widget.initialData.isFaceRegistrationAdmin;

  @override
  void initState() {
    super.initState();
    if (_authorized) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadEmployees());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _loadingEmployees = true;
      _error = null;
    });
    try {
      final rows = await AppScope.of(context).apiClient
          .getEmployeesForFaceRegistration(search: _searchController.text);
      if (!mounted) return;
      setState(() => _employees = rows);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loadingEmployees = false);
    }
  }

  Future<void> _selectEmployee(Employee employee) async {
    setState(() {
      _selected = employee;
      _selectedStatus = null;
      _error = null;
    });
    try {
      final status = await AppScope.of(
        context,
      ).apiClient.getEmployeeFaceStatus(employee.name);
      if (!mounted) return;
      setState(() => _selectedStatus = status);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(error));
    }
  }

  Future<void> _captureLocation() async {
    setState(() {
      _capturingLocation = true;
      _error = null;
    });
    try {
      final position = await AppScope.of(
        context,
      ).locationService.determinePosition();
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _location =
            '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _capturingLocation = false);
    }
  }

  Future<void> _openCapture() async {
    final selected = _selected;
    if (selected == null) return;
    if (_latitude == null || _longitude == null) {
      await _captureLocation();
      if (_latitude == null || _longitude == null) return;
    }
    if (!mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RegisterFaceScreen(
          employee: selected,
          user: selected.userId ?? selected.name,
          adminRegistration: true,
          latitude: _latitude,
          longitude: _longitude,
          location: _location ?? 'Address not available',
        ),
      ),
    );
    if (changed == true) {
      await _selectEmployee(selected);
      await _loadEmployees();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_authorized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Employee Face Registration')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Not authorized',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Employee Face Registration')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            PremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _loadEmployees(),
                    decoration: InputDecoration(
                      hintText: 'Search active employee',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: 'Search',
                        onPressed: _loadingEmployees ? null : _loadEmployees,
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.red,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _EmployeeListCard(
              employees: _employees,
              selected: _selected,
              loading: _loadingEmployees,
              onSelect: _selectEmployee,
            ),
            if (_selected != null) ...[
              const SizedBox(height: 12),
              _SelectedEmployeeCard(
                employee: _selected!,
                status: _selectedStatus,
              ),
              const SizedBox(height: 12),
              _LocationCard(
                latitude: _latitude,
                longitude: _longitude,
                location: _location,
                loading: _capturingLocation,
                onCapture: _captureLocation,
              ),
              const SizedBox(height: 14),
              PremiumActionButton(
                label: 'Capture Face Samples',
                icon: Icons.face_retouching_natural_rounded,
                colors: const [AppColors.primary, AppColors.secondary],
                isLoading: _capturingLocation,
                onPressed: _openCapture,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmployeeListCard extends StatelessWidget {
  const _EmployeeListCard({
    required this.employees,
    required this.selected,
    required this.loading,
    required this.onSelect,
  });

  final List<Employee> employees;
  final Employee? selected;
  final bool loading;
  final ValueChanged<Employee> onSelect;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Active Employees',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (!loading && employees.isEmpty)
            Text(
              'No active employees found.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.faint,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            ...employees
                .take(8)
                .map(
                  (employee) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    selected: selected?.name == employee.name,
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primarySoft,
                      child: Text(
                        employee.initials,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    title: Text(employee.employeeName),
                    subtitle: Text(employee.name),
                    trailing: StatusPill(
                      label: employee.faceRegistered ? 'Registered' : 'Not set',
                      foreground: employee.faceRegistered
                          ? AppColors.green
                          : AppColors.amber,
                      background:
                          (employee.faceRegistered
                                  ? AppColors.green
                                  : AppColors.amber)
                              .withValues(alpha: 0.1),
                    ),
                    onTap: () => onSelect(employee),
                  ),
                ),
        ],
      ),
    );
  }
}

class _SelectedEmployeeCard extends StatelessWidget {
  const _SelectedEmployeeCard({required this.employee, required this.status});

  final Employee employee;
  final EmployeeFaceStatus? status;

  @override
  Widget build(BuildContext context) {
    final registered = status?.faceRegistered ?? employee.faceRegistered;
    final registeredOn = status?.registeredOn;
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Selected Employee',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              StatusPill(
                label: registered ? 'Registered' : 'Not Registered',
                foreground: registered ? AppColors.green : AppColors.amber,
                background: (registered ? AppColors.green : AppColors.amber)
                    .withValues(alpha: 0.1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DetailLine(label: 'Employee ID', value: employee.name),
          _DetailLine(label: 'Employee Name', value: employee.employeeName),
          _DetailLine(label: 'User ID', value: employee.userId ?? 'Not set'),
          _DetailLine(
            label: 'Designation',
            value: employee.designation ?? 'Not available',
          ),
          _DetailLine(
            label: 'Department',
            value: employee.department ?? 'Not available',
          ),
          _DetailLine(
            label: 'Company',
            value: employee.company ?? 'Not available',
          ),
          _DetailLine(label: 'Status', value: employee.status ?? 'Active'),
          _DetailLine(
            label: 'Face status',
            value: registered
                ? registeredOn == null
                      ? 'Registered'
                      : 'Registered on ${DateFormats.historyDate.format(registeredOn.toLocal())}'
                : 'Not Registered',
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.latitude,
    required this.longitude,
    required this.location,
    required this.loading,
    required this.onCapture,
  });

  final double? latitude;
  final double? longitude;
  final String? location;
  final bool loading;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final hasGps = latitude != null && longitude != null;
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Location',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              StatusPill(
                label: hasGps ? 'GPS captured' : 'GPS required',
                foreground: hasGps ? AppColors.green : AppColors.amber,
                background: (hasGps ? AppColors.green : AppColors.amber)
                    .withValues(alpha: 0.1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DetailLine(
            label: 'Latitude',
            value: hasGps ? latitude!.toStringAsFixed(6) : 'Pending',
          ),
          _DetailLine(
            label: 'Longitude',
            value: hasGps ? longitude!.toStringAsFixed(6) : 'Pending',
          ),
          _DetailLine(
            label: 'Address/City',
            value: location ?? 'Address not available',
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: loading ? null : onCapture,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
            label: Text(hasGps ? 'Refresh GPS' : 'Capture GPS'),
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
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
