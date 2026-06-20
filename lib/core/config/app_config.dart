class AppConfig {
  const AppConfig._();

  static const appName = 'Brij Dairy HRMS';
  static const tagline = 'ERPNext HRMS attendance';
  static const brandName = 'Brij Dairy';
  static const developerName = 'DUX Digitech';
  static const poweredBy = 'Designed & Developed by DUX Digitech';
  static const baseUrl = 'https://app.brijdairy.com';
  static const appDeviceId = 'BRIJ_DAIRY_HRMS_ANDROID';
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

  static const faceAttendanceEndpoint =
      '/api/method/brij_ventures.api.mobile.verify_face_and_mark_attendance';

  // Kept for existing UI labels that show which attendance API is active.
  static const useCustomAttendanceEndpoint = true;
  static const customAttendanceEndpoint =
      '/api/method/brij_ventures.api.mobile.mark_employee_checkin';
}
