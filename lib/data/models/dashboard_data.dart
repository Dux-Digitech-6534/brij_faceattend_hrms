import 'employee.dart';
import 'employee_checkin.dart';
import 'holiday_item.dart';
import 'shift_details.dart';

class DashboardData {
  const DashboardData({
    required this.user,
    required this.employee,
    required this.shiftDetails,
    required this.history,
    required this.holidays,
  });

  final String user;
  final Employee employee;
  final ShiftDetails shiftDetails;
  final List<EmployeeCheckin> history;
  final List<HolidayItem> holidays;

  EmployeeCheckin? get lastCheckin {
    if (history.isEmpty) return null;
    return history.first;
  }

  bool get isCurrentlyIn => lastCheckin?.isIn ?? false;
}
