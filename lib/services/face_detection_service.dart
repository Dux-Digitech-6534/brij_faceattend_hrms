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
    required this.debugInfo,
    this.face,
    this.failureReason,
  });

  final bool isValid;
  final int detectedFaceCount;
  final double faceQualityScore;
  final String debugInfo;
  final Face? face;
  final String? failureReason;

  Rect? get faceBoundingBox => face?.boundingBox;
}

class FaceDetectionService {
  const FaceDetectionService();

  FaceValidationResult validateCameraFaces({
    required CameraImage image,
    required List<Face> faces,
    CameraDescription? camera,
    Size? previewSize,
    bool requireCentered = true,
  }) {
    final rotation = camera?.sensorOrientation ?? 0;
    final rawImageSize = Size(image.width.toDouble(), image.height.toDouble());
    if (faces.isEmpty) {
      return _invalid(
        faces.length,
        'No face detected.',
        _debug(
          imageSize: rawImageSize,
          previewSize: previewSize,
          coordinateSize: _rotatedSize(rawImageSize, rotation),
          rotation: rotation,
          reason: 'no_face',
        ),
      );
    }
    if (faces.length > 1) {
      return _invalid(
        faces.length,
        'Multiple faces detected.',
        _debug(
          imageSize: rawImageSize,
          previewSize: previewSize,
          coordinateSize: _rotatedSize(rawImageSize, rotation),
          rotation: rotation,
          reason: 'multiple_faces',
        ),
      );
    }

    final face = faces.single;
    final rect = face.boundingBox;
    final coordinateSize = _coordinateSizeForFace(rawImageSize, rotation, rect);
    final frame = Offset.zero & coordinateSize;
    final visibleRect = rect.intersect(frame);
    final visibleArea = visibleRect.isEmpty
        ? 0.0
        : visibleRect.width * visibleRect.height;
    final faceArea = rect.width * rect.height;
    final visibleRatio = faceArea <= 0 ? 0.0 : visibleArea / faceArea;
    final landmarks = _landmarkStats(face, coordinateSize);
    final centerDx =
        ((rect.center.dx - coordinateSize.width / 2).abs() /
        coordinateSize.width);
    final centerDy =
        ((rect.center.dy - coordinateSize.height / 2).abs() /
        coordinateSize.height);
    final widthRatio = rect.width / coordinateSize.width;
    final heightRatio = rect.height / coordinateSize.height;
    final minFaceSideRatio = math.min(widthRatio, heightRatio);
    final maxFaceSideRatio = math.max(widthRatio, heightRatio);

    String debug({String? reason, double? quality}) {
      return _debug(
        imageSize: rawImageSize,
        previewSize: previewSize,
        coordinateSize: coordinateSize,
        rotation: rotation,
        rect: rect,
        centerDx: centerDx,
        centerDy: centerDy,
        widthRatio: widthRatio,
        heightRatio: heightRatio,
        visibleRatio: visibleRatio,
        landmarksInside: landmarks.inside,
        landmarksAvailable: landmarks.available,
        quality: quality,
        reason: reason,
      );
    }

    if (visibleRatio < 0.72) {
      return _invalid(
        faces.length,
        'Full face must be visible.',
        debug(reason: 'visible_ratio_low'),
        face: face,
      );
    }
    if (landmarks.available >= 3 && landmarks.inside < 3) {
      return _invalid(
        faces.length,
        'Full face must be visible.',
        debug(reason: 'landmarks_near_edge'),
        face: face,
      );
    }

    if (minFaceSideRatio < 0.16) {
      return _invalid(
        faces.length,
        'Face too small. Move closer.',
        debug(reason: 'face_too_small'),
        face: face,
      );
    }
    if (maxFaceSideRatio > 0.86) {
      return _invalid(
        faces.length,
        'Move slightly back.',
        debug(reason: 'face_too_large'),
        face: face,
      );
    }

    final yaw = face.headEulerAngleY ?? 0;
    final roll = face.headEulerAngleZ ?? 0;
    final pitch = face.headEulerAngleX ?? 0;
    if (yaw.abs() > AppConfig.maxFaceYawDegrees ||
        roll.abs() > AppConfig.maxFaceRollDegrees ||
        pitch.abs() > AppConfig.maxFacePitchDegrees) {
      return _invalid(
        faces.length,
        'Keep your face straight.',
        debug(reason: 'pose_out_of_range'),
        face: face,
      );
    }

    if (requireCentered) {
      if (centerDx > 0.40 || centerDy > 0.44) {
        return _invalid(
          faces.length,
          'Keep your face centered.',
          debug(reason: 'not_centered'),
          face: face,
        );
      }
    }

    final quality = estimateFaceQuality(image, rect);
    if (quality < 0.34) {
      return FaceValidationResult(
        isValid: false,
        detectedFaceCount: faces.length,
        faceQualityScore: quality,
        debugInfo: debug(reason: 'quality_low', quality: quality),
        face: face,
        failureReason: 'Face image is too dark or blurry.',
      );
    }

    return FaceValidationResult(
      isValid: true,
      detectedFaceCount: faces.length,
      faceQualityScore: quality,
      debugInfo: debug(reason: 'valid', quality: quality),
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

  FaceValidationResult _invalid(
    int count,
    String reason,
    String debugInfo, {
    Face? face,
  }) {
    return FaceValidationResult(
      isValid: false,
      detectedFaceCount: count,
      faceQualityScore: 0,
      debugInfo: debugInfo,
      face: face,
      failureReason: reason,
    );
  }

  Size _coordinateSizeForFace(Size imageSize, int rotation, Rect rect) {
    final raw = imageSize;
    final rotated = _rotatedSize(imageSize, rotation);
    if (_fitsInFrame(rect, raw)) return raw;
    if (_fitsInFrame(rect, rotated)) return rotated;
    final maxWidth = math.max(raw.width, rotated.width);
    final maxHeight = math.max(raw.height, rotated.height);
    return Size(maxWidth, maxHeight);
  }

  Size _rotatedSize(Size imageSize, int rotation) {
    final normalized = rotation.abs() % 180;
    if (normalized == 90) return Size(imageSize.height, imageSize.width);
    return imageSize;
  }

  bool _fitsInFrame(Rect rect, Size size) {
    final slackX = size.width * 0.12;
    final slackY = size.height * 0.14;
    return rect.left >= -slackX &&
        rect.top >= -slackY &&
        rect.right <= size.width + slackX &&
        rect.bottom <= size.height + slackY;
  }

  _LandmarkStats _landmarkStats(Face face, Size coordinateSize) {
    final points = [
      face.landmarks[FaceLandmarkType.leftEye]?.position,
      face.landmarks[FaceLandmarkType.rightEye]?.position,
      face.landmarks[FaceLandmarkType.noseBase]?.position,
      face.landmarks[FaceLandmarkType.leftMouth]?.position,
      face.landmarks[FaceLandmarkType.rightMouth]?.position,
      face.landmarks[FaceLandmarkType.bottomMouth]?.position,
    ].whereType<math.Point<int>>();
    var available = 0;
    var inside = 0;
    final marginX = coordinateSize.width * 0.02;
    final marginY = coordinateSize.height * 0.02;
    for (final point in points) {
      available++;
      if (point.x >= marginX &&
          point.y >= marginY &&
          point.x <= coordinateSize.width - marginX &&
          point.y <= coordinateSize.height - marginY) {
        inside++;
      }
    }
    return _LandmarkStats(available: available, inside: inside);
  }

  String _debug({
    required Size imageSize,
    required Size coordinateSize,
    required int rotation,
    Size? previewSize,
    Rect? rect,
    double? centerDx,
    double? centerDy,
    double? widthRatio,
    double? heightRatio,
    double? visibleRatio,
    int? landmarksInside,
    int? landmarksAvailable,
    double? quality,
    String? reason,
  }) {
    return 'image=${imageSize.width.toInt()}x${imageSize.height.toInt()} '
        'preview=${previewSize == null ? 'n/a' : '${previewSize.width.toStringAsFixed(0)}x${previewSize.height.toStringAsFixed(0)}'} '
        'rotation=$rotation '
        'coord=${coordinateSize.width.toInt()}x${coordinateSize.height.toInt()} '
        'box=${rect == null ? 'n/a' : '${rect.left.toStringAsFixed(1)},${rect.top.toStringAsFixed(1)},${rect.right.toStringAsFixed(1)},${rect.bottom.toStringAsFixed(1)}'} '
        'centerDx=${centerDx?.toStringAsFixed(3) ?? 'n/a'} '
        'centerDy=${centerDy?.toStringAsFixed(3) ?? 'n/a'} '
        'widthRatio=${widthRatio?.toStringAsFixed(3) ?? 'n/a'} '
        'heightRatio=${heightRatio?.toStringAsFixed(3) ?? 'n/a'} '
        'visibleRatio=${visibleRatio?.toStringAsFixed(3) ?? 'n/a'} '
        'landmarks=${landmarksInside ?? 0}/${landmarksAvailable ?? 0} '
        'quality=${quality?.toStringAsFixed(3) ?? 'n/a'} '
        'reason=${reason ?? ''}';
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

class _LandmarkStats {
  const _LandmarkStats({required this.available, required this.inside});

  final int available;
  final int inside;
}
