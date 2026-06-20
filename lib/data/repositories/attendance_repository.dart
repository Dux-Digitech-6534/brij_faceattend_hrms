import '../../core/config/app_config.dart';
import '../../core/utils/erp_error.dart';
import '../api/api_client.dart';
import '../models/attendance_day_status.dart';
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
    await _apiClient.getMobileEmployees(modifiedAfter: employee.modified);
    final shift = await _apiClient.getShiftDetails(employee);
    final todayCheckins = await _apiClient.getTodayEmployeeCheckins(
      employee.name,
    );
    final history = await _apiClient.getAttendanceHistory(employee.name);
    final holidays = await _apiClient.getHolidays(employee);
    return DashboardData(
      user: user,
      employee: employee,
      shiftDetails: shift,
      history: history,
      holidays: holidays,
      todayStatus: AttendanceDayStatus.fromCheckins(todayCheckins),
    );
  }

  Future<AttendanceDayStatus> loadTodayStatus(Employee employee) async {
    final checkins = await _apiClient.getTodayEmployeeCheckins(employee.name);
    return AttendanceDayStatus.fromCheckins(checkins);
  }

  Future<EmployeeCheckin> markAttendance({
    required Employee employee,
    required String logType,
    required DateTime time,
    required double latitude,
    required double longitude,
    required double accuracy,
    required bool faceVerified,
    required String capturedImagePath,
    required List<double> faceEmbedding,
    String appDeviceId = AppConfig.appDeviceId,
  }) async {
    final shift = employee.resolvedShift;
    if (shift == null || shift.trim().isEmpty) {
      throw const ErpError('Shift not assigned. Please contact HR.');
    }

    final normalizedLogType = logType.toUpperCase();

    try {
      return await _apiClient.verifyFaceAndMarkAttendance(
        labourName: employee.name,
        imagePath: capturedImagePath,
        shift: shift,
        logType: normalizedLogType,
        time: time,
        latitude: latitude,
        longitude: longitude,
        appDeviceId: appDeviceId,
        faceEmbedding: faceEmbedding,
      );
    } catch (error) {
      if (!isServerMethodMissingError(error)) rethrow;
      return _apiClient.createEmployeeCheckin(
        employee: employee.name,
        shift: shift,
        logType: normalizedLogType,
        time: time,
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        faceVerified: faceVerified,
        appDeviceId: appDeviceId,
      );
    }
  }

  Future<void> logout() => _apiClient.logout();
}
