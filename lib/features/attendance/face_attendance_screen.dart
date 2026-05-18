import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/app_scope.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/erp_error.dart';
import '../../data/models/employee.dart';
import '../../data/models/face_profile.dart';
import '../../data/services/face_embedding_service.dart';
import '../../data/services/face_profile_service.dart';
import '../../shared/widgets/premium_action_button.dart';
import '../../shared/widgets/premium_card.dart';
import '../../shared/widgets/status_pill.dart';

class FaceAttendanceScreen extends StatefulWidget {
  const FaceAttendanceScreen({
    required this.employee,
    required this.logType,
    this.initialFaceProfile,
    super.key,
  });

  final Employee employee;
  final String logType;
  final FaceProfile? initialFaceProfile;

  @override
  State<FaceAttendanceScreen> createState() => _FaceAttendanceScreenState();
}

class _FaceAttendanceScreenState extends State<FaceAttendanceScreen>
    with SingleTickerProviderStateMixin {
  late final FaceDetector _faceDetector;
  late final AnimationController _scanController;
  late FaceEmbeddingService _embeddingService;
  late FaceProfileService _faceProfileService;
  CameraController? _cameraController;
  CameraDescription? _camera;
  FaceProfile? _faceProfile;
  bool _initializing = true;
  bool _loadingFaceProfile = true;
  bool _processingFrame = false;
  bool _faceDetected = false;
  bool _faceVerified = false;
  bool _verificationFailed = false;
  bool _submitting = false;
  String? _error;
  String? _profileError;
  double? _lastScore;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastVerificationAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFailureSnackAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _isMarkIn => widget.logType.toUpperCase() == 'IN';
  bool get _hasProfile => _faceProfile != null && _faceProfile!.hasEmbedding;

  @override
  void initState() {
    super.initState();
    _faceProfile = widget.initialFaceProfile;
    _loadingFaceProfile = widget.initialFaceProfile == null;
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: true,
        enableTracking: true,
        minFaceSize: 0.18,
      ),
    );
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFaceProfile());
    _initializeCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    _embeddingService = scope.faceEmbeddingService;
    _faceProfileService = scope.faceProfileService;
  }

  @override
  void dispose() {
    if (_cameraController?.value.isStreamingImages ?? false) {
      _cameraController?.stopImageStream();
    }
    _cameraController?.dispose();
    _faceDetector.close();
    _scanController.dispose();
    super.dispose();
  }

  Future<void> _loadFaceProfile() async {
    if (_hasProfile) {
      setState(() => _loadingFaceProfile = false);
      return;
    }

    setState(() {
      _loadingFaceProfile = true;
      _profileError = null;
    });

    try {
      final profile = await _faceProfileService.getFaceProfile(
        widget.employee.name,
      );
      if (!mounted) return;
      setState(() {
        _faceProfile = profile;
        _profileError = profile == null || !profile.hasEmbedding
            ? 'Face not registered. Please register your face first.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _profileError = '$error');
    } finally {
      if (mounted) setState(() => _loadingFaceProfile = false);
    }
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _initializing = true;
      _error = null;
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
        _error = '$error';
      });
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_processingFrame || _submitting) return;
    final now = DateTime.now();
    if (now.difference(_lastFrameAt) < const Duration(milliseconds: 450)) {
      return;
    }
    _lastFrameAt = now;
    _processingFrame = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;
      final faces = await _faceDetector.processImage(inputImage);
      final detected = faces.isNotEmpty;
      if (mounted && detected != _faceDetected) {
        setState(() => _faceDetected = detected);
      }
      if (!_hasProfile || _faceVerified || faces.isEmpty) return;
      if (now.difference(_lastVerificationAt) <
          const Duration(milliseconds: 900)) {
        return;
      }
      _lastVerificationAt = now;

      final liveEmbedding = await _embeddingService.createEmbedding(
        image: image,
        face: faces.first,
      );
      final result = _faceProfileService.verifyFaceProfile(
        profile: _faceProfile!,
        liveEmbedding: liveEmbedding,
      );
      debugPrint(
        'Face verification score: cosine=${result.cosineSimilarity.toStringAsFixed(4)}, '
        'distance=${result.euclideanDistance.toStringAsFixed(4)}, '
        'threshold=${AppConfig.faceCosineThreshold.toStringAsFixed(2)}',
      );
      if (!mounted) return;
      setState(() {
        _lastScore = result.cosineSimilarity;
        _faceVerified = result.matched;
        _verificationFailed = !result.matched;
      });
      if (!result.matched) _showVerificationFailedSnack();
    } catch (_) {
      if (mounted && _faceDetected) {
        setState(() => _faceDetected = false);
      }
    } finally {
      _processingFrame = false;
    }
  }

  void _showVerificationFailedSnack() {
    final now = DateTime.now();
    if (now.difference(_lastFailureSnackAt) < const Duration(seconds: 4)) {
      return;
    }
    _lastFailureSnackAt = now;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Face verification failed. Please try again.'),
        backgroundColor: AppColors.red,
      ),
    );
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
    if (!_faceVerified || _submitting) return;
    setState(() => _submitting = true);

    try {
      final scope = AppScope.of(context);
      final position = await scope.locationService.determinePosition();
      await scope.repository.markAttendance(
        employee: widget.employee,
        logType: widget.logType,
        time: DateTime.now(),
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        faceVerified: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.logType.toUpperCase()} marked successfully.'),
          backgroundColor: AppColors.green,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: AppColors.red),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actionColor = _isMarkIn ? AppColors.green : AppColors.red;
    return Scaffold(
      appBar: AppBar(title: Text(_isMarkIn ? 'Face Mark In' : 'Face Mark Out')),
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
                      ],
                    ),
                  ),
                  StatusPill(
                    label: widget.logType.toUpperCase(),
                    foreground: actionColor,
                    background: actionColor.withValues(alpha: 0.1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _CameraPanel(
              controller: _cameraController,
              scanController: _scanController,
              initializing: _initializing,
              faceDetected: _faceDetected || _faceVerified,
              error: _error,
              onRetry: _initializeCamera,
            ),
            const SizedBox(height: 18),
            PremiumCard(
              child: Row(
                children: [
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
              colors: _isMarkIn
                  ? const [Color(0xFF00D090), AppColors.green]
                  : const [Color(0xFFFF6680), AppColors.red],
              isLoading: _submitting,
              onPressed: _faceVerified ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }

  String get _statusTitle {
    if (_loadingFaceProfile) return 'Loading face profile';
    if (_profileError != null) return 'Face not registered';
    if (_faceVerified) return 'Face verified';
    if (_verificationFailed) return 'Face verification failed';
    if (_faceDetected) return 'Matching face profile';
    return 'Scanning face';
  }

  String get _statusSubtitle {
    if (_loadingFaceProfile) {
      return 'Fetching registered template from ERPNext.';
    }
    if (_profileError != null) return _profileError!;
    if (_faceVerified) {
      final score = _lastScore == null
          ? ''
          : ' Score ${_lastScore!.toStringAsFixed(2)}.';
      return 'GPS will be captured before ERPNext submission.$score';
    }
    if (_verificationFailed) {
      final score = _lastScore == null
          ? ''
          : ' Score ${_lastScore!.toStringAsFixed(2)}.';
      return 'Face verification failed. Please try again.$score';
    }
    if (_faceDetected) {
      return 'Keep your face centered while the live template is checked.';
    }
    return 'Keep your face centered inside the scan frame.';
  }
}

class _CameraPanel extends StatelessWidget {
  const _CameraPanel({
    required this.controller,
    required this.scanController,
    required this.initializing,
    required this.faceDetected,
    required this.error,
    required this.onRetry,
  });

  final CameraController? controller;
  final AnimationController scanController;
  final bool initializing;
  final bool faceDetected;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ready = controller != null && controller!.value.isInitialized;
    return AspectRatio(
      aspectRatio: 0.78,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
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
