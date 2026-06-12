import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/config/app_config.dart';
import '../models/employee_face_data.dart';

class FaceEmbeddingDebugInfo {
  const FaceEmbeddingDebugInfo({
    required this.modelInputShape,
    required this.embeddingLength,
    required this.faceBoundingBox,
    required this.faceQualityScore,
    required this.sourceImageSize,
    required this.processedImageSize,
    required this.cameraRotation,
    required this.cropRect,
  });

  final List<int> modelInputShape;
  final int embeddingLength;
  final Rect faceBoundingBox;
  final double faceQualityScore;
  final Size sourceImageSize;
  final Size processedImageSize;
  final int cameraRotation;
  final Rect cropRect;
}

class FaceEmbeddingResult {
  const FaceEmbeddingResult({required this.embedding, required this.debugInfo});

  final List<double> embedding;
  final FaceEmbeddingDebugInfo debugInfo;
}

class FaceRecognitionService {
  FaceRecognitionService();

  Interpreter? _interpreter;
  List<int> _inputShape = const [];
  List<int> _outputShape = const [];
  TensorType? _inputType;
  int _inputWidth = 112;
  int _inputHeight = 112;
  bool _channelLast = true;

  Future<void> initialize() => _ensureModelLoaded();

  Future<FaceEmbeddingResult> createEmbedding({
    required CameraImage image,
    required Face face,
    CameraDescription? camera,
    double faceQualityScore = 0,
  }) async {
    await _ensureModelLoaded();
    final rawSource = _cameraImageToRgbImage(image);
    final preparedSource = _imageMatchingFaceCoordinates(
      source: rawSource,
      face: face,
      camera: camera,
    );
    final cropResult = _cropAlignedFace(preparedSource.image, face);
    final resized = img.copyResize(
      cropResult.image,
      width: _inputWidth,
      height: _inputHeight,
      interpolation: img.Interpolation.linear,
    );
    final input = _buildInputTensor(resized);
    final output = _allocateTensor(_outputShape);
    _interpreter!.run(input, output);
    final embedding = EmployeeFaceData.l2Normalize(_flatten(output));
    debugPrint(
      'FaceRecognition modelInputShape=$_inputShape '
      'embeddingLength=${embedding.length} faceBoundingBox=${face.boundingBox} '
      'faceQualityScore=${faceQualityScore.toStringAsFixed(3)} '
      'rawImage=${rawSource.width}x${rawSource.height} '
      'processedImage=${preparedSource.image.width}x${preparedSource.image.height} '
      'rotation=${preparedSource.rotationApplied} '
      'cropRect=${cropResult.rect} '
      'modelVersion=${AppConfig.faceModelVersion}',
    );
    return FaceEmbeddingResult(
      embedding: embedding,
      debugInfo: FaceEmbeddingDebugInfo(
        modelInputShape: _inputShape,
        embeddingLength: embedding.length,
        faceBoundingBox: face.boundingBox,
        faceQualityScore: faceQualityScore,
        sourceImageSize: Size(
          rawSource.width.toDouble(),
          rawSource.height.toDouble(),
        ),
        processedImageSize: Size(
          preparedSource.image.width.toDouble(),
          preparedSource.image.height.toDouble(),
        ),
        cameraRotation: preparedSource.rotationApplied,
        cropRect: cropResult.rect,
      ),
    );
  }

