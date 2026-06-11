import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../core/config/app_config.dart';
import '../../services/face_recognition_service.dart';
import '../models/face_match_result.dart';

class FaceEmbeddingService {
  FaceEmbeddingService({FaceRecognitionService? recognitionService})
    : _recognitionService = recognitionService ?? FaceRecognitionService();

  final FaceRecognitionService _recognitionService;

  Future<List<double>> createEmbedding({
    required CameraImage image,
    required Face face,
    double faceQualityScore = 0,
  }) async {
    final result = await _recognitionService.createEmbedding(
      image: image,
      face: face,
      faceQualityScore: faceQualityScore,
    );
    return result.embedding;
  }

  List<double> averageEmbeddings(List<List<double>> samples) {
    return _recognitionService.averageEmbeddings(samples);
  }

  FaceMatchResult compare({
    required List<double> storedEmbedding,
    required List<double> liveEmbedding,
    double threshold = AppConfig.faceCosineThreshold,
  }) {
    final similarity = cosineSimilarity(storedEmbedding, liveEmbedding);
    final distance = euclideanDistance(storedEmbedding, liveEmbedding);
    return FaceMatchResult(
      matched: similarity >= threshold,
      cosineSimilarity: similarity,
      euclideanDistance: distance,
      threshold: threshold,
    );
  }

  double cosineSimilarity(List<double> a, List<double> b) {
    return _recognitionService.cosineSimilarity(a, b);
  }

  double euclideanDistance(List<double> a, List<double> b) {
    return _recognitionService.euclideanDistance(a, b);
  }
}
