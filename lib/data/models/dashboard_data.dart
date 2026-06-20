import 'attendance_day_status.dart';
import 'employee.dart';
import 'employee_checkin.dart';
import 'holiday_item.dart';
import 'shift_details.dart';

class DashboardData {
  DashboardData({
    required this.user,
    required this.employee,
    required this.shiftDetails,
    required this.history,
    required this.holidays,
    this.isFaceRegistrationAdmin = false,
    AttendanceDayStatus? todayStatus,
  }) : todayStatus = todayStatus ?? AttendanceDayStatus.fromCheckins(const []);

  final String user;
  final Employee employee;
  final ShiftDetails shiftDetails;
  final List<EmployeeCheckin> history;
  final List<HolidayItem> holidays;
  final AttendanceDayStatus todayStatus;
  final bool isFaceRegistrationAdmin;

  EmployeeCheckin? get lastCheckin {
    if (history.isEmpty) return null;
    return history.first;
  }

  bool get isCurrentlyIn => todayStatus.canMarkOut;

  DashboardData copyWith({
    Employee? employee,
    List<EmployeeCheckin>? history,
    AttendanceDayStatus? todayStatus,
    bool? isFaceRegistrationAdmin,
  }) {
    return DashboardData(
      user: user,
      employee: employee ?? this.employee,
      shiftDetails: shiftDetails,
      history: history ?? this.history,
      holidays: holidays,
      todayStatus: todayStatus ?? this.todayStatus,
      isFaceRegistrationAdmin:
          isFaceRegistrationAdmin ?? this.isFaceRegistrationAdmin,
    );
  }
}
