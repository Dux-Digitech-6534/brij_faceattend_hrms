import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../core/config/app_config.dart';
import '../../services/face_recognition_service.dart';
import '../models/face_match_result.dart';

class FaceEmbeddingService {
  FaceEmbeddingService({FaceRecognitionService? recognitionService})
    : _recognitionService = recognitionService ?? FaceRecognitionService();

  final FaceRecognitionService _recognitionService;

  Future<void> initialize() {
    return _recognitionService.initialize();
  }

  Future<List<double>> createEmbedding({
    required CameraImage image,
    required Face face,
    CameraDescription? camera,
    double faceQualityScore = 0,
  }) async {
    final result = await _recognitionService.createEmbedding(
      image: image,
      face: face,
      camera: camera,
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

  FaceMatchResult compareAgainstSamples({
    required List<List<double>> storedEmbeddings,
    required List<double> liveEmbedding,
    double threshold = AppConfig.faceStrongMatchThreshold,
  }) {
    final candidates = storedEmbeddings
        .where((embedding) => embedding.isNotEmpty)
        .toList(growable: false);
    if (liveEmbedding.isEmpty || candidates.isEmpty) {
      return FaceMatchResult(
        matched: false,
        cosineSimilarity: 0,
        euclideanDistance: double.infinity,
        threshold: threshold,
      );
    }

    var bestSimilarity = -1.0;
    var bestDistance = double.infinity;
    for (final stored in candidates) {
      final similarity = cosineSimilarity(stored, liveEmbedding);
      final distance = euclideanDistance(stored, liveEmbedding);
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestDistance = distance;
      }
    }

    return FaceMatchResult(
      matched: bestSimilarity >= threshold,
      cosineSimilarity: bestSimilarity,
      euclideanDistance: bestDistance,
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
