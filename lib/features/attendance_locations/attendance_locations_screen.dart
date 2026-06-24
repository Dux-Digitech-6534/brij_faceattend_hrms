import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/erp_error.dart';
import '../../data/models/attendance_location.dart';
import '../../data/models/dashboard_data.dart';
import '../../shared/widgets/premium_action_button.dart';
import '../../shared/widgets/premium_card.dart';
import '../../shared/widgets/status_pill.dart';

class AttendanceLocationsScreen extends StatefulWidget {
  const AttendanceLocationsScreen({required this.initialData, super.key});

  final DashboardData initialData;

  @override
  State<AttendanceLocationsScreen> createState() =>
      _AttendanceLocationsScreenState();
}

class _AttendanceLocationsScreenState extends State<AttendanceLocationsScreen> {
  List<AttendanceLocation> _locations = const [];
  bool _loading = false;
  String? _error;

  bool get _authorized => widget.initialData.isFaceRegistrationAdmin;

  @override
  void initState() {
    super.initState();
    if (_authorized) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadLocations());
    }
  }

  Future<void> _loadLocations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AppScope.of(
        context,
      ).apiClient.getAttendanceLocations(includeInactive: true);
      if (!mounted) return;
      setState(() => _locations = rows);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openLocationForm({AttendanceLocation? location}) async {
    final nameController = TextEditingController(
      text: location?.locationName ?? '',
    );
    final latitudeController = TextEditingController(
      text: location == null ? '' : location.latitude.toStringAsFixed(6),
    );
    final longitudeController = TextEditingController(
      text: location == null ? '' : location.longitude.toStringAsFixed(6),
    );
    var isActive = location?.isActive ?? true;

    final result = await showDialog<_LocationFormResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(location == null ? 'Add Location' : 'Edit Location'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Location name',
                        prefixIcon: Icon(Icons.place_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: latitudeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        prefixIcon: Icon(Icons.explore_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: longitudeController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        prefixIcon: Icon(Icons.explore_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: isActive,
                      onChanged: (value) =>
                          setDialogState(() => isActive = value),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final latitude = double.tryParse(
                      latitudeController.text.trim(),
                    );
                    final longitude = double.tryParse(
                      longitudeController.text.trim(),
                    );
                    final locationName = nameController.text.trim();
                    if (locationName.isEmpty ||
                        latitude == null ||
                        longitude == null) {
                      return;
                    }
                    Navigator.of(context).pop(
                      _LocationFormResult(
                        locationName: locationName,
                        latitude: latitude,
                        longitude: longitude,
                        isActive: isActive,
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    latitudeController.dispose();
    longitudeController.dispose();
    if (result == null || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = AppScope.of(context).apiClient;
      if (location == null) {
        await api.createAttendanceLocation(
          locationName: result.locationName,
          latitude: result.latitude,
          longitude: result.longitude,
          isActive: result.isActive,
        );
      } else {
        await api.updateAttendanceLocation(
          name: location.name,
          locationName: result.locationName,
          latitude: result.latitude,
          longitude: result.longitude,
          isActive: result.isActive,
        );
      }
      if (!mounted) return;
      _showSnack('Attendance location saved.');
      await _loadLocations();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deactivateLocation(AttendanceLocation location) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate Location'),
        content: Text(location.locationName),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.block_rounded),
            label: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppScope.of(
        context,
      ).apiClient.deleteAttendanceLocation(location.name);
      if (!mounted) return;
      _showSnack('Attendance location deactivated.');
      await _loadLocations();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_authorized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Attendance Locations')),
        body: Center(
          child: Text(
            'Not authorized',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Locations'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadLocations,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            PremiumActionButton(
              label: 'Add Attendance Location',
              icon: Icons.add_location_alt_rounded,
              colors: const [AppColors.primary, AppColors.secondary],
              isLoading: _loading,
              onPressed: _loading ? null : () => _openLocationForm(),
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
            const SizedBox(height: 12),
            PremiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Locations',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (_loading)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (!_loading && _locations.isEmpty)
                    Text(
                      'No attendance locations found.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.faint,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else
                    ..._locations.map(
                      (location) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.location_on_rounded),
                        title: Text(location.locationName),
                        subtitle: Text(
                          '${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StatusPill(
                              label: location.isActive ? 'Active' : 'Inactive',
                              foreground: location.isActive
                                  ? AppColors.green
                                  : AppColors.faint,
                              background:
                                  (location.isActive
                                          ? AppColors.green
                                          : AppColors.faint)
                                      .withValues(alpha: 0.1),
                            ),
                            IconButton(
                              tooltip: 'Edit',
                              onPressed: _loading
                                  ? null
                                  : () => _openLocationForm(location: location),
                              icon: const Icon(Icons.edit_rounded),
                            ),
                            IconButton(
                              tooltip: 'Deactivate',
                              onPressed: _loading || !location.isActive
                                  ? null
                                  : () => _deactivateLocation(location),
                              icon: const Icon(Icons.block_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationFormResult {
  const _LocationFormResult({
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.isActive,
  });

  final String locationName;
  final double latitude;
  final double longitude;
  final bool isActive;
}
