import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../core/config/app_config.dart';

class FaceValidationResult {
  const FaceValidationResult({
    required this.isValid,
    required this.detectedFaceCount,
    required this.faceQualityScore,
    this.face,
    this.failureReason,
  });

  final bool isValid;
  final int detectedFaceCount;
  final double faceQualityScore;
  final Face? face;
  final String? failureReason;

  Rect? get faceBoundingBox => face?.boundingBox;
}

class FaceDetectionService {
  const FaceDetectionService();

  FaceValidationResult validateCameraFaces({
    required CameraImage image,
    required List<Face> faces,
    bool requireCentered = true,
  }) {
    if (faces.isEmpty) {
      return _invalid(faces.length, 'No face detected.');
    }
    if (faces.length > 1) {
      return _invalid(faces.length, 'Multiple faces detected.');
    }

    final face = faces.single;
    final rect = face.boundingBox;
    if (rect.left < image.width * 0.02 ||
        rect.top < image.height * 0.02 ||
        rect.right > image.width * 0.98 ||
        rect.bottom > image.height * 0.98) {
      return _invalid(faces.length, 'Full face must be visible.');
    }

    final minFaceSide = math.min(rect.width, rect.height);
    final minImageSide = math.min(image.width, image.height);
    if (minFaceSide < minImageSide * 0.18) {
      return _invalid(faces.length, 'Face too small. Move closer.');
    }
    if (minFaceSide > minImageSide * 0.72) {
      return _invalid(faces.length, 'Move slightly back.');
    }

    final yaw = face.headEulerAngleY ?? 0;
    final roll = face.headEulerAngleZ ?? 0;
    final pitch = face.headEulerAngleX ?? 0;
    if (yaw.abs() > AppConfig.maxFaceYawDegrees ||
        roll.abs() > AppConfig.maxFaceRollDegrees ||
        pitch.abs() > AppConfig.maxFacePitchDegrees) {
      return _invalid(faces.length, 'Keep your face straight.');
    }

    if (requireCentered) {
      final center = rect.center;
      final dx = ((center.dx - image.width / 2).abs() / image.width);
      final dy = ((center.dy - image.height / 2).abs() / image.height);
      if (dx > 0.32 || dy > 0.34) {
        return _invalid(faces.length, 'Keep your face centered.');
      }
    }

    final quality = estimateFaceQuality(image, rect);
    if (quality < 0.34) {
      return FaceValidationResult(
        isValid: false,
        detectedFaceCount: faces.length,
        faceQualityScore: quality,
        face: face,
        failureReason: 'Face image is too dark or blurry.',
      );
    }

    return FaceValidationResult(
      isValid: true,
      detectedFaceCount: faces.length,
      faceQualityScore: quality,
      face: face,
    );
  }

  double estimateFaceQuality(CameraImage image, Rect faceRect) {
    if (image.planes.isEmpty) return 0;
    final plane = image.planes.first;
    final bytes = plane.bytes;
    if (bytes.isEmpty) return 0;

    final rect = _expandedFaceRect(faceRect, image.width, image.height);
    final stepX = math.max(1, rect.width ~/ 18);
    final stepY = math.max(1, rect.height ~/ 18);
    final values = <int>[];
    for (var y = rect.top.round(); y < rect.bottom; y += stepY) {
      for (var x = rect.left.round(); x < rect.right; x += stepX) {
        values.add(
          _luminanceAt(
            bytes,
            plane.bytesPerRow,
            image.width,
            image.height,
            x,
            y,
          ),
        );
      }
    }
    if (values.isEmpty) return 0;

    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.fold<double>(
          0,
          (sum, value) => sum + math.pow(value - mean, 2),
        ) /
        values.length;
    final brightnessScore = (1 - ((mean - 132).abs() / 132)).clamp(0.0, 1.0);
    final contrastScore = (math.sqrt(variance) / 52).clamp(0.0, 1.0);
    return ((brightnessScore * 0.45) + (contrastScore * 0.55)).clamp(0.0, 1.0);
  }

  FaceValidationResult _invalid(int count, String reason) {
    return FaceValidationResult(
      isValid: false,
      detectedFaceCount: count,
      faceQualityScore: 0,
      failureReason: reason,
    );
  }

  Rect _expandedFaceRect(Rect rect, int imageWidth, int imageHeight) {
    final padding = math.max(rect.width, rect.height) * 0.18;
    final left = (rect.left - padding).clamp(0.0, imageWidth - 1.0);
    final top = (rect.top - padding).clamp(0.0, imageHeight - 1.0);
    final right = (rect.right + padding).clamp(
      left + 1.0,
      imageWidth.toDouble(),
    );
    final bottom = (rect.bottom + padding).clamp(
      top + 1.0,
      imageHeight.toDouble(),
    );
    return Rect.fromLTRB(left, top, right, bottom);
  }

  int _luminanceAt(
    Uint8List bytes,
    int bytesPerRow,
    int width,
    int height,
    int x,
    int y,
  ) {
    final safeX = x.clamp(0, width - 1);
    final safeY = y.clamp(0, height - 1);
    final index = safeY * bytesPerRow + safeX;
    if (index < 0 || index >= bytes.length) return 128;
    return bytes[index];
  }
}
