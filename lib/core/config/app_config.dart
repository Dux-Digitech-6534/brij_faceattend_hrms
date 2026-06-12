class AppConfig {
  const AppConfig._();

  static const appName = 'DUX FaceAttend HRMS';
  static const tagline = 'ERPNext HRMS face attendance';
  static const brandName = 'DUX Digitech';
  static const poweredBy = 'Powered by DUX Digitech';
  static const baseUrl = 'https://erp.jewonline.in';
  static const appDeviceId = 'FACEATTEND_ANDROID';
  static const faceStrongMatchThreshold = 0.90;
  static const faceMediumMatchThreshold = 0.78;
  static const faceCosineThreshold = faceStrongMatchThreshold;
  static const faceMediumStableFrames = 3;
  static const faceRecognitionStableFrames = 3;
  static const kbyFaceMatchThreshold = 0.88;
  static const kbyFaceLivenessThreshold = 0.70;
  static const maxFaceYawDegrees = 18.0;
  static const maxFaceRollDegrees = 16.0;
  static const maxFacePitchDegrees = 18.0;
  static const faceFrameInterval = Duration(milliseconds: 420);
  static const faceAttendanceTimeout = Duration(seconds: 22);
  static const faceModelAssetPath = 'assets/models/mobilefacenet.tflite';
  static const faceEngineName = 'kby-or-tflite-mobilefacenet';
  static const faceThresholdVersion = 'strict-stable-v2';
  static const faceModelVersion = 'kby-face-sdk-mobilefacenet-112-aligned-v3';
  static const faceRegistrationSampleCount = 5;

  // Backend verifies the live face against ERPNext's stored reference image and
  // creates the Attendance Log only after message.status == success.
  static const faceAttendanceEndpoint =
      '/api/method/faceattend_hrms.api.face_attendance.verify_face_and_mark_attendance';

  // Kept for existing UI labels that show which attendance API is active.
  static const useCustomAttendanceEndpoint = true;
  static const customAttendanceEndpoint = faceAttendanceEndpoint;
}
