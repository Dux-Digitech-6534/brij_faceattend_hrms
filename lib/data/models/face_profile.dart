import 'dart:convert';

import '../../core/utils/date_formats.dart';
import 'employee.dart';

class FaceProfile {
  const FaceProfile({
    required this.name,
    required this.employee,
    required this.employeeName,
    required this.userId,
    required this.faceEmbedding,
    required this.sampleCount,
    required this.isActive,
    this.designation,
    this.department,
    this.company,
    this.shift,
    this.registeredOn,
    this.registeredDeviceId,
    this.lastUpdatedOn,
  });

  final String name;
  final String employee;
  final String employeeName;
  final String userId;
  final List<double> faceEmbedding;
  final int sampleCount;
  final bool isActive;
  final String? designation;
  final String? department;
  final String? company;
  final String? shift;
  final DateTime? registeredOn;
  final String? registeredDeviceId;
  final DateTime? lastUpdatedOn;

  bool get hasEmbedding => faceEmbedding.isNotEmpty;

  factory FaceProfile.fromJson(Map<String, dynamic> json) {
    return FaceProfile(
      name: '${json['name'] ?? ''}',
      employee: '${json['employee'] ?? ''}',
      employeeName: '${json['employee_name'] ?? ''}',
      userId: '${json['user_id'] ?? ''}',
      designation: json['designation'] as String?,
      department: json['department'] as String?,
      company: json['company'] as String?,
      shift: json['shift'] as String?,
      faceEmbedding: decodeEmbedding(json['face_embedding']),
      sampleCount: _toInt(json['sample_count']),
      isActive: _toBool(json['is_active']) ?? true,
      registeredOn: _toDate(json['registered_on']),
      registeredDeviceId: json['registered_device_id'] as String?,
      lastUpdatedOn: _toDate(json['last_updated_on']),
    );
  }

  static Map<String, Object?> createPayload({
    required Employee employee,
    required List<double> embedding,
    required int sampleCount,
    required String deviceId,
  }) {
    final now = DateFormats.forErp(DateTime.now());
    return {
      'employee': employee.name,
      'employee_name': employee.employeeName,
      'user_id': employee.userId ?? '',
      'designation': employee.designation ?? '',
      'department': employee.department ?? '',
      'company': employee.company ?? '',
      'shift': employee.defaultShift ?? '',
      'face_embedding': encodeEmbedding(embedding),
      'sample_count': sampleCount,
      'is_active': 1,
      'registered_on': now,
      'registered_device_id': deviceId,
      'last_updated_on': now,
    };
  }

  static Map<String, Object?> updatePayload({
    required Employee employee,
    required List<double> embedding,
    required int sampleCount,
    required String deviceId,
  }) {
    return {
      'employee': employee.name,
      'employee_name': employee.employeeName,
      'user_id': employee.userId ?? '',
      'designation': employee.designation ?? '',
      'department': employee.department ?? '',
      'company': employee.company ?? '',
      'shift': employee.defaultShift ?? '',
      'face_embedding': encodeEmbedding(embedding),
      'sample_count': sampleCount,
      'is_active': 1,
      'registered_device_id': deviceId,
      'last_updated_on': DateFormats.forErp(DateTime.now()),
    };
  }

  static String encodeEmbedding(List<double> embedding) {
    return jsonEncode(
      embedding.map((value) => double.parse(value.toStringAsFixed(6))).toList(),
    );
  }

  static List<double> decodeEmbedding(Object? source) {
    if (source == null) return const [];
    try {
      final decoded = source is String ? jsonDecode(source) : source;
      if (decoded is! List) return const [];
      return decoded
          .map((value) {
            if (value is num) return value.toDouble();
            return double.tryParse('$value') ?? 0;
          })
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static int _toInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static bool? _toBool(Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value == 1;
    final text = '$value'.toLowerCase();
    return text == '1' || text == 'true';
  }

  static DateTime? _toDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse('$value');
  }
}