  List<double> averageEmbeddings(List<List<double>> samples) {
    return EmployeeFaceData.averageEmbeddings(samples);
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

  Future<void> _ensureModelLoaded() async {
    if (_interpreter != null) return;
    debugPrint(
      'FaceSDK fallback init start model=${AppConfig.faceModelAssetPath}',
    );
    final options = InterpreterOptions()..threads = 2;
    final Interpreter interpreter;
    try {
      interpreter = await Interpreter.fromAsset(
        AppConfig.faceModelAssetPath,
        options: options,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'FaceSDK fallback init failed model=${AppConfig.faceModelAssetPath} '
        'error=$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
    _interpreter = interpreter;
    _inputShape = interpreter.getInputTensor(0).shape;
    _outputShape = interpreter.getOutputTensor(0).shape;
    _inputType = interpreter.getInputTensor(0).type;

    final shape = _inputShape;
    if (shape.length != 4) {
      throw StateError('Unsupported face model input shape: $shape');
    }
    _channelLast = shape[3] == 3;
    if (_channelLast) {
      _inputHeight = shape[1];
      _inputWidth = shape[2];
    } else {
      _inputHeight = shape[2];
      _inputWidth = shape[3];
    }
    debugPrint(
      'FaceSDK fallback init success model=${AppConfig.faceModelAssetPath} '
      'modelInputShape=$_inputShape outputShape=$_outputShape inputType=$_inputType',
    );
  }

  Object _buildInputTensor(img.Image image) {
    if (_channelLast) {
      return List.generate(
        1,
        (_) => List.generate(
          _inputHeight,
          (y) => List.generate(
            _inputWidth,
            (x) => _normalizedPixel(image.getPixel(x, y)),
            growable: false,
          ),
          growable: false,
        ),
        growable: false,
      );
    }

    return List.generate(
      1,
      (_) => List.generate(
        3,
        (channel) => List.generate(
          _inputHeight,
          (y) => List.generate(
            _inputWidth,
            (x) => _normalizedPixel(image.getPixel(x, y))[channel],
            growable: false,
          ),
          growable: false,
        ),
        growable: false,
      ),
      growable: false,
    );
  }

  List<num> _normalizedPixel(img.Pixel pixel) {
    final r = pixel.r.toDouble();
    final g = pixel.g.toDouble();
    final b = pixel.b.toDouble();
    if (_inputType == TensorType.uint8) {
      return [r.round(), g.round(), b.round()];
    }
    return [(r - 127.5) / 127.5, (g - 127.5) / 127.5, (b - 127.5) / 127.5];
  }

  Object _allocateTensor(List<int> shape) {
    if (shape.isEmpty) return 0.0;
    Object build(int depth) {
      final length = shape[depth];
      if (depth == shape.length - 1) {
        return List<double>.filled(length, 0);
      }
      return List.generate(length, (_) => build(depth + 1), growable: false);
    }

    return build(0);
  }

  List<double> _flatten(Object source) {
    final values = <double>[];
    void visit(Object? value) {
      if (value is List) {
        for (final item in value) {
          visit(item);
        }
      } else if (value is num) {
        values.add(value.toDouble());
      }
    }

    visit(source);
    return values;
  }

  _PreparedFaceSource _imageMatchingFaceCoordinates({
    required img.Image source,
    required Face face,
    CameraDescription? camera,
  }) {
    final rotation = ((camera?.sensorOrientation ?? 0) % 360 + 360) % 360;
    final rawSize = Size(source.width.toDouble(), source.height.toDouble());
    final rotatedSize = _rotatedSize(rawSize, rotation);
    final rect = face.boundingBox;
    final fitsRaw = _fitsInFrame(rect, rawSize);
    final fitsRotated = rotation != 0 && _fitsInFrame(rect, rotatedSize);

    if (!fitsRaw && fitsRotated) {
      return _PreparedFaceSource(
        image: img.copyRotate(source, angle: rotation),
        rotationApplied: rotation,
      );
    }

    return _PreparedFaceSource(image: source, rotationApplied: 0);
  }

  _FaceCropResult _cropAlignedFace(img.Image source, Face face) {
    final rect = _expandedFaceRect(
      face.boundingBox,
      source.width,
      source.height,
    );
    var crop = img.copyCrop(
      source,
      x: rect.left.round(),
      y: rect.top.round(),
      width: rect.width.round(),
      height: rect.height.round(),
    );

    final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
    if (leftEye != null && rightEye != null) {
      final angle = math.atan2(
        rightEye.y.toDouble() - leftEye.y.toDouble(),
        rightEye.x.toDouble() - leftEye.x.toDouble(),
      );
      if (angle.abs() > 0.05) {
        crop = img.copyRotate(crop, angle: -angle * 180 / math.pi);
      }
    }
    return _FaceCropResult(image: crop, rect: rect);
  }

  Rect _expandedFaceRect(Rect rect, int imageWidth, int imageHeight) {
    final side = math.max(rect.width, rect.height);
    final center = rect.center;
    final paddedSide = side * 1.34;
    final left = (center.dx - paddedSide / 2).clamp(0.0, imageWidth - 1.0);
    final top = (center.dy - paddedSide / 2).clamp(0.0, imageHeight - 1.0);
    final right = (center.dx + paddedSide / 2).clamp(
      left + 1.0,
      imageWidth.toDouble(),
    );
    final bottom = (center.dy + paddedSide / 2).clamp(
      top + 1.0,
      imageHeight.toDouble(),
    );
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Size _rotatedSize(Size size, int rotation) {
    if (rotation % 180 == 90) return Size(size.height, size.width);
    return size;
  }

  bool _fitsInFrame(Rect rect, Size size) {
    final slackX = size.width * 0.12;
    final slackY = size.height * 0.14;
    return rect.left >= -slackX &&
        rect.top >= -slackY &&
        rect.right <= size.width + slackX &&
        rect.bottom <= size.height + slackY;
  }

  img.Image _cameraImageToRgbImage(CameraImage image) {
    if (image.format.group == ImageFormatGroup.bgra8888) {
      return _bgraToImage(image);
    }
    if (image.planes.length == 1) {
      return _nv21ToImage(image);
    }
    return _yuv420ToImage(image);
  }

  img.Image _bgraToImage(CameraImage image) {
    final plane = image.planes.first;
    final output = img.Image(width: image.width, height: image.height);
    final stride = plane.bytesPerPixel ?? 4;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final index = y * plane.bytesPerRow + x * stride;
        if (index + 2 >= plane.bytes.length) continue;
        output.setPixelRgb(
          x,
          y,
          plane.bytes[index + 2],
          plane.bytes[index + 1],
          plane.bytes[index],
        );
      }
    }
    return output;
  }

  img.Image _nv21ToImage(CameraImage image) {
    final bytes = image.planes.first.bytes;
    final width = image.width;
    final height = image.height;
    final frameSize = width * height;
    final output = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final yIndex = y * width + x;
        final uvIndex = frameSize + (y >> 1) * width + (x & ~1);
        final yy = bytes[yIndex].toDouble();
        final v = uvIndex < bytes.length ? bytes[uvIndex].toDouble() - 128 : 0;
        final u = uvIndex + 1 < bytes.length
            ? bytes[uvIndex + 1].toDouble() - 128
            : 0;
        output.setPixelRgb(
          x,
          y,
          _clip(yy + 1.402 * v),
          _clip(yy - 0.344136 * u - 0.714136 * v),
          _clip(yy + 1.772 * u),
        );
      }
    }
    return output;
  }

  img.Image _yuv420ToImage(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final output = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final yValue = yPlane.bytes[y * yPlane.bytesPerRow + x].toDouble();
        final uvX = x >> 1;
        final uvY = y >> 1;
        final uIndex =
            uvY * uPlane.bytesPerRow + uvX * (uPlane.bytesPerPixel ?? 1);
        final vIndex =
            uvY * vPlane.bytesPerRow + uvX * (vPlane.bytesPerPixel ?? 1);
        final u = uPlane.bytes[uIndex].toDouble() - 128;
        final v = vPlane.bytes[vIndex].toDouble() - 128;
        output.setPixelRgb(
          x,
          y,
          _clip(yValue + 1.402 * v),
          _clip(yValue - 0.344136 * u - 0.714136 * v),
          _clip(yValue + 1.772 * u),
        );
      }
    }
    return output;
  }

  int _clip(double value) => value.round().clamp(0, 255);
}

class _PreparedFaceSource {
  const _PreparedFaceSource({
    required this.image,
    required this.rotationApplied,
  });

  final img.Image image;
  final int rotationApplied;
}

class _FaceCropResult {
  const _FaceCropResult({required this.image, required this.rect});

  final img.Image image;
  final Rect rect;
}
