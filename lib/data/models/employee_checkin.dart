import '../../core/utils/date_formats.dart';

class EmployeeCheckin {
  const EmployeeCheckin({
    required this.name,
    required this.employee,
    required this.logType,
    required this.time,
    this.employeeName,
    this.shift,
    this.deviceId,
    this.skipAutoAttendance,
    this.latitude,
    this.longitude,
    this.faceVerified,
    this.faceDistance,
    this.serverMessage,
  });

  final String name;
  final String employee;
  final String logType;
  final DateTime time;
  final String? employeeName;
  final String? shift;
  final String? deviceId;
  final bool? skipAutoAttendance;
  final double? latitude;
  final double? longitude;
  final bool? faceVerified;
  final double? faceDistance;
  final String? serverMessage;

  factory EmployeeCheckin.fromJson(Map<String, dynamic> json) {
    return EmployeeCheckin(
      name: '${json['name'] ?? ''}',
      employee: '${json['employee'] ?? ''}',
      employeeName: json['employee_name'] as String?,
      logType: '${json['log_type'] ?? ''}',
      time: DateTime.tryParse('${json['time'] ?? ''}') ?? DateTime.now(),
      shift: json['shift'] as String?,
      deviceId: json['device_id'] as String?,
      skipAutoAttendance: _toBool(json['skip_auto_attendance']),
      latitude: _toDouble(json['custom_latitude'] ?? json['latitude']),
      longitude: _toDouble(json['custom_longitude'] ?? json['longitude']),
      faceVerified: _toBool(json['custom_face_verified']),
      faceDistance: _toDouble(json['distance']),
      serverMessage: json['message'] as String?,
    );
  }

  static double? _toDouble(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  static bool? _toBool(Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value == 1;
    return value == '1' || value == 'true';
  }

  String get timeLabel => DateFormats.shortTime.format(time);
  String get dateLabel => DateFormats.historyDate.format(time);
  bool get isIn => logType.toUpperCase() == 'IN';
}
