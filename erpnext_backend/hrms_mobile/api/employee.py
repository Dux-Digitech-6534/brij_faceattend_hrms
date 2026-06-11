import json

import frappe
from frappe.utils import getdate, today


EMPLOYEE_FIELDS = (
    "name",
    "employee_name",
    "user_id",
    "personal_email",
    "company_email",
    "prefered_email",
    "designation",
    "department",
    "company",
    "default_shift",
    "branch",
    "holiday_list",
    "status",
    "image",
    "cell_number",
    "modified",
    "face_registered",
    "face_embeddings",
    "face_updated_on",
    "face_model_version",
    "face_quality_score",
    "face_embedding_count",
)


def _employee_fieldnames():
    meta = frappe.get_meta("Employee")
    return {df.fieldname for df in meta.fields}


def _get_employee_doc_for_user(user):
    fields = _employee_fieldnames()
    lookup_fields = [
        "user_id",
        "prefered_email",
        "company_email",
        "personal_email",
    ]

    for fieldname in lookup_fields:
        if fieldname not in fields:
            continue
        employees = frappe.get_all(
            "Employee",
            filters={fieldname: user},
            fields=["name"],
            limit=1,
            ignore_permissions=True,
        )
        if employees:
            return frappe.get_doc("Employee", employees[0].name)

    if frappe.db.exists("Employee", user):
        return frappe.get_doc("Employee", user)

    frappe.throw(
        "Your employee profile is inactive or removed. Please contact HR.",
        frappe.DoesNotExistError,
    )


def _get_value(employee, fieldname, fields):
    if fieldname not in fields:
        return None
    return getattr(employee, fieldname, None)


def resolve_active_shift(employee):
    fields = _employee_fieldnames()
    default_shift = _get_value(employee, "default_shift", fields)
    if default_shift:
        return default_shift

    if not frappe.db.exists("DocType", "Shift Assignment"):
        return None

    current_date = getdate(today())
    assignments = frappe.get_all(
        "Shift Assignment",
        filters={
            "employee": employee.name,
            "status": "Active",
            "start_date": ["<=", current_date],
        },
        fields=["name", "shift_type", "start_date", "end_date", "status"],
        order_by="start_date desc, creation desc",
        limit=20,
        ignore_permissions=True,
    )

    for assignment in assignments:
        end_date = assignment.get("end_date")
        if end_date and getdate(end_date) < current_date:
            continue
        shift_type = assignment.get("shift_type")
        if shift_type:
            return shift_type

    return None


def employee_payload(employee, user=None):
    fields = _employee_fieldnames()
    status = _get_value(employee, "status", fields) or "Active"
    active_shift = resolve_active_shift(employee)
    return {
        "employee_id": employee.name,
        "employee": employee.name,
        "name": employee.name,
        "employee_name": employee.employee_name or employee.name,
        "user_id": getattr(employee, "user_id", None) or user or frappe.session.user,
        "personal_email": _get_value(employee, "personal_email", fields),
        "company_email": _get_value(employee, "company_email", fields),
        "prefered_email": _get_value(employee, "prefered_email", fields),
        "designation": _get_value(employee, "designation", fields),
        "department": _get_value(employee, "department", fields),
        "company": _get_value(employee, "company", fields),
        "branch": _get_value(employee, "branch", fields),
        "default_shift": _get_value(employee, "default_shift", fields),
        "active_shift": active_shift,
        "holiday_list": _get_value(employee, "holiday_list", fields),
        "status": status,
        "is_active": status == "Active",
        "image": _get_value(employee, "image", fields),
        "cell_number": _get_value(employee, "cell_number", fields),
        "modified": getattr(employee, "modified", None),
        "face_registered": _get_value(employee, "face_registered", fields) or 0,
        "face_embeddings": _get_value(employee, "face_embeddings", fields),
        "face_updated_on": _get_value(employee, "face_updated_on", fields),
        "face_model_version": _get_value(employee, "face_model_version", fields),
        "face_quality_score": _get_value(employee, "face_quality_score", fields) or 0,
        "face_embedding_count": _get_value(employee, "face_embedding_count", fields) or 0,
    }


def get_logged_employee_doc():
    user = frappe.session.user
    if not user or user == "Guest":
        frappe.throw("Login required.", frappe.PermissionError)
    return _get_employee_doc_for_user(user)


@frappe.whitelist()
def get_logged_employee():
    employee = get_logged_employee_doc()
    return employee_payload(employee, frappe.session.user)


@frappe.whitelist()
def get_my_employee_profile():
    employee = get_logged_employee_doc()
    return employee_payload(employee, frappe.session.user)


@frappe.whitelist()
def get_mobile_employees(modified_after=None, include_inactive=0):
    fields = _employee_fieldnames()
    selected_fields = [
        field
        for field in EMPLOYEE_FIELDS
        if field in fields or field in ("name", "modified")
    ]
    filters = []
    if not int(include_inactive or 0) and "status" in fields:
        filters.append(["status", "=", "Active"])
    if modified_after:
        filters.append(["modified", ">", modified_after])

    employees = frappe.get_all(
        "Employee",
        filters=filters,
        fields=selected_fields,
        order_by="modified asc",
        ignore_permissions=True,
    )

    rows = []
    for row in employees:
        doc = frappe._dict(row)
        doc.name = row.get("name")
        rows.append(employee_payload(doc))

    return {
        "employees": rows,
        "count": len(rows),
        "modified_after": modified_after,
    }


@frappe.whitelist()
def sync_deleted_or_inactive_employees(employee_ids=None):
    if isinstance(employee_ids, str):
        try:
            employee_ids = json.loads(employee_ids)
        except Exception:
            employee_ids = [item.strip() for item in employee_ids.split(",") if item.strip()]
    employee_ids = employee_ids or []
    inactive_or_missing = []
    fields = _employee_fieldnames()

    for employee in employee_ids:
        if not frappe.db.exists("Employee", employee):
            inactive_or_missing.append(employee)
            continue
        status = frappe.db.get_value("Employee", employee, "status") if "status" in fields else "Active"
        if status and status != "Active":
            inactive_or_missing.append(employee)

    return {
        "employees_removed": inactive_or_missing,
        "count": len(inactive_or_missing),
    }
