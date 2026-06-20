class FaceRegistrationAdmin {
  const FaceRegistrationAdmin({
    required this.isAdmin,
    required this.user,
    required this.fullName,
    required this.roles,
  });

  final bool isAdmin;
  final String user;
  final String fullName;
  final List<String> roles;

  factory FaceRegistrationAdmin.fromJson(Map<String, dynamic> json) {
    final roles = json['roles'];
    return FaceRegistrationAdmin(
      isAdmin: _bool(json['is_admin']),
      user: '${json['user'] ?? ''}',
      fullName: '${json['full_name'] ?? ''}',
      roles: roles is List ? roles.map((role) => '$role').toList() : const [],
    );
  }

  static bool _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value == 1;
    final text = '$value'.trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }
}
