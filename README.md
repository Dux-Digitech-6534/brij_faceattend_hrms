# Brij Dairy HRMS

Flutter Android face-attendance HRMS app for Brij Dairy, using the original dark FaceAttend flow with Brij branding and DUX Digitech delivery credit.

## Configuration

- App name: Brij Dairy HRMS
- Android package/applicationId: `com.duxdigitech.brijdairyhrms`
- Backend URL: `https://app.brijdairy.com`
- Development credit: Designed & Developed by DUX Digitech

## Existing Mobile Features

- ERPNext login through `/api/method/login`
- Secure session cookie storage with `flutter_secure_storage`
- Dashboard with employee, shift, holiday, sync, and attendance status
- Face-detection based Mark In and Mark Out using Google ML Kit
- Camera preview using the Flutter `camera` package
- GPS capture before attendance submission
- Attendance history, profile sync, and face registration screens

## Backend Requirements

The Flutter app keeps the existing API structure from the source project. The Brij ERPNext site must provide these server-side apps/methods before end-to-end login/dashboard/attendance testing can pass:

- `hrms_mobile`
- `faceattend_hrms`

See `BACKEND_REQUIREMENTS_BRIJ.md` for the exact checklist.

## Build

```bash
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```
