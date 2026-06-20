# Brij Dairy ERPNext backend patch

Copy `hrms_mobile/api/employee.py`, `hrms_mobile/api/face.py`, and
`hrms_mobile/api/attendance.py` into the server-side `hrms_mobile` app,
preserving the same paths.

Run the DocType setup from bench:

```bash
cd /home/frappe/frappe-bench
bench --site app.brijdairy.com console < /path/to/setup_employee_face_profile.py
bench --site app.brijdairy.com clear-cache
bench --site app.brijdairy.com migrate
bench restart
```

The setup is idempotent and creates these Employee custom fields when missing:

```text
face_registered
face_embeddings
face_updated_on
face_model_version
face_quality_score
face_embedding_count
```

It also creates these `Employee Checkin` custom fields used by the Brij Android
app to persist timestamp/GPS metadata:

```text
custom_latitude
custom_longitude
custom_location
custom_device_time
custom_app_source
custom_app_device_id
custom_gps_accuracy
custom_face_verified
custom_source
```

Flutter calls these whitelisted methods:

```text
hrms_mobile.api.attendance.get_mobile_employees
hrms_mobile.api.attendance.sync_deleted_or_inactive_employees
hrms_mobile.api.attendance.get_my_employee_profile
hrms_mobile.api.attendance.get_logged_employee
hrms_mobile.api.attendance.get_face_profile
hrms_mobile.api.attendance.save_employee_face_embeddings
hrms_mobile.api.attendance.remove_employee_face_embeddings
hrms_mobile.api.attendance.verify_face_profile
hrms_mobile.api.attendance.mark_employee_checkin
```

Each method derives Employee from `frappe.session.user`; it does not trust an
employee id supplied by the mobile app.
