import 'dart:convert';

class Employee {
  const Employee({
    required this.name,
    required this.employeeName,
    this.userId,
    this.companyEmail,
    this.personalEmail,
    this.preferredEmail,
    this.designation,
    this.department,
    this.company,
    this.defaultShift,
    this.activeShift,
    this.branch,
    this.holidayList,
    this.status,
    this.isActive = true,
    this.image,
    this.cellNumber,
    this.modified,
    this.faceRegistered = false,
    this.faceEmbeddings,
    this.faceUpdatedOn,
    this.faceModelVersion,
    this.faceQualityScore = 0,
    this.faceEmbeddingCount = 0,
  });

  final String name;
  final String employeeName;
  final String? userId;
  final String? companyEmail;
  final String? personalEmail;
  final String? preferredEmail;
  final String? designation;
  final String? department;
  final String? company;
  final String? defaultShift;
  final String? activeShift;
  final String? branch;
  final String? holidayList;
  final String? status;
  final bool isActive;
  final String? image;
  final String? cellNumber;
  final String? modified;
  final bool faceRegistered;
  final String? faceEmbeddings;
  final DateTime? faceUpdatedOn;
  final String? faceModelVersion;
  final double faceQualityScore;
  final int faceEmbeddingCount;

  factory Employee.fromJson(Map<String, dynamic> json) {
    final status = _string(json['status']);
    return Employee(
      name:
          _string(json['employee_id'] ?? json['employee'] ?? json['name']) ??
          '',
      employeeName:
          _string(json['employee_name'] ?? json['employee'] ?? json['name']) ??
          'Employee',
      userId: _string(json['user_id']),
      companyEmail: _string(json['company_email']),
      personalEmail: _string(json['personal_email']),
      preferredEmail: _string(
        json['prefered_email'] ?? json['preferred_email'],
      ),
      designation: _string(json['designation']),
      department: _string(json['department']),
      company: _string(json['company']),
      defaultShift: _string(json['default_shift']),
      activeShift: _string(json['active_shift'] ?? json['shift']),
      branch: _string(json['branch']),
      holidayList: _string(json['holiday_list']),
      status: status,
      isActive: _readActive(json['is_active'], status),
      image: _string(json['image']),
      cellNumber: _string(json['cell_number']),
      modified: _string(json['modified']),
      faceRegistered: _readBool(json['face_registered']),
      faceEmbeddings: _string(json['face_embeddings']),
      faceUpdatedOn: DateTime.tryParse('${json['face_updated_on'] ?? ''}'),
      faceModelVersion: _string(json['face_model_version']),
      faceQualityScore: _toDouble(json['face_quality_score']),
      faceEmbeddingCount: _toInt(json['face_embedding_count']),
    );
  }

  factory Employee.fromStoredJson(String source) {
    return Employee.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'employee_name': employeeName,
      'user_id': userId,
      'company_email': companyEmail,
      'personal_email': personalEmail,
      'prefered_email': preferredEmail,
      'designation': designation,
      'department': department,
      'company': company,
      'default_shift': defaultShift,
      'active_shift': activeShift,
      'branch': branch,
      'holiday_list': holidayList,
      'status': status,
      'is_active': isActive,
      'image': image,
      'cell_number': cellNumber,
      'modified': modified,
      'face_registered': faceRegistered,
      'face_embeddings': faceEmbeddings,
      'face_updated_on': faceUpdatedOn?.toIso8601String(),
      'face_model_version': faceModelVersion,
      'face_quality_score': faceQualityScore,
      'face_embedding_count': faceEmbeddingCount,
    };
  }

  String get encoded => jsonEncode(toJson());

  String? get resolvedShift {
    final active = activeShift?.trim();
    if (active != null && active.isNotEmpty) return active;
    final fallback = defaultShift?.trim();
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return null;
  }

  bool get hasAssignedShift => resolvedShift != null;

  String get displayShift => resolvedShift ?? 'Shift not assigned';

  String get primaryEmail =>
      companyEmail ??
      personalEmail ??
      preferredEmail ??
      userId ??
      'Not available';

  Employee copyWith({String? activeShift, bool clearActiveShift = false}) {
    return Employee(
      name: name,
      employeeName: employeeName,
      userId: userId,
      companyEmail: companyEmail,
      personalEmail: personalEmail,
      preferredEmail: preferredEmail,
      designation: designation,
      department: department,
      company: company,
      defaultShift: defaultShift,
      activeShift: clearActiveShift ? null : activeShift ?? this.activeShift,
      branch: branch,
      holidayList: holidayList,
      status: status,
      isActive: isActive,
      image: image,
      cellNumber: cellNumber,
      modified: modified,
      faceRegistered: faceRegistered,
      faceEmbeddings: faceEmbeddings,
      faceUpdatedOn: faceUpdatedOn,
      faceModelVersion: faceModelVersion,
      faceQualityScore: faceQualityScore,
      faceEmbeddingCount: faceEmbeddingCount,
    );
  }

  String get initials {
    final words = employeeName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'FA';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }

  static Employee demo(String user) {
    return Employee(
      name: 'DEMO-EMPLOYEE',
      employeeName: user.isEmpty ? 'Demo Employee' : user,
      userId: user,
      designation: 'HRMS User',
      department: 'Demo',
      company: 'Brij Dairy',
      defaultShift: 'General Shift',
      activeShift: 'General Shift',
      status: 'Active',
    );
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

  static bool _readBool(Object? value) {
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

  static bool _readActive(Object? value, String? status) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    if (value != null) {
      final text = '$value'.trim().toLowerCase();
      if (text == '1' || text == 'true') return true;
      if (text == '0' || text == 'false') return false;
    }
    return status == null || status.trim().toLowerCase() == 'active';
  }
}
