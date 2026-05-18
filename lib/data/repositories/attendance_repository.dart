import '../../core/config/app_config.dart';
import '../api/api_client.dart';
import '../models/dashboard_data.dart';
import '../models/employee.dart';
import '../models/employee_checkin.dart';

class AttendanceRepository {
  const AttendanceRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<DashboardData> login(String username, String password) async {
    await _apiClient.login(username, password);
    return loadDashboard();
  }

  Future<DashboardData> loadDashboard() async {
    final user = await _apiClient.getLoggedInUser();
    final employee = await _apiClient.getEmployeeByUser(user);
    final shift = await _apiClient.getShiftDetails(employee);
    final history = await _apiClient.getAttendanceHistory(employee.name);
    final holidays = await _apiClient.getHolidays(employee);
    return DashboardData(
      user: user,
      employee: employee,
      shiftDetails: shift,
      history: history,
      holidays: holidays,
    );
  }

  Future<EmployeeCheckin> markAttendance({
    required Employee employee,
    required String logType,
    required DateTime time,
    required double latitude,
    required double longitude,
    required double accuracy,
    required bool faceVerified,
    String appDeviceId = AppConfig.appDeviceId,
  }) {
    return _apiClient.createEmployeeCheckin(
      employee: employee.name,
      logType: logType,
      time: time,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      faceVerified: faceVerified,
      appDeviceId: appDeviceId,
    );
  }

  Future<void> logout() => _apiClient.logout();
}
