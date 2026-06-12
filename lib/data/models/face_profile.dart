import 'dart:convert';

import '../../core/config/app_config.dart';
import '../../core/utils/date_formats.dart';
import '../../models/employee_face_data.dart';
import 'employee.dart';

class FaceProfile {
  const FaceProfile({
    required this.name,
    required this.employee,
    required this.employeeName,
    required this.userId,
    required this.faceEmbedding,
    this.embeddings = const [],
    this.kbyTemplatesBase64 = const [],
    this.modelVersion,
    this.faceQualityScore = 0,
    this.faceRegistered = true,
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
  final List<List<double>> embeddings;
  final List<String> kbyTemplatesBase64;
  final String? modelVersion;
  final double faceQualityScore;
  final bool faceRegistered;
  final int sampleCount;
  final bool isActive;
  final String? designation;
  final String? department;
  final String? company;
  final String? shift;
  final DateTime? registeredOn;
  final String? registeredDeviceId;
  final DateTime? lastUpdatedOn;

  bool get hasEmbedding => faceRegistered && faceEmbedding.isNotEmpty;

  bool get hasKbyTemplates => faceRegistered && kbyTemplatesBase64.isNotEmpty;

  FaceProfile copyWith({List<String>? kbyTemplatesBase64}) {
    return FaceProfile(
      name: name,
      employee: employee,
      employeeName: employeeName,
      userId: userId,
      faceEmbedding: faceEmbedding,
      embeddings: embeddings,
      kbyTemplatesBase64: kbyTemplatesBase64 ?? this.kbyTemplatesBase64,
      modelVersion: modelVersion,
      faceQualityScore: faceQualityScore,
      faceRegistered: faceRegistered,
      sampleCount: sampleCount,
      isActive: isActive,
      designation: designation,
      department: department,
      company: company,
      shift: shift,
      registeredOn: registeredOn,
      registeredDeviceId: registeredDeviceId,
      lastUpdatedOn: lastUpdatedOn,
    );
  }

  factory FaceProfile.fromJson(Map<String, dynamic> json) {
    final storedEmbeddings = EmployeeFaceData.decodeEmbeddingsPayload(
      json['face_embeddings'],
    );
    final storedAverage = EmployeeFaceData.decodeAveragePayload(
      json['face_embeddings'],
    );
    final payloadModelVersion = EmployeeFaceData.decodeModelVersionPayload(
      json['face_embeddings'],
    );
    final legacyEmbedding = decodeEmbedding(json['face_embedding']);
    final average = storedAverage.isNotEmpty ? storedAverage : legacyEmbedding;
    return FaceProfile(
      name: '${json['name'] ?? ''}',
      employee: '${json['employee'] ?? json['employee_id'] ?? ''}',
      employeeName: '${json['employee_name'] ?? ''}',
      userId: '${json['user_id'] ?? ''}',
      designation: json['designation'] as String?,
      department: json['department'] as String?,
      company: json['company'] as String?,
      shift: json['shift'] as String?,
      faceEmbedding: average,
      embeddings: storedEmbeddings.isNotEmpty
          ? storedEmbeddings
          : legacyEmbedding.isEmpty
          ? const []
          : [legacyEmbedding],
      kbyTemplatesBase64: EmployeeFaceData.decodeStringList(
        json['kby_templates_base64'] ?? json['kby_templates'],
      ),
      modelVersion: _string(json['face_model_version']) ?? payloadModelVersion,
      faceQualityScore: _toDouble(json['face_quality_score']),
      faceRegistered: _toBool(json['face_registered']) ?? true,
      sampleCount: _toInt(json['sample_count'] ?? json['face_embedding_count']),
      isActive: _toBool(json['is_active']) ?? true,
      registeredOn: _toDate(json['registered_on'] ?? json['face_updated_on']),
      registeredDeviceId: json['registered_device_id'] as String?,
      lastUpdatedOn: _toDate(
        json['last_updated_on'] ?? json['face_updated_on'],
      ),
    );
  }

  static Map<String, Object?> createPayload({
    required Employee employee,
    required List<double> embedding,
    List<List<double>> embeddings = const [],
    String modelVersion = '',
    double qualityScore = 0,
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
      'shift': employee.resolvedShift ?? '',
      'face_embedding': encodeEmbedding(embedding),
      'face_embeddings': EmployeeFaceData.encodeEmbeddingsPayload(
        embeddings: embeddings.isEmpty ? [embedding] : embeddings,
        averageEmbedding: embedding,
        modelVersion: modelVersion,
        qualityScore: qualityScore,
        engineName: AppConfig.faceEngineName,
        embeddingDimension: embedding.length,
        thresholdVersion: AppConfig.faceThresholdVersion,
      ),
      'face_registered': 1,
      'face_model_version': modelVersion,
      'face_quality_score': qualityScore,
      'face_embedding_count': sampleCount,
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
    List<List<double>> embeddings = const [],
    String modelVersion = '',
    double qualityScore = 0,
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
      'shift': employee.resolvedShift ?? '',
      'face_embedding': encodeEmbedding(embedding),
      'face_embeddings': EmployeeFaceData.encodeEmbeddingsPayload(
        embeddings: embeddings.isEmpty ? [embedding] : embeddings,
        averageEmbedding: embedding,
        modelVersion: modelVersion,
        qualityScore: qualityScore,
        engineName: AppConfig.faceEngineName,
        embeddingDimension: embedding.length,
        thresholdVersion: AppConfig.faceThresholdVersion,
      ),
      'face_registered': 1,
      'face_model_version': modelVersion,
      'face_quality_score': qualityScore,
      'face_embedding_count': sampleCount,
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

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
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
