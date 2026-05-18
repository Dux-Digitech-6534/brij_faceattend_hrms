# FaceAttend HRMS

Premium Flutter Android attendance app for ERPNext HRMS at `https://erp.jewonline.in`.

## Features

- Employee login through ERPNext `/api/method/login`
- Secure session cookie storage with `flutter_secure_storage`
- Dashboard with employee, shift, holiday, sync, and attendance status
- Face-detection based Mark In and Mark Out using Google ML Kit
- Camera preview using the Flutter `camera` package
- GPS capture before attendance submission
- Employee Checkin creation through ERPNext REST API
- Optional custom endpoint placeholder:
  `/api/method/hrms_mobile.api.attendance.mark_checkin`
- Attendance history, profile, and sync screens
- Premium light-mode UI with FaceAttend HRMS branding

## ERPNext API Used

- `POST /api/method/login`
- `GET /api/method/frappe.auth.get_logged_user`
- `GET /api/resource/Employee?filters=[["user_id","=","USER"]]`
- `GET /api/resource/Shift Type/{shift}`
- `GET /api/resource/Holiday`
- `GET /api/resource/Employee Checkin?filters=...`
- `POST /api/resource/Employee Checkin`

The standard Employee Checkin payload includes `employee`, `log_type`, `time`,
`latitude`, `longitude`, and `custom_face_verified`. If the ERPNext site does
not have the custom face field, the app retries the Checkin creation without it.

## Setup

```bash
flutter pub get
flutter run
flutter build apk --release
```

## Android Permissions

The app requests:

- Camera
- Fine location
- Coarse location
- Internet

## Custom Endpoint

To use a server-side attendance method instead of direct REST insertion, edit:

`lib/core/config/app_config.dart`

Set:

```dart
static const useCustomAttendanceEndpoint = true;
```

Then implement this ERPNext method:

```text
hrms_mobile.api.attendance.mark_checkin
```

Expected request fields:

- `employee`
- `log_type`
- `time`
- `latitude`
- `longitude`
- `face_verified`
