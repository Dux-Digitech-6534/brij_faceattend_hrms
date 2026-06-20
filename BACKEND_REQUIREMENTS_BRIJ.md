# Brij Dairy Backend Requirements

The Flutter build is configured for `https://app.brijdairy.com`, but the public API checks currently show these custom apps are missing on the Brij site:

- `hrms_mobile`: required for employee profile, mobile sync, face profile, and today checkins.
- `faceattend_hrms`: required for the currently configured face verification attendance endpoint.

## Required APIs

- `POST /api/method/login`
- `POST /api/method/logout`
- `GET /api/method/frappe.auth.get_logged_user`
- `GET /api/method/hrms_mobile.api.attendance.get_my_employee_profile`
- `GET /api/method/hrms_mobile.api.attendance.get_logged_employee`
- `GET /api/method/hrms_mobile.api.attendance.get_today_employee_checkins`
- `GET /api/method/hrms_mobile.api.attendance.get_mobile_employees`
- `GET /api/method/hrms_mobile.api.attendance.get_face_profile`
- `POST /api/method/hrms_mobile.api.attendance.save_employee_face_embeddings`
- `POST /api/method/faceattend_hrms.api.face_attendance.verify_face_and_mark_attendance`
- REST fallback access to `Employee`, `Shift Assignment`, `Shift Type`, `Holiday`, `Employee Checkin`, and `Employee Face Profile`

## Required Employee Fields

- `face_registered`
- `face_embeddings`
- `face_updated_on`
- `face_model_version`
- `face_quality_score`
- `face_embedding_count`

## Attendance Data To Store

- employee/user reference
- attendance/checkin timestamp
- log type: `IN` or `OUT`
- latitude
- longitude
- GPS accuracy when available
- device/app source: `Brij Dairy HRMS Flutter App`
- face verification result/distance when returned by backend

## Current Public Check Result

Unauthenticated requests to the Brij site respond, but these custom method checks fail because the apps are not installed:

- `hrms_mobile.api.attendance.get_my_employee_profile`: `App hrms_mobile is not installed`
- `faceattend_hrms.api.face_attendance.verify_face_and_mark_attendance`: `App faceattend_hrms is not installed`
