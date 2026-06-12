import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/app_scope.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/erp_error.dart';
import '../../data/models/employee.dart';
import '../../data/services/face_embedding_service.dart';
import '../../services/face_detection_service.dart';
import '../../services/kby_face_recognition_service.dart';
import '../../shared/widgets/premium_action_button.dart';
import '../../shared/widgets/premium_card.dart';
import '../../shared/widgets/status_pill.dart';

class RegisterFaceScreen extends StatefulWidget {
  const RegisterFaceScreen({
    required this.employee,
    required this.user,
    super.key,
  });

  final Employee employee;
  final String user;

  @override
  State<RegisterFaceScreen> createState() => _RegisterFaceScreenState();
}

class _RegisterFaceScreenState extends State<RegisterFaceScreen>
    with SingleTickerProviderStateMixin {
  static const _sampleTarget = AppConfig.faceRegistrationSampleCount;

  late final FaceDetector _faceDetector;
  final FaceDetectionService _faceDetectionService =
      const FaceDetectionService();
  final KbyFaceRecognitionService _kbyFaceRecognitionService =
      KbyFaceRecognitionService();
  late final AnimationController _scanController;
  late FaceEmbeddingService _embeddingService;

  CameraController? _cameraController;
  CameraDescription? _camera;
  final List<List<double>> _samples = [];
  final List<String> _kbyTemplates = [];
  final List<double> _sampleQualities = [];
  bool _initializing = true;
  bool _engineInitStarted = false;
  bool _recognitionEngineInitializing = true;
  bool _recognitionEngineReady = false;
  bool _useKbyRecognition = false;
  bool _processingFrame = false;
  bool _started = false;
  bool _faceDetected = false;
  bool _saving = false;
  String? _error;
  double _qualityTotal = 0;
  DateTime _lastFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSampleAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _completed => _samples.length >= _sampleTarget;
  String get _selectedEngine => _useKbyRecognition
      ? 'KBY FaceSDK'
      : _recognitionEngineReady
      ? 'Flutter/TFLite fallback'
      : 'unavailable';

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
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
    _initializeCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _embeddingService = AppScope.of(context).faceEmbeddingService;
    if (!_engineInitStarted) {
      _engineInitStarted = true;
      _initializeRecognitionEngine();
    }
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
    });

    try {
      final permission = await Permission.camera.request();
      if (!permission.isGranted) {
        throw const ErpError(
          'Camera permission is required for face registration.',
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

  Future<void> _initializeRecognitionEngine() async {
    if (mounted) {
      setState(() {
        _recognitionEngineInitializing = true;
        _recognitionEngineReady = false;
      });
    }

    final kbyStatus = await _kbyFaceRecognitionService.initialize();
    if (kbyStatus.available) {
      if (!mounted) return;
      setState(() {
        _useKbyRecognition = true;
        _recognitionEngineReady = true;
        _recognitionEngineInitializing = false;
      });
      debugPrint(
        'FaceRegister engine ready selectedEngine=$_selectedEngine '
        'activationCode=${kbyStatus.activationCode ?? 'n/a'} '
        'initCode=${kbyStatus.initCode ?? 'n/a'}',
      );
      return;
    }

    debugPrint(
      'FaceRegister KBY unavailable; trying Flutter/TFLite fallback. '
      'reason=${kbyStatus.failureReason}',
    );
    try {
      await _embeddingService.initialize();
      if (!mounted) return;
      setState(() {
        _useKbyRecognition = false;
        _recognitionEngineReady = true;
        _recognitionEngineInitializing = false;
      });
      debugPrint(
        'FaceRegister engine ready selectedEngine=$_selectedEngine '
        'kbyFailure=${kbyStatus.failureReason}',
      );
    } catch (error, stackTrace) {
      debugPrint('FaceRegister fallback engine init failed error=$error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _useKbyRecognition = false;
        _recognitionEngineReady = false;
        _recognitionEngineInitializing = false;
        _error = 'Face recognition engine unavailable.';
      });
    }
  }

  void _startRegistration() {
    if (!_recognitionEngineReady) {
      setState(() {
        _error = _recognitionEngineInitializing
            ? 'Face recognition engine is initializing. Please wait.'
            : 'Face recognition engine unavailable.';
      });
      debugPrint(
        'FaceRegister reject reason=engine_not_ready '
        'selectedEngine=$_selectedEngine',
      );
      return;
    }
    setState(() {
      _samples.clear();
      _kbyTemplates.clear();
      _sampleQualities.clear();
      _qualityTotal = 0;
      _started = true;
      _error = null;
      _lastSampleAt = DateTime.fromMillisecondsSinceEpoch(0);
    });
    debugPrint(
      'FaceRegister started selectedEngine=$_selectedEngine '
      'sampleTarget=$_sampleTarget',
    );
  }

  Future<void> _recapture() async {
    setState(() {
      _samples.clear();
      _kbyTemplates.clear();
      _sampleQualities.clear();
      _qualityTotal = 0;
      _started = false;
      _faceDetected = false;
      _error = null;
    });
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        !controller.value.isStreamingImages) {
      await _initializeCamera();
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_processingFrame || _saving) return;
    final now = DateTime.now();
    if (now.difference(_lastFrameAt) < const Duration(milliseconds: 350)) {
      return;
    }
    _lastFrameAt = now;
    _processingFrame = true;

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
        'FaceRegister detectedFaceCount=${validation.detectedFaceCount} '
        'faceBoundingBox=${validation.faceBoundingBox} '
        'faceQualityScore=${validation.faceQualityScore.toStringAsFixed(3)} '
        'failureReason=${validation.failureReason ?? ''} '
        'debug=${validation.debugInfo}',
      );

      if (!_started || _completed) return;
      if (!_recognitionEngineReady) {
        if (mounted) {
          setState(() => _error = 'Face recognition engine unavailable.');
        }
        debugPrint(
          'FaceRegister sample reject reason=engine_not_ready '
          'selectedEngine=$_selectedEngine',
        );
        return;
      }
      if (!validation.isValid || validation.face == null) {
        if (mounted) setState(() => _error = validation.failureReason);
        return;
      }
      if (now.difference(_lastSampleAt) < const Duration(milliseconds: 850)) {
        return;
      }

      String? kbyTemplateBase64;
      if (_useKbyRecognition) {
        final kbyTemplate = await _kbyFaceRecognitionService.extractTemplate(
          image: image,
          camera: _camera,
        );
        if (kbyTemplate.success && kbyTemplate.hasTemplate) {
          kbyTemplateBase64 = kbyTemplate.templateBase64;
        } else if (kbyTemplate.engineUnavailable) {
          _useKbyRecognition = false;
          debugPrint(
            'FaceRegister switching to fallback reason=${kbyTemplate.failureReason}',
          );
        } else {
          if (mounted) setState(() => _error = kbyTemplate.failureReason);
          debugPrint(
            'FaceRegister sample reject reason=${kbyTemplate.failureReason} '
            'selectedEngine=KBY FaceSDK',
          );
          return;
        }
      }

      final embedding = await _embeddingService.createEmbedding(
        image: image,
        face: validation.face!,
        camera: _camera,
        faceQualityScore: validation.faceQualityScore,
      );
      if (!mounted || embedding.isEmpty) return;

      setState(() {
        _samples.add(embedding);
        if (kbyTemplateBase64 != null) _kbyTemplates.add(kbyTemplateBase64);
        _sampleQualities.add(validation.faceQualityScore);
        _qualityTotal += validation.faceQualityScore;
        _error = null;
        _lastSampleAt = now;
        if (_completed) _started = false;
      });
      debugPrint(
        'FaceRegister sampleAccepted count=${_samples.length}/$_sampleTarget '
        'selectedEngine=$_selectedEngine kbyTemplate=${kbyTemplateBase64 != null} '
        'quality=${validation.faceQualityScore.toStringAsFixed(3)}',
      );
      if (_completed) await _stopImageStream();
    } catch (_) {
      if (mounted && _faceDetected) {
        setState(() => _faceDetected = false);
      }
    } finally {
      _processingFrame = false;
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

  Future<void> _stopImageStream() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  Future<void> _saveFaceProfile() async {
    if (!_completed || _saving) return;
    setState(() => _saving = true);

    try {
      final embedding = _embeddingService.averageEmbeddings(_samples);
      if (embedding.isEmpty) {
        throw const ErpError('Embedding not generated. Please capture again.');
      }
      final bestIndex = _bestSampleIndex();
      final samples = List<List<double>>.from(_samples);
      if (bestIndex > 0) {
        final best = samples.removeAt(bestIndex);
        samples.insert(0, best);
      }
      await AppScope.of(context).faceProfileService.saveFaceProfile(
        employee: widget.employee,
        embedding: embedding,
        embeddings: samples,
        kbyTemplatesBase64: List<String>.from(_kbyTemplates),
        qualityScore: _samples.isEmpty ? 0 : _qualityTotal / _samples.length,
        sampleCount: _samples.length,
        deviceId: AppConfig.appDeviceId,
      );
      debugPrint(
        'FaceRegister save success selectedEngine=$_selectedEngine '
        'sampleCount=${_samples.length} kbyTemplateCount=${_kbyTemplates.length} '
        'avgQuality=${(_qualityTotal / _samples.length).toStringAsFixed(3)}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Face registered successfully. You can now mark attendance.',
          ),
          backgroundColor: AppColors.green,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(error)),
          backgroundColor: AppColors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  int _bestSampleIndex() {
    if (_sampleQualities.isEmpty) return 0;
    var bestIndex = 0;
    var bestQuality = _sampleQualities.first;
    for (var index = 1; index < _sampleQualities.length; index++) {
      if (_sampleQualities[index] > bestQuality) {
        bestQuality = _sampleQualities[index];
        bestIndex = index;
      }
    }
    return bestIndex;
  }

  String _promptForSample(int sampleNumber) {
    switch ((sampleNumber - 1) % 3) {
      case 1:
        return 'Move slightly left';
      case 2:
        return 'Move slightly right';
      default:
        return 'Look straight';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSample = math.min(_samples.length + 1, _sampleTarget);
    return Scaffold(
      appBar: AppBar(title: const Text('Register Face')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            _EmployeeDetailCard(employee: widget.employee, user: widget.user),
            const SizedBox(height: 16),
            _CameraScanCard(
              controller: _cameraController,
              scanController: _scanController,
              initializing: _initializing,
              faceDetected: _faceDetected,
              started: _started,
              completed: _completed,
              sampleCount: _samples.length,
              currentSample: currentSample,
              sampleTarget: _sampleTarget,
              prompt: _promptForSample(currentSample),
              error: _error,
              onRetry: _initializeCamera,
            ),
            const SizedBox(height: 16),
            _ProgressCard(
              sampleCount: _samples.length,
              sampleTarget: _sampleTarget,
              faceDetected: _faceDetected,
              started: _started,
              completed: _completed,
            ),
            const SizedBox(height: 18),
            PremiumActionButton(
              label: _completed
                  ? 'Save Face Profile'
                  : 'Start Face Registration',
              icon: _completed
                  ? Icons.cloud_done_rounded
                  : Icons.face_retouching_natural_rounded,
              colors: const [AppColors.primary, AppColors.secondary],
              isLoading: _saving,
              onPressed: _completed ? _saveFaceProfile : _startRegistration,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: (_samples.isNotEmpty || _started) && !_saving
                  ? () => _recapture()
                  : null,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Re-capture'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeDetailCard extends StatelessWidget {
  const _EmployeeDetailCard({required this.employee, required this.user});

  final Employee employee;
  final String user;

  @override
  Widget build(BuildContext context) {
    final details = [
      ('Employee ID', employee.name),
      ('Name', employee.employeeName),
      ('Designation', employee.designation ?? 'Not available'),
      ('Department', employee.department ?? 'Not available'),
      ('Company', employee.company ?? 'Not available'),
      ('Shift', employee.resolvedShift ?? 'Not assigned'),
      if (employee.branch != null && employee.branch!.trim().isNotEmpty)
        ('Branch', employee.branch!),
      ('User', employee.userId ?? user),
    ];

    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  employee.initials,
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
                      employee.employeeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      employee.name,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.faint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const StatusPill(
                label: 'Own profile',
                foreground: AppColors.primary,
                background: AppColors.primarySoft,
                icon: Icons.lock_rounded,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...details.map((item) => _DetailLine(label: item.$1, value: item.$2)),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.faint,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraScanCard extends StatelessWidget {
  const _CameraScanCard({
    required this.controller,
    required this.scanController,
    required this.initializing,
    required this.faceDetected,
    required this.started,
    required this.completed,
    required this.sampleCount,
    required this.currentSample,
    required this.sampleTarget,
    required this.prompt,
    required this.error,
    required this.onRetry,
  });

  final CameraController? controller;
  final AnimationController scanController;
  final bool initializing;
  final bool faceDetected;
  final bool started;
  final bool completed;
  final int sampleCount;
  final int currentSample;
  final int sampleTarget;
  final String prompt;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ready = controller != null && controller!.value.isInitialized;
    final status = completed
        ? 'Captured $sampleTarget of $sampleTarget'
        : started
        ? 'Capturing sample $currentSample of $sampleTarget'
        : 'Ready to capture $sampleTarget samples';

    return PremiumCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 0.8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: const Color(0xFF111827)),
                  if (ready) CameraPreview(controller!),
                  if (!ready) _CameraPlaceholder(initializing: initializing),
                  _RegistrationScanOverlay(
                    controller: scanController,
                    faceDetected: faceDetected,
                    completed: completed,
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: _InstructionPill(
                      title: completed ? 'Samples captured' : prompt,
                      subtitle: status,
                      faceDetected: faceDetected,
                      completed: completed,
                    ),
                  ),
                  if (error != null)
                    _CameraError(error: error!, onRetry: onRetry),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionPill extends StatelessWidget {
  const _InstructionPill({
    required this.title,
    required this.subtitle,
    required this.faceDetected,
    required this.completed,
  });

  final String title;
  final String subtitle;
  final bool faceDetected;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final color = completed
        ? AppColors.green
        : faceDetected
        ? AppColors.secondary
        : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            completed
                ? Icons.check_circle_rounded
                : Icons.center_focus_strong_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.sampleCount,
    required this.sampleTarget,
    required this.faceDetected,
    required this.started,
    required this.completed,
  });

  final int sampleCount;
  final int sampleTarget;
  final bool faceDetected;
  final bool started;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final value = sampleCount / sampleTarget;
    final text = completed
        ? 'Samples ready'
        : started
        ? 'Capturing automatically'
        : 'Start when your face is centered';
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                completed
                    ? Icons.verified_rounded
                    : faceDetected
                    ? Icons.face_rounded
                    : Icons.face_retouching_off_rounded,
                color: completed
                    ? AppColors.green
                    : faceDetected
                    ? AppColors.secondary
                    : AppColors.amber,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              StatusPill(
                label: '$sampleCount/$sampleTarget',
                foreground: completed ? AppColors.green : AppColors.primary,
                background: (completed ? AppColors.green : AppColors.primary)
                    .withValues(alpha: 0.1),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: value,
              backgroundColor: AppColors.primarySoft,
              color: completed ? AppColors.green : AppColors.primary,
            ),
          ),
        ],
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

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.62),
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 42),
          const SizedBox(height: 14),
          Text(
            error,
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
    );
  }
}

class _RegistrationScanOverlay extends StatelessWidget {
  const _RegistrationScanOverlay({
    required this.controller,
    required this.faceDetected,
    required this.completed,
  });

  final AnimationController controller;
  final bool faceDetected;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final color = completed
        ? AppColors.green
        : faceDetected
        ? AppColors.secondary
        : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.all(30),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _RegistrationScanPainter(
              progress: controller.value,
              color: color,
              faceDetected: faceDetected,
              completed: completed,
            ),
          );
        },
      ),
    );
  }
}

class _RegistrationScanPainter extends CustomPainter {
  const _RegistrationScanPainter({
    required this.progress,
    required this.color,
    required this.faceDetected,
    required this.completed,
  });

  final double progress;
  final Color color;
  final bool faceDetected;
  final bool completed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.36;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = completed ? 5 : 3.5
      ..color = color.withValues(alpha: completed ? 0.95 : 0.72);
    canvas.drawCircle(center, radius, ringPaint);

    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius + 8),
      -math.pi / 2 + (math.pi * 2 * progress),
      math.pi * 0.7,
      false,
      sweepPaint,
    );

    final lineY = center.dy - radius + (radius * 2 * progress);
    final scanPaint = Paint()
      ..shader =
          LinearGradient(
            colors: [
              color.withValues(alpha: 0),
              color.withValues(alpha: 0.9),
              color.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromLTWH(center.dx - radius, lineY - 2, radius * 2, 4),
          );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(center.dx - radius, lineY - 2, radius * 2, 4),
        const Radius.circular(4),
      ),
      scanPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RegistrationScanPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.faceDetected != faceDetected ||
        oldDelegate.completed != completed;
  }
}
