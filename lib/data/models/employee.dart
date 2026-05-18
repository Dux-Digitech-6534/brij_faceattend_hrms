import 'dart:convert';

class Employee {
  const Employee({
    required this.name,
    required this.employeeName,
    this.userId,
    this.designation,
    this.department,
    this.company,
    this.defaultShift,
    this.branch,
    this.holidayList,
    this.image,
    this.cellNumber,
  });

  final String name;
  final String employeeName;
  final String? userId;
  final String? designation;
  final String? department;
  final String? company;
  final String? defaultShift;
  final String? branch;
  final String? holidayList;
  final String? image;
  final String? cellNumber;

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      name: '${json['name'] ?? json['employee'] ?? ''}',
      employeeName:
          '${json['employee_name'] ?? json['employee'] ?? json['name'] ?? 'Employee'}',
      userId: json['user_id'] as String?,
      designation: json['designation'] as String?,
      department: json['department'] as String?,
      company: json['company'] as String?,
      defaultShift: (json['default_shift'] ?? json['shift']) as String?,
      branch: json['branch'] as String?,
      holidayList: json['holiday_list'] as String?,
      image: json['image'] as String?,
      cellNumber: json['cell_number'] as String?,
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
      'designation': designation,
      'department': department,
      'company': company,
      'default_shift': defaultShift,
      'branch': branch,
      'holiday_list': holidayList,
      'image': image,
      'cell_number': cellNumber,
    };
  }

  String get encoded => jsonEncode(toJson());

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
      company: 'Jew Online',
      defaultShift: 'General Shift',
    );
  }
}
