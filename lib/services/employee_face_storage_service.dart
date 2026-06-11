import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/employee_face_data.dart';

class EmployeeFaceStorageService {
  EmployeeFaceStorageService({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  Future<void> save(EmployeeFaceData data) {
    return _secureStorage.write(
      key: _key(data.employeeId),
      value: data.encoded,
    );
  }

  Future<EmployeeFaceData?> read(String employeeId) async {
    final value = await _secureStorage.read(key: _key(employeeId));
    if (value == null || value.trim().isEmpty) return null;
    try {
      return EmployeeFaceData.fromEncoded(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String employeeId) {
    return _secureStorage.delete(key: _key(employeeId));
  }

  static String _key(String employeeId) => 'employee_face_data_$employeeId';
}
