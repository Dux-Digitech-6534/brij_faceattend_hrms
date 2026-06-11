import 'package:flutter/widgets.dart';

import '../data/api/api_client.dart';
import '../data/repositories/attendance_repository.dart';
import '../data/services/face_embedding_service.dart';
import '../data/services/face_profile_service.dart';
import '../data/services/location_service.dart';
import '../data/services/session_store.dart';
import '../services/employee_face_storage_service.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    required this.apiClient,
    required this.sessionStore,
    required this.repository,
    required this.locationService,
    required this.faceEmbeddingService,
    required this.faceProfileService,
    required this.employeeFaceStorageService,
    required super.child,
    super.key,
  });

  final ApiClient apiClient;
  final SessionStore sessionStore;
  final AttendanceRepository repository;
  final LocationService locationService;
  final FaceEmbeddingService faceEmbeddingService;
  final FaceProfileService faceProfileService;
  final EmployeeFaceStorageService employeeFaceStorageService;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope was not found above this context.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    return apiClient != oldWidget.apiClient ||
        sessionStore != oldWidget.sessionStore ||
        repository != oldWidget.repository ||
        locationService != oldWidget.locationService ||
        faceEmbeddingService != oldWidget.faceEmbeddingService ||
        faceProfileService != oldWidget.faceProfileService ||
        employeeFaceStorageService != oldWidget.employeeFaceStorageService;
  }
}
