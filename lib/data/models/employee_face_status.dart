class EmployeeFaceStatus {
  const EmployeeFaceStatus({
    required this.employee,
    required this.faceRegistered,
    this.registeredOn,
    this.registeredBy,
    this.status,
    this.isActive = false,
  });

  final String employee;
  final bool faceRegistered;
  final DateTime? registeredOn;
  final String? registeredBy;
  final String? status;
  final bool isActive;

  factory EmployeeFaceStatus.fromJson(Map<String, dynamic> json) {
    return EmployeeFaceStatus(
      employee: '${json['employee'] ?? ''}',
      faceRegistered: _bool(json['face_registered'] ?? json['registered']),
      registeredOn: DateTime.tryParse('${json['registered_on'] ?? ''}'),
      registeredBy: _string(json['registered_by']),
      status: _string(json['status']),
      isActive: _bool(json['is_active'] ?? json['active']),
    );
  }

  static bool _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    final text = '$value'.trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }
}
