import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:facesdk_plugin/facesdk_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/config/app_config.dart';

class KbyFaceTemplateResult {
  const KbyFaceTemplateResult({
    required this.success,
    required this.detectedFaceCount,
    this.templateBase64,
    this.liveness = 0,
    this.yaw = 0,
    this.roll = 0,
    this.pitch = 0,
    this.failureReason,
    this.engineUnavailable = false,
  });

  final bool success;
  final int detectedFaceCount;
  final String? templateBase64;
  final double liveness;
  final double yaw;
  final double roll;
  final double pitch;
  final String? failureReason;
  final bool engineUnavailable;

  bool get hasTemplate => templateBase64 != null && templateBase64!.isNotEmpty;
}

class KbyFaceMatchResult {
  const KbyFaceMatchResult({
    required this.matched,
    required this.similarity,
    required this.threshold,
    this.failureReason,
    this.engineUnavailable = false,
  });

  final bool matched;
  final double similarity;
  final double threshold;
  final String? failureReason;
  final bool engineUnavailable;
}

class KbyFaceEngineStatus {
  const KbyFaceEngineStatus({
    required this.available,
    this.activationCode,
    this.initCode,
    this.failureReason,
  });

  final bool available;
  final int? activationCode;
  final int? initCode;
  final String? failureReason;

  String get selectedEngine =>
      available ? 'KBY FaceSDK' : 'Flutter/TFLite fallback';
}

class KbyFaceRecognitionService {
  KbyFaceRecognitionService({FacesdkPlugin? plugin})
    : _plugin = plugin ?? FacesdkPlugin();

  final FacesdkPlugin _plugin;
  Future<KbyFaceEngineStatus>? _initFuture;
  KbyFaceEngineStatus? _status;

  Future<KbyFaceEngineStatus> initialize() {
    return _initFuture ??= _initialize();
  }

  Future<KbyFaceTemplateResult> extractTemplate({
    required CameraImage image,
    CameraDescription? camera,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const KbyFaceTemplateResult(
        success: false,
        detectedFaceCount: 0,
        failureReason: 'KBY face recognition is available only on mobile.',
      );
    }

    File? tempFile;
    try {
      final status = await initialize();
      if (!status.available) {
        return KbyFaceTemplateResult(
          success: false,
          detectedFaceCount: 0,
          failureReason: status.failureReason,
          engineUnavailable: true,
        );
      }
      tempFile = await _writeFrameAsJpeg(image, camera);
      final faces = await _plugin.extractFaces(tempFile.path);
      final faceList = faces is List ? faces : const [];
      debugPrint(
        'FaceSDK KBY extract detectedFaceCount=${faceList.length} '
        'image=${image.width}x${image.height}',
      );
      if (faceList.isEmpty) {
        return const KbyFaceTemplateResult(
          success: false,
          detectedFaceCount: 0,
          failureReason: 'No face detected.',
        );
      }
      if (faceList.length > 1) {
        return KbyFaceTemplateResult(
          success: false,
          detectedFaceCount: faceList.length,
          failureReason: 'Multiple faces detected.',
        );
      }

      final face = Map<Object?, Object?>.from(faceList.single as Map);
      debugPrint(
        'FaceSDK KBY face box='
        '${face['x1']},${face['y1']},${face['x2']},${face['y2']} '
        'landmarks=n/a',
      );
      final templates = face['templates'];
      if (templates is! Uint8List || templates.isEmpty) {
        return const KbyFaceTemplateResult(
          success: false,
          detectedFaceCount: 1,
          failureReason: 'Face template could not be generated.',
        );
      }

      final liveness = _toDouble(face['liveness']);
      final yaw = _toDouble(face['yaw']);
      final roll = _toDouble(face['roll']);
      final pitch = _toDouble(face['pitch']);
      final failure = _validateKbyQuality(
        liveness: liveness,
        yaw: yaw,
        roll: roll,
        pitch: pitch,
      );
      if (failure != null) {
        debugPrint(
          'FaceSDK KBY quality rejected liveness=${liveness.toStringAsFixed(3)} '
          'yaw=${yaw.toStringAsFixed(2)} roll=${roll.toStringAsFixed(2)} '
          'pitch=${pitch.toStringAsFixed(2)} reason=$failure',
        );
        return KbyFaceTemplateResult(
          success: false,
          detectedFaceCount: 1,
          liveness: liveness,
          yaw: yaw,
          roll: roll,
          pitch: pitch,
          failureReason: failure,
        );
      }

      debugPrint(
        'FaceSDK KBY template success liveness=${liveness.toStringAsFixed(3)} '
        'yaw=${yaw.toStringAsFixed(2)} roll=${roll.toStringAsFixed(2)} '
        'pitch=${pitch.toStringAsFixed(2)} templateBytes=${templates.length}',
      );
      return KbyFaceTemplateResult(
        success: true,
        detectedFaceCount: 1,
        templateBase64: base64Encode(templates),
        liveness: liveness,
        yaw: yaw,
        roll: roll,
        pitch: pitch,
      );
    } catch (error, stackTrace) {
      debugPrint('FaceSDK KBY extract failed error=$error');
      debugPrintStack(stackTrace: stackTrace);
      return KbyFaceTemplateResult(
        success: false,
        detectedFaceCount: 0,
        failureReason: 'KBY face recognition failed: $error',
      );
    } finally {
      try {
        await tempFile?.delete();
      } catch (_) {}
    }
  }

