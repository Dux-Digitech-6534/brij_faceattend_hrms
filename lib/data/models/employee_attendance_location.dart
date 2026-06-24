class EmployeeAttendanceLocation {
  const EmployeeAttendanceLocation({
    required this.name,
    required this.employee,
    required this.attendanceLocation,
    required this.locationName,
    required this.radiusMeters,
    this.employeeName,
    this.latitude,
    this.longitude,
    this.isActive = true,
    this.notes,
  });

  final String name;
  final String employee;
  final String? employeeName;
  final String attendanceLocation;
  final String locationName;
  final double? latitude;
  final double? longitude;
  final double radiusMeters;
  final bool isActive;
  final String? notes;

  factory EmployeeAttendanceLocation.fromJson(Map<String, dynamic> json) {
    return EmployeeAttendanceLocation(
      name: _string(json['name']),
      employee: _string(json['employee']),
      employeeName: _nullableString(json['employee_name']),
      attendanceLocation: _string(json['attendance_location']),
      locationName: _string(json['location_name']),
      latitude: _nullableDouble(json['latitude']),
      longitude: _nullableDouble(json['longitude']),
      radiusMeters: _toDouble(json['radius_meters']),
      isActive: _toBool(json['is_active']),
      notes: _nullableString(json['notes']),
    );
  }

  static String _string(Object? value) => _nullableString(value) ?? '';

  static String? _nullableString(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  static double? _nullableDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static bool _toBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    final text = '${value ?? ''}'.trim().toLowerCase();
    if (text.isEmpty || text == 'null') return true;
    return text == '1' || text == 'true' || text == 'yes';
  }
}
