class AppConfig {
  const AppConfig._();

  static const appName = 'FaceAttend HRMS';
  static const tagline = 'Smart. Secure. Seamless.';
  static const baseUrl = 'https://erp.jewonline.in';
  static const appDeviceId = 'FACEATTEND_ANDROID';
  static const faceCosineThreshold = 0.75;

  // Toggle this to true after adding the custom method on ERPNext.
  static const useCustomAttendanceEndpoint = false;
  static const customAttendanceEndpoint =
      '/api/method/hrms_mobile.api.attendance.mark_checkin';
}
