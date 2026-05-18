import frappe


EMPLOYEE_FIELDS = (
    "name",
    "employee_name",
    "user_id",
    "designation",
    "department",
    "company",
    "default_shift",
    "branch",
    "holiday_list",
    "image",
    "cell_number",
)


def _employee_fieldnames():
    meta = frappe.get_meta("Employee")
    return {df.fieldname for df in meta.fields}


def _get_employee_doc_for_user(user):
    fields = _employee_fieldnames()
    lookup_fields = [
        "user_id",
        "personal_email",
        "company_email",
        "prefered_email",
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
        "No Employee is mapped with this ERPNext user. Please contact HRMS admin.",
        frappe.DoesNotExistError,
    )


def employee_payload(employee, user=None):
    fields = _employee_fieldnames()
    return {
        "employee": employee.name,
        "name": employee.name,
        "employee_name": employee.employee_name or employee.name,
        "user_id": getattr(employee, "user_id", None) or user or frappe.session.user,
        "designation": getattr(employee, "designation", None) if "designation" in fields else None,
        "department": getattr(employee, "department", None) if "department" in fields else None,
        "company": getattr(employee, "company", None) if "company" in fields else None,
        "default_shift": getattr(employee, "default_shift", None) if "default_shift" in fields else None,
        "branch": getattr(employee, "branch", None) if "branch" in fields else None,
        "holiday_list": getattr(employee, "holiday_list", None) if "holiday_list" in fields else None,
        "image": getattr(employee, "image", None) if "image" in fields else None,
        "cell_number": getattr(employee, "cell_number", None) if "cell_number" in fields else None,
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

