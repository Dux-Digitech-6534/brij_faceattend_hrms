import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/app_scope.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/date_formats.dart';
import '../../core/utils/erp_error.dart';
import '../../data/models/employee.dart';
import '../../services/face_detection_service.dart';
import '../../shared/widgets/premium_action_button.dart';
import '../../shared/widgets/premium_card.dart';
import '../../shared/widgets/status_pill.dart';

class FaceAttendanceScreen extends StatefulWidget {
  const FaceAttendanceScreen({
    required this.employee,
    required this.logType,
    super.key,
  });

  final Employee employee;
  final String logType;

  @override
  State<FaceAttendanceScreen> createState() => _FaceAttendanceScreenState();
}

class _FaceAttendanceScreenState extends State<FaceAttendanceScreen>
    with SingleTickerProviderStateMixin {
  late final FaceDetector _faceDetector;
  final FaceDetectionService _faceDetectionService =
      const FaceDetectionService();
  late final AnimationController _scanController;
  CameraController? _cameraController;
  CameraDescription? _camera;
  bool _initializing = true;
  bool _engineInitStarted = false;
  bool _processingFrame = false;
  bool _faceDetected = false;
  bool _faceVerified = false;
  bool _serverVerificationReady = false;
  bool _verificationFailed = false;
  bool _livenessPassed = false;
  bool _submitting = false;
  bool _timedOut = false;
  String? _error;
  String? _failureReason;
  String _livenessMessage = 'Waiting for liveness prompt.';
  DateTime _scanStartedAt = DateTime.now();
  DateTime _istNow = DateFormats.istNow();
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  Position? _lastPosition;
  DateTime? _submittedAt;
  List<double> _liveEmbedding = const [];
  final List<List<double>> _liveEmbeddingSamples = <List<double>>[];
  Timer? _clockTimer;

  bool get _isMarkIn => widget.logType.toUpperCase() == 'IN';
  bool get _hasShift => widget.employee.hasAssignedShift;

  @override
  void initState() {
    super.initState();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: true,
        enableLandmarks: true,
        enableTracking: true,
        minFaceSize: 0.18,
      ),
    );
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _istNow = DateFormats.istNow());
    });
    _initializeCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_engineInitStarted) {
      _engineInitStarted = true;
      debugPrint(
        'FaceAttendance local identity recognition disabled; '
        'ERPNext backend face API is source of truth.',
      );
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    if (_cameraController?.value.isStreamingImages ?? false) {
      _cameraController?.stopImageStream();
    }
    _cameraController?.dispose();
    _faceDetector.close();
    _scanController.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    final oldController = _cameraController;
    if (oldController != null) {
      if (oldController.value.isStreamingImages) {
        await oldController.stopImageStream();
      }
      await oldController.dispose();
      _cameraController = null;
    }

    setState(() {
      _initializing = true;
      _error = null;
      _timedOut = false;
      _faceDetected = false;
      _faceVerified = false;
      _serverVerificationReady = false;
      _verificationFailed = false;
      _submitting = false;
      _livenessPassed = false;
      _livenessMessage = 'Face quality check ready.';
      _failureReason = null;
      _liveEmbedding = const [];
      _liveEmbeddingSamples.clear();
      _scanStartedAt = DateTime.now();
    });

    try {
      final permission = await Permission.camera.request();
      if (!permission.isGranted) {
        throw const ErpError(
          'Camera permission is required for face detection.',
        );
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw const ErpError('No camera was found on this device.');
      }

      _camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        _camera!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      _cameraController = controller;
      await controller.initialize();
      await controller.startImageStream(_processCameraImage);

      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = friendlyErrorMessage(
          error,
          fallback: 'Camera unavailable. Please try again.',
        );
      });
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_processingFrame || _submitting || _faceVerified || _timedOut) return;
    final now = DateTime.now();
    if (now.difference(_scanStartedAt) > AppConfig.faceAttendanceTimeout) {
      await _timeoutScan();
      return;
    }
    if (now.difference(_lastFrameAt) < AppConfig.faceFrameInterval) {
      return;
    }
    _lastFrameAt = now;
    _processingFrame = true;
    final scope = AppScope.of(context);

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;
      final faces = await _faceDetector.processImage(inputImage);
      final validation = _faceDetectionService.validateCameraFaces(
        image: image,
        faces: faces,
        camera: _camera,
        previewSize: _cameraController?.value.previewSize,
      );
      final detected = validation.isValid;
      if (mounted && detected != _faceDetected) {
        setState(() => _faceDetected = detected);
      }
      debugPrint(
        'FaceAttendance detectedFaceCount=${validation.detectedFaceCount} '
        'faceBoundingBox=${validation.faceBoundingBox} '
        'faceQualityScore=${validation.faceQualityScore.toStringAsFixed(3)} '
        'failureReason=${validation.failureReason ?? ''} '
        'debug=${validation.debugInfo}',
      );
      if (_faceVerified) return;
      if (!validation.isValid || validation.face == null) {
        if (mounted) {
          setState(() {
            _serverVerificationReady = false;
            _failureReason = validation.failureReason;
            _verificationFailed = true;
            _liveEmbedding = const [];
            _liveEmbeddingSamples.clear();
          });
        }
        debugPrint(
          'FaceAttendance reject reason=${validation.failureReason ?? 'face_quality_failed'} '
          'employeeId=${widget.employee.name} localIdentityMatchUsed=false '
          'facesCount=${validation.detectedFaceCount} '
          'faceQualityPassed=false attendanceApiCalled=false',
        );
        return;
      }

      final embedding = await scope.faceEmbeddingService.createEmbedding(
        image: image,
        face: validation.face!,
        camera: _camera,
        faceQualityScore: validation.faceQualityScore,
      );
      if (embedding.isEmpty) {
        if (mounted) {
          setState(() {
            _serverVerificationReady = false;
            _failureReason = 'face_embedding_failed';
            _verificationFailed = true;
            _liveEmbedding = const [];
            _liveEmbeddingSamples.clear();
          });
        }
        return;
      }

      _liveEmbeddingSamples.add(embedding);
      if (_liveEmbeddingSamples.length >
          AppConfig.faceRecognitionStableFrames) {
        _liveEmbeddingSamples.removeAt(0);
      }
      final stableEmbedding = scope.faceEmbeddingService.averageEmbeddings(
        _liveEmbeddingSamples,
      );
      final stableFrameCount = _liveEmbeddingSamples.length;
      final readyForBackend =
          stableEmbedding.isNotEmpty &&
          stableFrameCount >= AppConfig.faceRecognitionStableFrames;

      if (mounted) {
        setState(() {
          _livenessPassed = readyForBackend;
          _livenessMessage = readyForBackend
              ? 'Face ready for ERPNext verification.'
              : 'Face quality check ready.';
          _failureReason = null;
          _verificationFailed = false;
          _serverVerificationReady = readyForBackend;
          _liveEmbedding = readyForBackend ? stableEmbedding : const [];
        });
      }
      debugPrint(
        'FaceAttendance faceReadyForBackend=$readyForBackend localIdentityMatchUsed=false '
        'employeeId=${widget.employee.name} detectedFaces=${validation.detectedFaceCount} '
        'faceQualityScore=${validation.faceQualityScore.toStringAsFixed(3)} '
        'stableFrames=$stableFrameCount/${AppConfig.faceRecognitionStableFrames} '
        'embeddingLength=${stableEmbedding.length} '
        'attendanceApiCalled=false',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'FaceAttendance reject reason=recognition_exception error=$error '
        'employeeId=${widget.employee.name} localIdentityMatchUsed=false '
        'attendanceApiCalled=false',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (mounted && _faceDetected) {
        setState(() {
          _faceDetected = false;
        });
      }
    } finally {
      _processingFrame = false;
    }
  }

  String? _preSubmitRejectReason() {
    if (widget.employee.name.trim().isEmpty) return 'Employee not found.';
    if (!_serverVerificationReady || !_faceDetected || !_livenessPassed) {
      return 'Keep your face centered before ERPNext verification.';
    }
    if (_liveEmbedding.isEmpty) {
      return 'Keep your face centered while the app prepares verification.';
    }
    return null;
  }

  Future<void> _timeoutScan() async {
    if (_timedOut) return;
    await _stopImageStream();
    if (!mounted) return;
    setState(() {
      _timedOut = true;
      _verificationFailed = true;
      _failureReason = 'Please face the camera clearly.';
      _error = 'Please face the camera clearly.';
    });
  }

  Future<void> _stopImageStream() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _camera;
    if (camera == null) return null;

    final rotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    final bytes = _planesToBytes(image.planes);
    if (bytes.isEmpty) return null;

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Uint8List _planesToBytes(List<Plane> planes) {
    if (planes.length == 1) return planes.first.bytes;
    final builder = BytesBuilder();
    for (final plane in planes) {
      builder.add(plane.bytes);
    }
    return builder.toBytes();
  }

  Future<void> _submit() async {
    final rejectReason = _preSubmitRejectReason();
    if (rejectReason != null || _submitting) {
      debugPrint(
        'FaceAttendance preSubmitGuard allow=false reason=${rejectReason ?? 'already_submitting'} '
        'employeeId=${widget.employee.name} '
        'faceReadyForBackend=$_serverVerificationReady '
        'localIdentityMatchUsed=false '
        'attendanceApiCalled=false',
      );
      if (rejectReason != null && mounted) {
        setState(() {
          _verificationFailed = true;
          _failureReason = rejectReason;
        });
      }
      return;
    }
    if (!_hasShift) {
      debugPrint(
        'FaceAttendance preSubmitGuard allow=false reason=no_shift '
        'employeeId=${widget.employee.name} attendanceApiCalled=false',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shift not assigned. Please contact HR.'),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      debugPrint(
        'FaceAttendance preSubmitGuard allow=true '
        'employeeId=${widget.employee.name} '
        'faceReadyForBackend=$_serverVerificationReady '
        'localIdentityMatchUsed=false attendanceApiCalled=true',
      );
      final scope = AppScope.of(context);
      final position = await scope.locationService.determinePosition();
      if (mounted) {
        setState(() {
          _lastPosition = position;
          _submittedAt = DateTime.now();
        });
      }
      final capturedImagePath = await _captureAttendanceImagePath();
      final result = await scope.repository.markAttendance(
        employee: widget.employee,
        logType: widget.logType,
        time: DateTime.now(),
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        faceVerified: true,
        capturedImagePath: capturedImagePath,
        faceEmbedding: _liveEmbedding,
      );
      await _stopImageStream();
      if (!mounted) return;
      final distanceText = result.faceDistance == null
          ? ''
          : ' Distance ${result.faceDistance!.toStringAsFixed(4)}.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.serverMessage ?? 'Attendance marked successfully'}$distanceText',
          ),
          backgroundColor: AppColors.green,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failureReason = friendlyErrorMessage(error);
        _verificationFailed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(error)),
          backgroundColor: AppColors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<String> _captureAttendanceImagePath() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      throw const ErpError('Camera unavailable. Please try again.');
    }

    await _stopImageStream();
    final image = await controller.takePicture();
    if (image.path.trim().isEmpty) {
      throw const ErpError('Captured image is empty. Please try again.');
    }
    debugPrint(
      'FaceAttendance capturedImageForBackend=true path=${image.path} '
      'employeeId=${widget.employee.name}',
    );
    return image.path;
  }

  @override
  Widget build(BuildContext context) {
    final actionColor = AppColors.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            PremiumCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.secondary],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      widget.employee.initials,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.employee.employeeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.employee.name,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.faint,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'IST ${DateFormats.istClock.format(_istNow)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(
                    label: _hasShift
                        ? widget.logType.toUpperCase()
                        : 'No shift',
                    foreground: _hasShift ? actionColor : AppColors.amber,
                    background: (_hasShift ? actionColor : AppColors.amber)
                        .withValues(alpha: 0.1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _AttendanceDetailsCard(
              istNow: _istNow,
              position: _lastPosition,
              submittedAt: _submittedAt,
            ),
            const SizedBox(height: 18),
            _CameraPanel(
              controller: _cameraController,
              scanController: _scanController,
              initializing: _initializing,
              faceDetected: _faceDetected || _faceVerified,
              error: _error,
              livenessPrompt: _livenessMessage,
              livenessPassed: _livenessPassed,
              onRetry: _initializeCamera,
            ),
            const SizedBox(height: 18),
            PremiumCard(
              child: Row(
                children: [
                  if (_submitting)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  else
                    Icon(
                      _faceVerified
                          ? Icons.verified_user_rounded
                          : _verificationFailed
                          ? Icons.gpp_bad_rounded
                          : Icons.face_retouching_off_rounded,
                      color: _faceVerified
                          ? AppColors.green
                          : _verificationFailed
                          ? AppColors.red
                          : AppColors.amber,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _statusTitle,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _statusSubtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.faint,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            PremiumActionButton(
              label: _isMarkIn ? 'Confirm Mark In' : 'Confirm Mark Out',
              icon: _isMarkIn ? Icons.login_rounded : Icons.logout_rounded,
              colors: const [AppColors.redLight, AppColors.primary],
              isLoading: _submitting,
              onPressed: _serverVerificationReady && _hasShift && !_submitting
                  ? _submit
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  String get _statusTitle {
    if (!_hasShift) return 'Shift not assigned';
    if (_submitting) return 'Verifying with ERPNext';
    if (_faceVerified) return 'Attendance accepted';
    if (_serverVerificationReady) return 'Ready for ERPNext verification';
    if (_timedOut) return 'Try again';
    if (!_livenessPassed && _faceDetected) return 'Checking face quality';
    if (_verificationFailed) return 'Face not ready';
    if (_faceDetected) return 'Checking face quality';
    return 'Scanning face';
  }

  String get _statusSubtitle {
    if (!_hasShift) return 'Shift not assigned. Please contact HR.';
    if (_submitting) return 'Sending live image and GPS to ERPNext.';
    if (_faceVerified) return 'Backend confirmed the face match.';
    if (_serverVerificationReady) {
      return 'Tap confirm to verify and mark attendance.';
    }
    if (_timedOut) return 'Please face the camera clearly.';
    if (!_livenessPassed && _faceDetected) return _livenessMessage;
    if (_verificationFailed) {
      if (_failureReason != null) return _failureReason!;
      return 'Keep your face centered before ERPNext verification.';
    }
    if (_faceDetected) {
      return 'Keep your face centered for the backend check.';
    }
    return 'Keep your face centered inside the scan frame.';
  }
}

class _AttendanceDetailsCard extends StatelessWidget {
  const _AttendanceDetailsCard({
    required this.istNow,
    required this.position,
    required this.submittedAt,
  });

  final DateTime istNow;
  final Position? position;
  final DateTime? submittedAt;

  @override
  Widget build(BuildContext context) {
    final captured = position != null;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _DetailRow(
            icon: Icons.access_time_rounded,
            title: 'Timestamp',
            value: submittedAt == null
                ? 'IST ${DateFormats.istClock.format(istNow)}'
                : DateFormats.forErp(submittedAt!),
          ),
          const Divider(height: 20, color: AppColors.border),
          _DetailRow(
            icon: Icons.location_on_rounded,
            title: 'Location',
            value: captured
                ? 'GPS locked for Brij Dairy HRMS'
                : 'Captured during submit',
          ),
          const Divider(height: 20, color: AppColors.border),
          _DetailRow(
            icon: Icons.gps_fixed_rounded,
            title: 'GPS Coordinates',
            value: captured
                ? '${position!.latitude.toStringAsFixed(5)}, ${position!.longitude.toStringAsFixed(5)}'
                : 'Pending secure GPS capture',
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CameraPanel extends StatelessWidget {
  const _CameraPanel({
    required this.controller,
    required this.scanController,
    required this.initializing,
    required this.faceDetected,
    required this.error,
    required this.livenessPrompt,
    required this.livenessPassed,
    required this.onRetry,
  });

  final CameraController? controller;
  final AnimationController scanController;
  final bool initializing;
  final bool faceDetected;
  final String? error;
  final String livenessPrompt;
  final bool livenessPassed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ready = controller != null && controller!.value.isInitialized;
    return AspectRatio(
      aspectRatio: 0.78,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF111827)),
            if (ready) CameraPreview(controller!),
            if (!ready) _CameraPlaceholder(initializing: initializing),
            _ScanOverlay(
              controller: scanController,
              faceDetected: faceDetected,
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      livenessPassed
                          ? Icons.verified_rounded
                          : Icons.visibility_rounded,
                      color: livenessPassed
                          ? AppColors.green
                          : AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        livenessPassed
                            ? 'Face quality accepted'
                            : livenessPrompt,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.text,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (error != null)
              Container(
                color: Colors.black.withValues(alpha: 0.62),
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.white,
                      size: 42,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry camera'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder({required this.initializing});

  final bool initializing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (initializing)
            const CircularProgressIndicator(color: Colors.white)
          else
            const Icon(
              Icons.camera_alt_outlined,
              color: Colors.white,
              size: 40,
            ),
          const SizedBox(height: 14),
          Text(
            initializing ? 'Opening secure camera' : 'Camera unavailable',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay({required this.controller, required this.faceDetected});

  final AnimationController controller;
  final bool faceDetected;

  @override
  Widget build(BuildContext context) {
    final color = faceDetected ? AppColors.green : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.all(30),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _ScanPainter(
              progress: controller.value,
              color: color,
              faceDetected: faceDetected,
            ),
          );
        },
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  const _ScanPainter({
    required this.progress,
    required this.color,
    required this.faceDetected,
  });

  final double progress;
  final Color color;
  final bool faceDetected;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(28),
    );
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color.withValues(alpha: faceDetected ? 0.9 : 0.72);
    canvas.drawRRect(frame, borderPaint);

    final cornerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = color;
    const cornerLength = 36.0;
    const inset = 2.0;
    final path = Path()
      ..moveTo(inset, cornerLength)
      ..lineTo(inset, inset)
      ..lineTo(cornerLength, inset)
      ..moveTo(size.width - cornerLength, inset)
      ..lineTo(size.width - inset, inset)
      ..lineTo(size.width - inset, cornerLength)
      ..moveTo(inset, size.height - cornerLength)
      ..lineTo(inset, size.height - inset)
      ..lineTo(cornerLength, size.height - inset)
      ..moveTo(size.width - cornerLength, size.height - inset)
      ..lineTo(size.width - inset, size.height - inset)
      ..lineTo(size.width - inset, size.height - cornerLength);
    canvas.drawPath(path, cornerPaint);

    final y = 18 + (size.height - 36) * progress;
    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.95),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(18, y - 2, size.width - 36, 4));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(18, y - 2, size.width - 36, 4),
        const Radius.circular(4),
      ),
      scanPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.faceDetected != faceDetected;
  }
}
