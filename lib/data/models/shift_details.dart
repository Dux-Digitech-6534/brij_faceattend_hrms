class ShiftDetails {
  const ShiftDetails({
    this.name,
    this.startTime,
    this.endTime,
    this.beginCheckInBeforeShiftStartTime,
    this.allowCheckOutAfterShiftEndTime,
    this.isNightShift = false,
    this.fetchedFromErp = false,
  });

  final String? name;
  final String? startTime;
  final String? endTime;
  final int? beginCheckInBeforeShiftStartTime;
  final int? allowCheckOutAfterShiftEndTime;
  final bool isNightShift;
  final bool fetchedFromErp;

  factory ShiftDetails.fromJson(Map<String, dynamic> json) {
    return ShiftDetails(
      name: json['name'] as String?,
      startTime: json['start_time'] as String?,
      endTime: json['end_time'] as String?,
      beginCheckInBeforeShiftStartTime: _toInt(
        json['begin_check_in_before_shift_start_time'],
      ),
      allowCheckOutAfterShiftEndTime: _toInt(
        json['allow_check_out_after_shift_end_time'],
      ),
      isNightShift:
          _toBool(json['enable_auto_attendance_for_night_shift']) ||
          _toBool(json['is_night_shift']),
      fetchedFromErp: true,
    );
  }

  static int? _toInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  static bool _toBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    return value == '1' || value == 'true';
  }

  String get displayName => name ?? 'Shift not assigned';

  String get displayTime {
    if (startTime == null && endTime == null) return 'Sync from ERPNext';
    return '${_formatTime(startTime)} - ${_formatTime(endTime)}';
  }

  static String _formatTime(String? time) {
    if (time == null || time.isEmpty) return '--:--';
    final parts = time.split(':');
    if (parts.length < 2) return time;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts[1].padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$hour12:$minute $period';
  }
}
