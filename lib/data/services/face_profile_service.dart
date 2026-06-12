import '../../core/config/app_config.dart';
import '../../models/employee_face_data.dart';
import '../../services/employee_face_storage_service.dart';
import '../api/api_client.dart';
import '../models/employee.dart';
import '../models/face_match_result.dart';
import '../models/face_profile.dart';
import 'face_embedding_service.dart';

class FaceProfileService {
  const FaceProfileService(
    this._apiClient,
    this._embeddingService,
    this._storageService,
  );

  final ApiClient _apiClient;
  final FaceEmbeddingService _embeddingService;
  final EmployeeFaceStorageService _storageService;

  Future<FaceProfile?> getFaceProfile(String employeeId) async {
    final local = await _storageService.read(employeeId);
    final profile = await _apiClient.getFaceProfile(employeeId);
    if (profile != null && profile.hasEmbedding) {
      return profile.copyWith(
        kbyTemplatesBase64: local?.kbyTemplatesBase64 ?? const [],
      );
    }

    if (local == null || !local.hasEmbedding) return profile;
    return FaceProfile(
      name: 'local-${local.employeeId}',
      employee: local.employeeId,
      employeeName: local.employeeName,
      userId: '',
      faceEmbedding: local.averageEmbedding,
      embeddings: local.embeddings,
      kbyTemplatesBase64: local.kbyTemplatesBase64,
      modelVersion: local.modelVersion,
      faceQualityScore: local.faceQualityScore,
      faceRegistered: local.faceRegistered,
      sampleCount: local.embeddingCount,
      isActive: true,
      registeredOn: local.updatedAt,
      lastUpdatedOn: local.updatedAt,
    );
  }

  Future<bool> hasFaceProfile(String employeeId) async {
    final profile = await getFaceProfile(employeeId);
    return profile != null && profile.hasEmbedding;
  }

  Future<FaceProfile> saveFaceProfile({
    required Employee employee,
    required List<double> embedding,
    List<List<double>> embeddings = const [],
    List<String> kbyTemplatesBase64 = const [],
    double qualityScore = 0,
    required int sampleCount,
    String deviceId = AppConfig.appDeviceId,
  }) async {
    final data = EmployeeFaceData(
      employeeId: employee.name,
      employeeName: employee.employeeName,
      embeddings: embeddings.isEmpty ? [embedding] : embeddings,
      averageEmbedding: embedding,
      kbyTemplatesBase64: kbyTemplatesBase64,
      modelVersion: AppConfig.faceModelVersion,
      engineName: AppConfig.faceEngineName,
      embeddingDimension: embedding.length,
      thresholdVersion: AppConfig.faceThresholdVersion,
      faceRegistered: embedding.isNotEmpty,
      faceQualityScore: qualityScore,
      updatedAt: DateTime.now(),
    );
    await _storageService.save(data);
    return _apiClient.saveFaceProfile(
      employee: employee,
      embedding: embedding,
      embeddings: data.embeddings,
      modelVersion: AppConfig.faceModelVersion,
      qualityScore: qualityScore,
      sampleCount: sampleCount,
      deviceId: deviceId,
    );
  }

  Future<FaceProfile> updateFaceProfile({
    required String profileName,
    required Employee employee,
    required List<double> embedding,
    List<List<double>> embeddings = const [],
    List<String> kbyTemplatesBase64 = const [],
    double qualityScore = 0,
    required int sampleCount,
    String deviceId = AppConfig.appDeviceId,
  }) async {
    await _storageService.save(
      EmployeeFaceData(
        employeeId: employee.name,
        employeeName: employee.employeeName,
        embeddings: embeddings.isEmpty ? [embedding] : embeddings,
        averageEmbedding: embedding,
        kbyTemplatesBase64: kbyTemplatesBase64,
        modelVersion: AppConfig.faceModelVersion,
        engineName: AppConfig.faceEngineName,
        embeddingDimension: embedding.length,
        thresholdVersion: AppConfig.faceThresholdVersion,
        faceRegistered: embedding.isNotEmpty,
        faceQualityScore: qualityScore,
        updatedAt: DateTime.now(),
      ),
    );
    return _apiClient.updateFaceProfile(
      profileName: profileName,
      employee: employee,
      embedding: embedding,
      embeddings: embeddings,
      modelVersion: AppConfig.faceModelVersion,
      qualityScore: qualityScore,
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
