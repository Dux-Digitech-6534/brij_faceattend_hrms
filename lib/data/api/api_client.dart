import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/date_formats.dart';
import '../../core/utils/erp_error.dart';
import '../models/employee.dart';
import '../models/employee_checkin.dart';
import '../models/face_profile.dart';
import '../models/holiday_item.dart';
import '../models/shift_details.dart';
import '../services/session_store.dart';

class ApiClient {
  ApiClient(this._sessionStore)
    : _dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.baseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 20),
          headers: const {'Accept': 'application/json'},
        ),
      ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final cookie = await _sessionStore.readSessionCookie();
          if (cookie != null && cookie.isNotEmpty) {
            options.headers['Cookie'] = cookie;
          }
          handler.next(options);
        },
      ),
    );
  }

  final SessionStore _sessionStore;
  final Dio _dio;

  Future<void> login(String username, String password) async {
    try {
      final response = await _dio.post<Object?>(
        '/api/method/login',
        data: {'usr': username.trim(), 'pwd': password},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final cookie = _readCookie(response.headers);
      if (cookie == null || cookie.isEmpty) {
        throw const ErpError(
          'Login succeeded, but no session cookie was returned.',
        );
      }

      await _sessionStore.saveSessionCookie(cookie);
    } on DioException catch (error) {
      throw _buildErpError(error, fallback: 'Unable to login to ERPNext.');
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post<Object?>('/api/method/logout');
    } catch (_) {
      // Clearing the local session is still the right outcome if logout fails.
    } finally {
      await _sessionStore.clear();
    }
  }

  Future<String> getLoggedInUser() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/method/frappe.auth.get_logged_user',
      );
      final user = '${response.data?['message'] ?? ''}';
      if (user.isEmpty || user == 'Guest') {
        throw const ErpError(
          'ERPNext did not return a logged-in employee user.',
        );
      }
      await _sessionStore.saveLoggedInUser(user);
      return user;
    } on DioException catch (error) {
      throw _buildErpError(error, fallback: 'Unable to fetch logged-in user.');
    }
  }

  Future<Employee> getEmployeeByUser(String user) async {
    try {
      final employee = await _getLoggedEmployeeViaCustomMethod(user);
      await _sessionStore.saveEmployee(employee);
      return employee;
    } on DioException catch (customError) {
      if (!_canFallbackFromCustomMethod(customError)) {
        throw _employeeLookupError();
      }
    }

    final employee = await _fetchEmployeeByEmailFallback(user);
    if (employee == null) {
      throw _employeeLookupError();
    }
    await _sessionStore.saveEmployee(employee);
    return employee;
  }

  Future<Employee> _getLoggedEmployeeViaCustomMethod(String user) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/method/hrms_mobile.api.employee.get_logged_employee',
    );
    final employee = _readEmployeeResponse(response.data, user);
    if (employee == null || employee.name.trim().isEmpty) {
      throw _employeeLookupError();
    }
    return employee;
  }

  Future<Employee?> _fetchEmployeeByEmailFallback(String user) async {
    for (final field in _employeeEmailLookupFields) {
      try {
        final response = await _dio.get<Map<String, dynamic>>(
          '/api/resource/Employee',
          queryParameters: {
            'filters': jsonEncode([
              [field, '=', user],
            ]),
            'fields': jsonEncode(_employeeListFields),
            'limit_page_length': 1,
          },
        );

        final data = response.data?['data'];
        if (data is! List || data.isEmpty || data.first is! Map) {
          continue;
        }

        final row = Map<String, dynamic>.from(data.first as Map);
        final employeeName = '${row['name'] ?? ''}';
        if (employeeName.isEmpty) continue;
        return await _fetchEmployeeDetailsByName(employeeName, user) ??
            Employee.fromJson({...row, 'user_id': user});
      } on DioException catch (error) {
        if (_isFieldOrPermissionError(error) || _isMissingFieldError(error)) {
          continue;
        }
        continue;
      }
    }

    return null;
  }

  Future<Employee?> _fetchEmployeeDetailsByName(
    String employeeName,
    String user,
  ) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/resource/Employee/${Uri.encodeComponent(employeeName)}',
      );
      return _readEmployeeResponse(response.data, user);
    } on DioException {
      return null;
    }
  }

  Future<ShiftDetails> getShiftDetails(Employee employee) async {
    final shiftName = employee.defaultShift;
    if (shiftName == null || shiftName.trim().isEmpty) {
      return const ShiftDetails();
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/resource/Shift Type/${Uri.encodeComponent(shiftName)}',
        queryParameters: {
          'fields': jsonEncode([
            'name',
            'start_time',
            'end_time',
            'begin_check_in_before_shift_start_time',
            'allow_check_out_after_shift_end_time',
            'enable_auto_attendance_for_night_shift',
            'is_night_shift',
          ]),
        },
      );
      final data = response.data?['data'];
      if (data is Map) {
        return ShiftDetails.fromJson(Map<String, dynamic>.from(data));
      }
      return const ShiftDetails();
    } on DioException catch (error) {
      if (_isFieldOrPermissionError(error) || _isMissingFieldError(error)) {
        return const ShiftDetails();
      }
      throw _buildErpError(error, fallback: 'Unable to fetch shift details.');
    }
  }

  Future<List<HolidayItem>> getHolidays(Employee employee) async {
    final holidayList = employee.holidayList;
    if (holidayList == null || holidayList.trim().isEmpty) return const [];

    try {
      final today = DateTime.now();
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/resource/Holiday',
        queryParameters: {
          'filters': jsonEncode([
            ['parent', '=', holidayList],
            [
              'holiday_date',
              '>=',
              DateFormats.erpDate.format(
                DateTime(today.year, today.month, today.day),
              ),
            ],
          ]),
          'fields': jsonEncode(['name', 'holiday_date', 'description']),
          'order_by': 'holiday_date asc',
          'limit_page_length': 10,
        },
      );

      final data = response.data?['data'];
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((item) => HolidayItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on DioException catch (error) {
      if (_isFieldOrPermissionError(error) || _isMissingFieldError(error)) {
        return const [];
      }
      throw _buildErpError(error, fallback: 'Unable to fetch holiday list.');
    }
  }

  Future<List<EmployeeCheckin>> getAttendanceHistory(String employee) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/resource/Employee Checkin',
        queryParameters: {
          'filters': jsonEncode([
            ['employee', '=', employee],
          ]),
          'fields': jsonEncode([
            'name',
            'employee',
            'employee_name',
            'time',
            'log_type',
            'shift',
            'device_id',
            'skip_auto_attendance',
          ]),
          'order_by': 'time desc',
          'limit_page_length': 40,
        },
      );

      final data = response.data?['data'];
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map(
            (item) => EmployeeCheckin.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
    } on DioException catch (error) {
      throw _buildErpError(
        error,
        fallback: 'Unable to fetch attendance history.',
      );
    }
  }

  Future<EmployeeCheckin> createEmployeeCheckin({
    required String employee,
    required String logType,
    required DateTime time,
    required double latitude,
    required double longitude,
    required double accuracy,
    required bool faceVerified,
    required String appDeviceId,
  }) async {
    if (AppConfig.useCustomAttendanceEndpoint) {
      return _createViaCustomEndpoint(
        employee: employee,
        logType: logType,
        time: time,
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        faceVerified: faceVerified,
        appDeviceId: appDeviceId,
      );
    }

    final payload = <String, Object?>{
      'employee': employee,
      'log_type': logType.toUpperCase(),
      'time': DateFormats.forErp(time),
      'device_id': appDeviceId,
      'custom_face_verified': faceVerified ? 1 : 0,
      'custom_source': 'FaceAttend HRMS Flutter App',
      'custom_latitude': latitude,
      'custom_longitude': longitude,
      'custom_gps_accuracy': accuracy,
      'custom_app_device_id': appDeviceId,
    };

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/resource/Employee Checkin',
        data: payload,
      );
      return EmployeeCheckin.fromJson(
        Map<String, dynamic>.from(response.data?['data'] as Map),
      );
    } on DioException catch (error) {
      final rawMessage = _extractMessage(error.response?.data) ?? '';
      final erpError = _buildErpError(
        error,
        fallback: 'Unable to create Employee Checkin.',
      );
      if (_looksLikeMissingCustomField(rawMessage) ||
          _looksLikeMissingCustomField(erpError.message)) {
        return _createCheckinWithStandardPayload(payload);
      }
      throw erpError;
    }
  }

  Future<FaceProfile?> getFaceProfile(String employee) async {
    try {
      return await _getFaceProfileViaCustomMethod(employee);
    } on DioException catch (customError) {
      if (!_canFallbackFromCustomMethod(customError)) {
        return null;
      }
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/resource/${Uri.encodeComponent(_faceProfileDoctype)}',
        queryParameters: {
          'filters': jsonEncode([
            ['employee', '=', employee],
            ['is_active', '=', 1],
          ]),
          'fields': jsonEncode(['name']),
          'order_by': 'modified desc',
          'limit_page_length': 1,
        },
      );
      final data = response.data?['data'];
      if (data is! List || data.isEmpty) return null;
      final row = Map<String, dynamic>.from(data.first as Map);
      final profileName = '${row['name'] ?? ''}';
      if (profileName.isEmpty) return null;
      return await _fetchFaceProfileByName(profileName);
    } on DioException catch (error) {
      if (_isFieldOrPermissionError(error) ||
          _isMissingFieldError(error) ||
          _looksLikeMissingFaceProfileStorage(error)) {
        return null;
      }
      return null;
    }
  }

  Future<FaceProfile> saveFaceProfile({
    required Employee employee,
    required List<double> embedding,
    required int sampleCount,
    required String deviceId,
  }) async {
    final existing = await getFaceProfile(employee.name);
    if (existing != null && existing.name.isNotEmpty) {
      return updateFaceProfile(
        profileName: existing.name,
        employee: employee,
        embedding: embedding,
        sampleCount: sampleCount,
        deviceId: deviceId,
      );
    }

    try {
      return await _saveFaceProfileViaCustomMethod(
        employee: employee,
        embedding: embedding,
        sampleCount: sampleCount,
        deviceId: deviceId,
      );
    } on DioException catch (customError) {
      if (!_canFallbackFromCustomMethod(customError)) {
        throw _faceProfileSaveError();
      }
    }

    final payload = FaceProfile.createPayload(
      employee: employee,
      embedding: embedding,
      sampleCount: sampleCount,
      deviceId: deviceId,
    );

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/resource/${Uri.encodeComponent(_faceProfileDoctype)}',
        data: payload,
      );
      return _readFaceProfileResponse(response.data);
    } on DioException catch (error) {
      if (_isFieldOrPermissionError(error) || _isMissingFieldError(error)) {
        return _createFaceProfileWithEssentialPayload(
          employee: employee,
          embedding: embedding,
          sampleCount: sampleCount,
          deviceId: deviceId,
        );
      }
      throw _faceProfileSaveError();
    }
  }

  Future<FaceProfile> updateFaceProfile({
    required String profileName,
    required Employee employee,
    required List<double> embedding,
    required int sampleCount,
    required String deviceId,
  }) async {
    try {
      return await _saveFaceProfileViaCustomMethod(
        employee: employee,
        embedding: embedding,
        sampleCount: sampleCount,
        deviceId: deviceId,
      );
    } on DioException catch (customError) {
      if (!_canFallbackFromCustomMethod(customError)) {
        throw _faceProfileSaveError();
      }
    }

    final payload = FaceProfile.updatePayload(
      employee: employee,
      embedding: embedding,
      sampleCount: sampleCount,
      deviceId: deviceId,
    );

    try {
      final response = await _dio.put<Map<String, dynamic>>(
        '/api/resource/${Uri.encodeComponent(_faceProfileDoctype)}/${Uri.encodeComponent(profileName)}',
        data: payload,
      );
      return _readFaceProfileResponse(response.data);
    } on DioException catch (error) {
      if (_isFieldOrPermissionError(error) || _isMissingFieldError(error)) {
        return _updateFaceProfileWithEssentialPayload(
          profileName: profileName,
          employee: employee,
          embedding: embedding,
          sampleCount: sampleCount,
          deviceId: deviceId,
        );
      }
      throw _faceProfileSaveError();
    }
  }

  Future<FaceProfile?> _getFaceProfileViaCustomMethod(String employee) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/method/hrms_mobile.api.face.get_face_profile',
      queryParameters: {'employee': employee},
    );
    return _readNullableFaceProfileResponse(response.data);
  }

  Future<FaceProfile> _saveFaceProfileViaCustomMethod({
    required Employee employee,
    required List<double> embedding,
    required int sampleCount,
    required String deviceId,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/method/hrms_mobile.api.face.save_face_profile',
      data: {
        'employee': employee.name,
        'employee_name': employee.employeeName,
        'user_id': employee.userId ?? '',
        'designation': employee.designation ?? '',
        'department': employee.department ?? '',
        'company': employee.company ?? '',
        'shift': employee.defaultShift ?? '',
        'face_embedding': FaceProfile.encodeEmbedding(embedding),
        'sample_count': sampleCount,
        'device_id': deviceId,
      },
    );
    return _readFaceProfileResponse(response.data);
  }

  Future<FaceProfile?> _fetchFaceProfileByName(String profileName) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/resource/${Uri.encodeComponent(_faceProfileDoctype)}/${Uri.encodeComponent(profileName)}',
      );
      return _readNullableFaceProfileResponse(response.data);
    } on DioException {
      return null;
    }
  }

  Future<FaceProfile> _createFaceProfileWithEssentialPayload({
    required Employee employee,
    required List<double> embedding,
    required int sampleCount,
    required String deviceId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/resource/${Uri.encodeComponent(_faceProfileDoctype)}',
        data: _essentialFaceProfilePayload(
          employee: employee,
          embedding: embedding,
          sampleCount: sampleCount,
          deviceId: deviceId,
        ),
      );
      return _readFaceProfileResponse(response.data);
    } on DioException {
      throw _faceProfileSaveError();
    }
  }

  Future<FaceProfile> _updateFaceProfileWithEssentialPayload({
    required String profileName,
    required Employee employee,
    required List<double> embedding,
    required int sampleCount,
    required String deviceId,
  }) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        '/api/resource/${Uri.encodeComponent(_faceProfileDoctype)}/${Uri.encodeComponent(profileName)}',
        data: _essentialFaceProfilePayload(
          employee: employee,
          embedding: embedding,
          sampleCount: sampleCount,
          deviceId: deviceId,
        ),
      );
      return _readFaceProfileResponse(response.data);
    } on DioException {
      throw _faceProfileSaveError();
    }
  }

  Future<EmployeeCheckin> _createCheckinWithStandardPayload(
    Map<String, Object?> payload,
  ) async {
    final fallbackPayload = <String, Object?>{
      'employee': payload['employee'],
      'time': payload['time'],
      'log_type': payload['log_type'],
      'device_id': payload['device_id'],
    };
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/resource/Employee Checkin',
        data: fallbackPayload,
      );
      return EmployeeCheckin.fromJson(
        Map<String, dynamic>.from(response.data?['data'] as Map),
      );
    } on DioException catch (error) {
      throw _buildErpError(
        error,
        fallback: 'Unable to create Employee Checkin.',
      );
    }
  }

  Future<EmployeeCheckin> _createViaCustomEndpoint({
    required String employee,
    required String logType,
    required DateTime time,
    required double latitude,
    required double longitude,
    required double accuracy,
    required bool faceVerified,
    required String appDeviceId,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        AppConfig.customAttendanceEndpoint,
        data: {
          'employee': employee,
          'log_type': logType.toUpperCase(),
          'time': DateFormats.forErp(time),
          'latitude': latitude,
          'longitude': longitude,
          'gps_accuracy': accuracy,
          'face_verified': faceVerified,
          'device_id': appDeviceId,
        },
      );
      final message = response.data?['message'];
      if (message is Map) {
        return EmployeeCheckin.fromJson(Map<String, dynamic>.from(message));
      }
      final data = response.data?['data'];
      if (data is Map) {
        return EmployeeCheckin.fromJson(Map<String, dynamic>.from(data));
      }
      return EmployeeCheckin(
        name: 'custom-${time.microsecondsSinceEpoch}',
        employee: employee,
        logType: logType,
        time: time,
        latitude: latitude,
        longitude: longitude,
        faceVerified: faceVerified,
      );
    } on DioException catch (error) {
      throw _buildErpError(
        error,
        fallback: 'Unable to mark attendance through the custom endpoint.',
      );
    }
  }

  static const _employeeEmailLookupFields = [
    'personal_email',
    'company_email',
    'prefered_email',
  ];

  static const _employeeListFields = ['name', 'employee_name'];

  static const _faceProfileDoctype = 'Employee Face Profile';

  static Employee? _readEmployeeResponse(
    Map<String, dynamic>? data,
    String user,
  ) {
    if (data == null) return null;
    final message = data['message'];
    if (message is Map) {
      return Employee.fromJson({
        ...Map<String, dynamic>.from(message),
        if (message['user_id'] == null) 'user_id': user,
      });
    }
    final restData = data['data'];
    if (restData is Map) {
      return Employee.fromJson({
        ...Map<String, dynamic>.from(restData),
        if (restData['user_id'] == null) 'user_id': user,
      });
    }
    return null;
  }

  static FaceProfile _readFaceProfileResponse(Map<String, dynamic>? data) {
    final profile = _readNullableFaceProfileResponse(data);
    if (profile == null) {
      throw const ErpError('ERPNext did not return the saved face profile.');
    }
    return profile;
  }

  static FaceProfile? _readNullableFaceProfileResponse(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;
    final message = data['message'];
    if (message is Map) {
      return FaceProfile.fromJson(Map<String, dynamic>.from(message));
    }
    if (message is List && message.isNotEmpty && message.first is Map) {
      return FaceProfile.fromJson(
        Map<String, dynamic>.from(message.first as Map),
      );
    }
    final restData = data['data'];
    if (restData is Map) {
      return FaceProfile.fromJson(Map<String, dynamic>.from(restData));
    }
    if (restData is List && restData.isNotEmpty && restData.first is Map) {
      return FaceProfile.fromJson(
        Map<String, dynamic>.from(restData.first as Map),
      );
    }
    return null;
  }

  static Map<String, Object?> _essentialFaceProfilePayload({
    required Employee employee,
    required List<double> embedding,
    required int sampleCount,
    required String deviceId,
  }) {
    final now = DateFormats.forErp(DateTime.now());
    return {
      'employee': employee.name,
      'employee_name': employee.employeeName,
      'face_embedding': FaceProfile.encodeEmbedding(embedding),
      'sample_count': sampleCount,
      'is_active': 1,
      'registered_on': now,
      'registered_device_id': deviceId,
      'last_updated_on': now,
    };
  }

  static ErpError _employeeLookupError() {
    return const ErpError(
      'Unable to find an Employee mapped with this ERPNext user. Please contact HRMS admin.',
    );
  }

  static ErpError _faceProfileSaveError() {
    return const ErpError(
      'Unable to save face profile. Please contact HRMS admin.',
    );
  }

  static String? _readCookie(Headers headers) {
    final values = headers.map['set-cookie'];
    if (values == null || values.isEmpty) return null;
    return values
        .map((cookie) => cookie.split(';').first.trim())
        .where((cookie) => cookie.isNotEmpty)
        .join('; ');
  }

  static bool _looksLikeMissingCustomField(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('custom_face_verified') ||
        normalized.contains('custom_source') ||
        normalized.contains('custom_latitude') ||
        normalized.contains('custom_longitude') ||
        normalized.contains('custom_gps_accuracy') ||
        normalized.contains('custom_app_device_id') ||
        normalized.contains('unknown column') ||
        normalized.contains('field not permitted') ||
        normalized.contains('not permitted');
  }

  static bool _canFallbackFromCustomMethod(DioException error) {
    final statusCode = error.response?.statusCode;
    final message = _extractMessage(error.response?.data)?.toLowerCase() ?? '';
    return statusCode == 404 ||
        statusCode == 403 ||
        message.contains('failed to get method') ||
        message.contains('module') ||
        message.contains('not found') ||
        message.contains('does not exist') ||
        message.contains('attributeerror') ||
        message.contains('importerror');
  }

  static bool _isFieldOrPermissionError(DioException error) {
    final message = _extractMessage(error.response?.data)?.toLowerCase() ?? '';
    return message.contains('field not permitted') ||
        message.contains('not permitted in query') ||
        message.contains('permission') ||
        message.contains('not permitted');
  }

  static bool _isMissingFieldError(DioException error) {
    final message = _extractMessage(error.response?.data)?.toLowerCase() ?? '';
    return message.contains('unknown column') ||
        message.contains('does not exist') ||
        message.contains('unknown field');
  }

  static bool _looksLikeMissingFaceProfileStorage(DioException error) {
    final message = _extractMessage(error.response?.data)?.toLowerCase() ?? '';
    return message.contains('employee face profile') &&
        (message.contains('does not exist') ||
            message.contains('not found') ||
            message.contains('permission') ||
            message.contains('not permitted'));
  }

  static ErpError _buildErpError(
    DioException error, {
    required String fallback,
  }) {
    final statusCode = error.response?.statusCode;
    final extracted = _extractMessage(error.response?.data);
    final message = _shouldHideServerFieldMessage(extracted)
        ? fallback
        : extracted ?? error.message ?? fallback;
    return ErpError(message, statusCode: statusCode);
  }

  static bool _shouldHideServerFieldMessage(String? message) {
    if (message == null) return false;
    final normalized = message.toLowerCase();
    return normalized.contains('field not permitted') ||
        normalized.contains('not permitted in query') ||
        normalized.contains('unknown column') ||
        normalized.contains('unknown field') ||
        normalized.contains('custom_face_verified') ||
        normalized.contains('custom_source') ||
        normalized.contains('custom_latitude') ||
        normalized.contains('custom_longitude') ||
        normalized.contains('custom_gps_accuracy') ||
        normalized.contains('custom_app_device_id');
  }

  static String? _extractMessage(Object? data) {
    if (data == null) return null;
    if (data is String) return data;
    if (data is! Map) return null;

    final map = Map<String, dynamic>.from(data);
    for (final key in ['message', '_error_message', 'exception', 'exc_type']) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return _clean(value);
    }

    final serverMessages = map['_server_messages'];
    if (serverMessages is String && serverMessages.isNotEmpty) {
      try {
        final decoded = jsonDecode(serverMessages);
        if (decoded is List && decoded.isNotEmpty) {
          final first = decoded.first;
          if (first is String) {
            final inner = jsonDecode(first);
            if (inner is Map && inner['message'] is String) {
              return _clean(inner['message'] as String);
            }
            return _clean(first);
          }
        }
      } catch (_) {
        return _clean(serverMessages);
      }
    }

    return null;
  }

  static String _clean(String message) {
    return message
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }
}
