import 'employee_checkin.dart';

class AttendanceDayStatus {
  AttendanceDayStatus._(this.checkins);

  factory AttendanceDayStatus.fromCheckins(List<EmployeeCheckin> source) {
    final sorted = List<EmployeeCheckin>.from(source)
      ..sort((a, b) => a.time.compareTo(b.time));
    return AttendanceDayStatus._(List.unmodifiable(sorted));
  }

  final List<EmployeeCheckin> checkins;

  EmployeeCheckin? get firstIn {
    for (final item in checkins) {
      if (item.logType.toUpperCase() == 'IN') return item;
    }
    return null;
  }

  EmployeeCheckin? get lastOut {
    for (final item in checkins.reversed) {
      if (item.logType.toUpperCase() == 'OUT') return item;
    }
    return null;
  }

  bool get hasIn => firstIn != null;
  bool get hasOut => lastOut != null;
  bool get canMarkIn => !hasIn;
  bool get canMarkOut => hasIn && !hasOut;
  bool get completed => hasIn && hasOut;

  String? get nextLogType {
    if (canMarkIn) return 'IN';
    if (canMarkOut) return 'OUT';
    return null;
  }

  bool canSubmit(String logType) {
    final normalized = logType.toUpperCase();
    return normalized == 'IN' ? canMarkIn : normalized == 'OUT' && canMarkOut;
  }

  String get title {
    if (completed) return 'Completed';
    if (canMarkOut) return 'Checked In';
    return 'Not marked yet';
  }

  String duplicateMessage(String logType) {
    final normalized = logType.toUpperCase();
    if (completed) return "Today's attendance completed.";
    if (normalized == 'IN' && hasIn) {
      return 'Mark In is already recorded today.';
    }
    if (normalized == 'OUT' && hasOut) {
      return 'Mark Out is already recorded today.';
    }
    if (normalized == 'OUT' && !hasIn) return 'Please Mark In first.';
    return 'Attendance state was refreshed. Please try again.';
  }
}
