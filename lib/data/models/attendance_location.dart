class AttendanceLocation {
  const AttendanceLocation({
    required this.name,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    this.isActive = true,
  });

  final String name;
  final String locationName;
  final double latitude;
  final double longitude;
  final bool isActive;

  factory AttendanceLocation.fromJson(Map<String, dynamic> json) {
    return AttendanceLocation(
      name: _string(json['name']),
      locationName: _string(json['location_name']),
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      isActive: _toBool(json['is_active']),
    );
  }

  static String _string(Object? value) {
    if (value == null) return '';
    final text = '$value'.trim();
    return text.toLowerCase() == 'null' ? '' : text;
  }

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  static bool _toBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    final text = '${value ?? ''}'.trim().toLowerCase();
    if (text.isEmpty || text == 'null') return true;
    return text == '1' || text == 'true' || text == 'yes';
  }
}
