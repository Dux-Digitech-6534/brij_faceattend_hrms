import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_scope.dart';
import 'data/api/api_client.dart';
import 'data/repositories/attendance_repository.dart';
import 'data/services/face_embedding_service.dart';
import 'data/services/face_profile_service.dart';
import 'data/services/location_service.dart';
import 'data/services/session_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sessionStore = SessionStore();
  final apiClient = ApiClient(sessionStore);
  const faceEmbeddingService = FaceEmbeddingService();
  final faceProfileService = FaceProfileService(
    apiClient,
    faceEmbeddingService,
  );
  final repository = AttendanceRepository(apiClient);
  final locationService = LocationService();

  runApp(
    AppScope(
      apiClient: apiClient,
      sessionStore: sessionStore,
      repository: repository,
      locationService: locationService,
      faceEmbeddingService: faceEmbeddingService,
      faceProfileService: faceProfileService,
      child: const FaceAttendApp(),
    ),
  );
}
