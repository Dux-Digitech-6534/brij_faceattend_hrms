import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/employee.dart';

class SessionStore {
  SessionStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  static const _sessionCookieKey = 'session_cookie';
  static const _loggedInUserKey = 'logged_in_user';
  static const _employeeKey = 'employee';

  Future<void> saveSessionCookie(String cookie) {
    return _secureStorage.write(key: _sessionCookieKey, value: cookie);
  }

  Future<String?> readSessionCookie() {
    return _secureStorage.read(key: _sessionCookieKey);
  }

  Future<void> saveLoggedInUser(String user) {
    return _secureStorage.write(key: _loggedInUserKey, value: user);
  }

  Future<String?> readLoggedInUser() {
    return _secureStorage.read(key: _loggedInUserKey);
  }

  Future<void> saveEmployee(Employee employee) {
    return _secureStorage.write(key: _employeeKey, value: employee.encoded);
  }

  Future<Employee?> readEmployee() async {
    final value = await _secureStorage.read(key: _employeeKey);
    if (value == null || value.isEmpty) return null;
    return Employee.fromStoredJson(value);
  }

  Future<bool> hasSession() async {
    final cookie = await readSessionCookie();
    return cookie != null && cookie.trim().isNotEmpty;
  }

  Future<void> clear() async {
    await _secureStorage.delete(key: _sessionCookieKey);
    await _secureStorage.delete(key: _loggedInUserKey);
    await _secureStorage.delete(key: _employeeKey);
  }
}
