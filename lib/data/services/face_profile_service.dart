import '../../core/config/app_config.dart';
import '../api/api_client.dart';
import '../models/employee.dart';
import '../models/face_match_result.dart';
import '../models/face_profile.dart';
import 'face_embedding_service.dart';

class FaceProfileService {
  const FaceProfileService(this._apiClient, this._embeddingService);

  final ApiClient _apiClient;
  final FaceEmbeddingService _embeddingService;

  Future<FaceProfile?> getFaceProfile(String employeeId) {
    return _apiClient.getFaceProfile(employeeId);
  }

  Future<bool> hasFaceProfile(String employeeId) async {
    final profile = await getFaceProfile(employeeId);
    return profile != null && profile.hasEmbedding;
  }

  Future<FaceProfile> saveFaceProfile({
    required Employee employee,
    required List<double> embedding,
    required int sampleCount,
    String deviceId = AppConfig.appDeviceId,
  }) {
    return _apiClient.saveFaceProfile(
      employee: employee,
      embedding: embedding,
      sampleCount: sampleCount,
      deviceId: deviceId,
    );
  }

  Future<FaceProfile> updateFaceProfile({
    required String profileName,
    required Employee employee,
    required List<double> embedding,
    required int sampleCount,
    String deviceId = AppConfig.appDeviceId,
  }) {
    return _apiClient.updateFaceProfile(
      profileName: profileName,
      employee: employee,
      embedding: embedding,
      sampleCount: sampleCount,
      deviceId: deviceId,
    );
  }

  FaceMatchResult verifyFaceProfile({
    required FaceProfile profile,
    required List<double> liveEmbedding,
    double threshold = AppConfig.faceCosineThreshold,
  }) {
    return _embeddingService.compare(
      storedEmbedding: profile.faceEmbedding,
      liveEmbedding: liveEmbedding,
      threshold: threshold,
    );
  }
}
