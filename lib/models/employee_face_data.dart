import 'dart:convert';
import 'dart:math' as math;

class EmployeeFaceData {
  const EmployeeFaceData({
    required this.employeeId,
    required this.employeeName,
    required this.embeddings,
    required this.averageEmbedding,
    this.kbyTemplatesBase64 = const [],
    required this.modelVersion,
    required this.faceRegistered,
    required this.faceQualityScore,
    required this.updatedAt,
  });

  final String employeeId;
  final String employeeName;
  final List<List<double>> embeddings;
  final List<double> averageEmbedding;
  final List<String> kbyTemplatesBase64;
  final String modelVersion;
  final bool faceRegistered;
  final double faceQualityScore;
  final DateTime updatedAt;

  bool get hasEmbedding => faceRegistered && averageEmbedding.isNotEmpty;

  bool get hasKbyTemplates => faceRegistered && kbyTemplatesBase64.isNotEmpty;

  int get embeddingCount => embeddings.length;

  Map<String, dynamic> toJson() {
    return {
      'employeeId': employeeId,
      'employeeName': employeeName,
      'embeddings': embeddings,
      'averageEmbedding': averageEmbedding,
      'kbyTemplatesBase64': kbyTemplatesBase64,
      'modelVersion': modelVersion,
      'faceRegistered': faceRegistered,
      'faceQualityScore': faceQualityScore,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  String get encoded => jsonEncode(toJson());

  factory EmployeeFaceData.fromJson(Map<String, dynamic> json) {
    final embeddings = _decodeEmbeddings(json['embeddings']);
    final average = _decodeEmbedding(
      json['averageEmbedding'] ?? json['average_embedding'],
    );
    return EmployeeFaceData(
      employeeId: _string(json['employeeId'] ?? json['employee_id']) ?? '',
      employeeName:
          _string(json['employeeName'] ?? json['employee_name']) ?? 'Employee',
      embeddings: embeddings,
      averageEmbedding: average.isNotEmpty
          ? average
          : averageEmbeddings(embeddings),
      kbyTemplatesBase64: decodeStringList(
        json['kbyTemplatesBase64'] ??
            json['kby_templates_base64'] ??
            json['kby_templates'],
      ),
      modelVersion:
          _string(json['modelVersion'] ?? json['model_version']) ?? '',
      faceRegistered: _bool(json['faceRegistered'] ?? json['face_registered']),
      faceQualityScore: _double(
        json['faceQualityScore'] ?? json['face_quality_score'],
      ),
      updatedAt:
          DateTime.tryParse(
            '${json['updatedAt'] ?? json['updated_at'] ?? ''}',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  factory EmployeeFaceData.fromEncoded(String source) {
    return EmployeeFaceData.fromJson(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }

  static String encodeEmbeddingsPayload({
    required List<List<double>> embeddings,
    required List<double> averageEmbedding,
    required String modelVersion,
    required double qualityScore,
  }) {
    return jsonEncode({
      'embeddings': embeddings
          .map((sample) => sample.map(_round).toList(growable: false))
          .toList(growable: false),
      'average_embedding': averageEmbedding.map(_round).toList(growable: false),
      'model_version': modelVersion,
      'quality_score': _round(qualityScore),
    });
  }

  static List<List<double>> decodeEmbeddingsPayload(Object? source) {
    if (source == null) return const [];
    try {
      final decoded = source is String ? jsonDecode(source) : source;
      if (decoded is Map) {
        return _decodeEmbeddings(decoded['embeddings']);
      }
      return _decodeEmbeddings(decoded);
    } catch (_) {
      return const [];
    }
  }

  static List<double> decodeAveragePayload(Object? source) {
    if (source == null) return const [];
    try {
      final decoded = source is String ? jsonDecode(source) : source;
      if (decoded is Map) {
        final average = _decodeEmbedding(
          decoded['average_embedding'] ?? decoded['averageEmbedding'],
        );
        if (average.isNotEmpty) return average;
        return averageEmbeddings(_decodeEmbeddings(decoded['embeddings']));
      }
      return _decodeEmbedding(decoded);
    } catch (_) {
      return const [];
    }
  }

  static List<double> averageEmbeddings(List<List<double>> samples) {
    if (samples.isEmpty) return const [];
    final length = samples.map((item) => item.length).reduce(math.min);
    if (length == 0) return const [];
    final values = List<double>.filled(length, 0);
    for (final sample in samples) {
      for (var i = 0; i < length; i++) {
        values[i] += sample[i];
      }
    }
    for (var i = 0; i < length; i++) {
      values[i] = values[i] / samples.length;
    }
    return l2Normalize(values);
  }

  static List<double> l2Normalize(List<double> values) {
    if (values.isEmpty) return const [];
    final magnitude = math.sqrt(
      values.fold<double>(0, (sum, value) => sum + value * value),
    );
    if (magnitude == 0) return values;
    return values.map((value) => value / magnitude).toList(growable: false);
  }

  static List<List<double>> _decodeEmbeddings(Object? source) {
    if (source is! List) return const [];
    return source
        .whereType<List>()
        .map(_decodeEmbedding)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<double> _decodeEmbedding(Object? source) {
    if (source is! List) return const [];
    return source
        .map((value) {
          if (value is num) return value.toDouble();
          return double.tryParse('$value') ?? 0;
        })
        .toList(growable: false);
  }

  static List<String> decodeStringList(Object? source) {
    if (source is String) {
      try {
        final decoded = jsonDecode(source);
        return decodeStringList(decoded);
      } catch (_) {
        return source.trim().isEmpty ? const [] : [source];
      }
    }
    if (source is! List) return const [];
    return source
        .map((value) => '$value'.trim())
        .where((value) => value.isNotEmpty && value.toLowerCase() != 'null')
        .toList(growable: false);
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  static bool _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    final text = '$value'.trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }

  static double _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  static double _round(double value) => double.parse(value.toStringAsFixed(6));
}
