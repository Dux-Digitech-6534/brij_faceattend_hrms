# Backend Fix Required

The app is configured for `https://app.brijdairy.com` and now includes a standard ERPNext `Employee Checkin` fallback when the custom face attendance method is missing.

Authenticated API testing still requires a safe Brij ERPNext test user. Without credentials, login/current-user/employee/attendance record verification cannot be marked as passed.

## Missing Custom Apps Observed Publicly

- `hrms_mobile`: required for custom employee profile, sync, today checkins, and face profile APIs.
- `faceattend_hrms`: required for `/api/method/faceattend_hrms.api.face_attendance.verify_face_and_mark_attendance`.

## App-Side Fallback Added

If the custom attendance method is missing, the app attempts standard REST creation of `Employee Checkin` with:

- `employee`
- `shift`
- `log_type`
- `time`
- `device_id`
- `custom_face_verified`
- `custom_source`
- `custom_latitude`
- `custom_longitude`
- `custom_gps_accuracy`
- `custom_app_device_id`

If those custom fields are not present or not permitted, the app retries with standard fields only:

- `employee`
- `shift`
- `time`
- `log_type`
- `device_id`

## Server-Side Requirements

- Active `Employee` must be linked to the ERPNext user through one of: `user_id`, `prefered_email`, `company_email`, or `personal_email`.
- Employee status must be `Active`.
- Mobile user role must have enough permission to read linked Employee/Shift/Holiday data and create Employee Checkin, or the `hrms_mobile` custom APIs must be installed to perform those operations with controlled permissions.
- To store location in ERPNext records, add/permit latitude/longitude fields on `Employee Checkin`, for example `custom_latitude`, `custom_longitude`, and `custom_gps_accuracy`.
