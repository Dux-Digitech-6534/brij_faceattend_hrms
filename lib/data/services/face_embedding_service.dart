import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../core/config/app_config.dart';
import '../models/face_match_result.dart';

class FaceEmbeddingService {
  const FaceEmbeddingService();

  static const embeddingLength = 128;
  static const _gridSize = 8;

  // TODO: Replace this demo descriptor with MobileFaceNet/FaceNet TFLite
  // inference when a vetted .tflite model is added under app assets.

  Future<List<double>> createEmbedding({
    required CameraImage image,
    required Face face,
  }) async {
    final luminanceGrid = _sampleFaceGrid(image, face.boundingBox);
    final gradients = _gradientFeatures(luminanceGrid);
    final vector = <double>[...luminanceGrid, ...gradients];
    return _l2Normalize(vector);
  }

  List<double> averageEmbeddings(List<List<double>> samples) {
    if (samples.isEmpty) return const [];
    final length = samples.first.length;
    final values = List<double>.filled(length, 0);
    for (final sample in samples) {
      for (var i = 0; i < math.min(length, sample.length); i++) {
        values[i] += sample[i];
      }
    }
    for (var i = 0; i < values.length; i++) {
      values[i] = values[i] / samples.length;
    }
    return _l2Normalize(values);
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
    final length = math.min(a.length, b.length);
    if (length == 0) return 0;
    var dot = 0.0;
    var magA = 0.0;
    var magB = 0.0;
    for (var i = 0; i < length; i++) {
      dot += a[i] * b[i];
      magA += a[i] * a[i];
      magB += b[i] * b[i];
    }
    if (magA == 0 || magB == 0) return 0;
    return dot / (math.sqrt(magA) * math.sqrt(magB));
  }

  double euclideanDistance(List<double> a, List<double> b) {
    final length = math.min(a.length, b.length);
    if (length == 0) return double.infinity;
    var sum = 0.0;
    for (var i = 0; i < length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return math.sqrt(sum);
  }

  List<double> _sampleFaceGrid(CameraImage image, Rect faceRect) {
    final rect = _expandedFaceRect(faceRect, image.width, image.height);
    final values = <double>[];
    for (var gy = 0; gy < _gridSize; gy++) {
      for (var gx = 0; gx < _gridSize; gx++) {
        final x = rect.left + rect.width * ((gx + 0.5) / _gridSize);
        final y = rect.top + rect.height * ((gy + 0.5) / _gridSize);
        values.add(_luminanceAt(image, x.round(), y.round()));
      }
    }

    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values
            .map((value) {
              final diff = value - mean;
              return diff * diff;
            })
            .reduce((a, b) => a + b) /
        values.length;
    final stdDev = math.sqrt(variance).clamp(0.08, 1.0);
    return values
        .map((value) => ((value - mean) / stdDev).clamp(-2.0, 2.0) / 2)
        .toList();
  }

  Rect _expandedFaceRect(Rect rect, int imageWidth, int imageHeight) {
    final horizontalPadding = rect.width * 0.14;
    final verticalPadding = rect.height * 0.18;
    final left = (rect.left - horizontalPadding).clamp(0.0, imageWidth - 1.0);
    final top = (rect.top - verticalPadding).clamp(0.0, imageHeight - 1.0);
    final right = (rect.right + horizontalPadding).clamp(
      left + 1.0,
      imageWidth.toDouble(),
    );
    final bottom = (rect.bottom + verticalPadding).clamp(
      top + 1.0,
      imageHeight.toDouble(),
    );
    return Rect.fromLTRB(left, top, right, bottom);
  }

  double _luminanceAt(CameraImage image, int x, int y) {
    if (image.planes.isEmpty) return 0.5;
    final plane = image.planes.first;
    final pixelStride = plane.bytesPerPixel ?? 1;
    final safeX = x.clamp(0, image.width - 1);
    final safeY = y.clamp(0, image.height - 1);
    final index = safeY * plane.bytesPerRow + safeX * pixelStride;
    if (index < 0 || index >= plane.bytes.length) return 0.5;

    if (pixelStride >= 4 && index + 2 < plane.bytes.length) {
      final b = plane.bytes[index].toDouble();
      final g = plane.bytes[index + 1].toDouble();
      final r = plane.bytes[index + 2].toDouble();
      return ((0.299 * r) + (0.587 * g) + (0.114 * b)) / 255;
    }

    return plane.bytes[index] / 255;
  }

  List<double> _gradientFeatures(List<double> values) {
    final gradients = <double>[];
    for (var gy = 0; gy < _gridSize; gy++) {
      for (var gx = 0; gx < _gridSize; gx++) {
        final index = gy * _gridSize + gx;
        final center = values[index];
        final right = values[gy * _gridSize + math.min(_gridSize - 1, gx + 1)];
        final down = values[math.min(_gridSize - 1, gy + 1) * _gridSize + gx];
        gradients.add(((right - center) + (down - center)).clamp(-1.0, 1.0));
      }
    }
    return gradients;
  }

  List<double> _l2Normalize(List<double> values) {
    if (values.isEmpty) return const [];
    final padded = List<double>.filled(embeddingLength, 0);
    for (var i = 0; i < math.min(values.length, embeddingLength); i++) {
      padded[i] = values[i];
    }
    final magnitude = math.sqrt(
      padded.fold<double>(0, (sum, value) => sum + value * value),
    );
    if (magnitude == 0) return padded;
    return padded.map((value) => value / magnitude).toList(growable: false);
  }
}