  Future<KbyFaceMatchResult> compareWithRegisteredTemplates({
    required String liveTemplateBase64,
    required List<String> registeredTemplatesBase64,
    double threshold = AppConfig.kbyFaceMatchThreshold,
  }) async {
    if (registeredTemplatesBase64.isEmpty) {
      return KbyFaceMatchResult(
        matched: false,
        similarity: 0,
        threshold: threshold,
        failureReason: 'Registered face template missing. Register again.',
      );
    }

    try {
      final status = await initialize();
      if (!status.available) {
        return KbyFaceMatchResult(
          matched: false,
          similarity: 0,
          threshold: threshold,
          failureReason: status.failureReason,
          engineUnavailable: true,
        );
      }
      final live = base64Decode(liveTemplateBase64);
      var best = 0.0;
      for (final storedBase64 in registeredTemplatesBase64) {
        final stored = base64Decode(storedBase64);
        final score =
            await _plugin.similarityCalculation(
              Uint8List.fromList(live),
              Uint8List.fromList(stored),
            ) ??
            0;
        if (score > best) best = score;
      }
      debugPrint(
        'FaceSDK KBY similarity best=${best.toStringAsFixed(4)} '
        'threshold=${threshold.toStringAsFixed(2)} '
        'registeredTemplates=${registeredTemplatesBase64.length}',
      );
      return KbyFaceMatchResult(
        matched: best >= threshold,
        similarity: best,
        threshold: threshold,
        failureReason: best >= threshold ? null : 'Face not matched.',
      );
    } catch (error, stackTrace) {
      debugPrint('FaceSDK KBY comparison failed error=$error');
      debugPrintStack(stackTrace: stackTrace);
      return KbyFaceMatchResult(
        matched: false,
        similarity: 0,
        threshold: threshold,
        failureReason: 'Face recognition failed. Please try again.',
      );
    }
  }

