# ERPNext backend patch

Copy `hrms_mobile/api/employee.py` and `hrms_mobile/api/face.py` into the
server-side `hrms_mobile` app, preserving the same paths.

Run the DocType setup from bench:

```bash
cd /home/frappe/frappe-bench
bench --site erp.jewonline.in console < /path/to/setup_employee_face_profile.py
bench --site erp.jewonline.in clear-cache
bench --site erp.jewonline.in migrate
bench restart
```

Flutter calls these whitelisted methods first:

```text
hrms_mobile.api.employee.get_logged_employee
hrms_mobile.api.face.get_face_profile
hrms_mobile.api.face.save_face_profile
hrms_mobile.api.face.verify_face_profile
```

Each method derives Employee from `frappe.session.user`; it does not trust an
employee id supplied by the mobile app.

