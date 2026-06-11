class AppConfig {
  const AppConfig._();

  static const appName = 'DUX FaceAttend HRMS';
  static const tagline = 'ERPNext HRMS face attendance';
  static const brandName = 'DUX Digitech';
  static const poweredBy = 'Powered by DUX Digitech';
  static const baseUrl = 'https://erp.jewonline.in';
  static const appDeviceId = 'FACEATTEND_ANDROID';
  static const faceStrongMatchThreshold = 0.84;
  static const faceMediumMatchThreshold = 0.78;
  static const faceCosineThreshold = faceMediumMatchThreshold;
  static const faceMediumStableFrames = 3;
  static const kbyFaceMatchThreshold = 0.86;
  static const kbyFaceLivenessThreshold = 0.70;
  static const maxFaceYawDegrees = 18.0;
  static const maxFaceRollDegrees = 16.0;
  static const maxFacePitchDegrees = 18.0;
  static const faceFrameInterval = Duration(milliseconds: 420);
  static const faceAttendanceTimeout = Duration(seconds: 22);
  static const faceModelAssetPath = 'assets/models/mobilefacenet.tflite';
  static const faceModelVersion = 'kby-face-sdk-mobilefacenet-112-v2';
  static const faceRegistrationSampleCount = 5;

  // Custom endpoint is safer because it validates active employees and optional
  // custom GPS/device fields before creating Employee Checkin.
  static const useCustomAttendanceEndpoint = true;
  static const customAttendanceEndpoint =
      '/api/method/hrms_mobile.api.attendance.mark_employee_checkin';
}