  Future<KbyFaceEngineStatus> _initialize() async {
    if (_status != null) return _status!;
    if (!Platform.isAndroid && !Platform.isIOS) {
      _status = const KbyFaceEngineStatus(
        available: false,
        failureReason: 'KBY face recognition is available only on mobile.',
      );
      debugPrint(
        'FaceSDK init status selectedEngine=${_status!.selectedEngine} '
        'reason=${_status!.failureReason}',
      );
      return _status!;
    }

    int? activation;
    int? init;
    try {
      debugPrint('FaceSDK KBY init start platform=${Platform.operatingSystem}');
      if (Platform.isAndroid) {
        activation = await _plugin.setActivation(
          'PjnUMBHfBhtT/oa8ySF6mwinqAj2oBls4vSsDmsdrpL/xHwPLtq9Dll/4IIe2KIkXQEh81/21yQhK'
          'AUQOmCvuuNcaZX+DS/EBhinprH+Y+XBzdGz2KWKEZjeDnhoSo8ql1CDDmMiCdRleZ7PbcPv10/dkdI'
          'mwGLFerErQxL/qKIz+8CQqOryw/7RjpNgkbpufY+Nd635HN3dbG4Z+AKdpsl2hB+hl/16O1IhQiGia'
          '4V2+1q9PsFfj6HFST+CQD17kXfsXkoQzMsFwQn4BSuyiiPUdHfJ+EFYMoeF96Jhqfe1CH3af41l0wK'
          'LNqXthBE24m96v06lDFPXkxDOCZCzug==',
        );
        debugPrint('FaceSDK KBY activation code=$activation');
        if (activation != 0) {
          _status = KbyFaceEngineStatus(
            available: false,
            activationCode: activation,
            failureReason: 'KBY activation failed with code $activation.',
          );
          debugPrint(
            'FaceSDK init status selectedEngine=${_status!.selectedEngine} '
            'activationCode=$activation initCode=n/a reason=${_status!.failureReason}',
          );
          return _status!;
        }
      }
      init = await _plugin.init();
      debugPrint('FaceSDK KBY native init code=$init');
      if (init != 0) {
        _status = KbyFaceEngineStatus(
          available: false,
          activationCode: activation,
          initCode: init,
          failureReason: 'KBY native init failed with code $init.',
        );
        debugPrint(
          'FaceSDK init status selectedEngine=${_status!.selectedEngine} '
          'activationCode=${activation ?? 'n/a'} initCode=$init '
          'reason=${_status!.failureReason}',
        );
        return _status!;
      }
      await _plugin.setParam({'check_liveness_level': 0});
      _status = KbyFaceEngineStatus(
        available: true,
        activationCode: activation,
        initCode: init,
      );
      debugPrint(
        'FaceSDK init status selectedEngine=${_status!.selectedEngine} '
        'activationCode=${activation ?? 'n/a'} initCode=$init '
        'licenseStatus=loaded modelStatus=loaded',
      );
      return _status!;
    } catch (error, stackTrace) {
      _status = KbyFaceEngineStatus(
        available: false,
        activationCode: activation,
        initCode: init,
        failureReason: 'KBY initialization exception: $error',
      );
      debugPrint(
        'FaceSDK init status selectedEngine=${_status!.selectedEngine} '
        'activationCode=${activation ?? 'n/a'} initCode=${init ?? 'n/a'} '
        'reason=${_status!.failureReason}',
      );
      debugPrintStack(stackTrace: stackTrace);
      return _status!;
    }
  }

  Future<File> _writeFrameAsJpeg(
    CameraImage image,
    CameraDescription? camera,
  ) async {
    var rgb = _cameraImageToRgbImage(image);
    final rotation = camera?.sensorOrientation ?? 0;
    if (rotation != 0) {
      rgb = img.copyRotate(rgb, angle: rotation);
    }
    final bytes = img.encodeJpg(rgb, quality: 92);
    final file = File(
      '${Directory.systemTemp.path}'
      '${Platform.pathSeparator}faceattend_kby_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    return file.writeAsBytes(bytes, flush: true);
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
        final yy = yIndex < bytes.length ? bytes[yIndex].toDouble() : 0;
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
        final yIndex = y * yPlane.bytesPerRow + x;
        final yValue = yIndex < yPlane.bytes.length
            ? yPlane.bytes[yIndex].toDouble()
            : 0;
        final uvX = x >> 1;
        final uvY = y >> 1;
        final uIndex =
            uvY * uPlane.bytesPerRow + uvX * (uPlane.bytesPerPixel ?? 1);
        final vIndex =
            uvY * vPlane.bytesPerRow + uvX * (vPlane.bytesPerPixel ?? 1);
        final u = uIndex < uPlane.bytes.length
            ? uPlane.bytes[uIndex].toDouble() - 128
            : 0;
        final v = vIndex < vPlane.bytes.length
            ? vPlane.bytes[vIndex].toDouble() - 128
            : 0;
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

  String? _validateKbyQuality({
    required double liveness,
    required double yaw,
    required double roll,
    required double pitch,
  }) {
    if (liveness < AppConfig.kbyFaceLivenessThreshold) {
      return 'Liveness check failed.';
    }
    if (yaw.abs() > AppConfig.maxFaceYawDegrees ||
        roll.abs() > AppConfig.maxFaceRollDegrees ||
        pitch.abs() > AppConfig.maxFacePitchDegrees) {
      return 'Keep your face straight.';
    }
    return null;
  }

  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  int _clip(double value) => value.round().clamp(0, 255);
}
