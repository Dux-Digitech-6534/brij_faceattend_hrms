import frappe
from frappe.custom.doctype.custom_field.custom_field import create_custom_fields


def create_employee_face_fields():
    custom_fields = {
        "Employee": [
            {
                "fieldname": "face_registered",
                "label": "Face Registered",
                "fieldtype": "Check",
                "insert_after": "image",
            },
            {
                "fieldname": "face_embeddings",
                "label": "Face Embeddings",
                "fieldtype": "Long Text",
                "insert_after": "face_registered",
            },
            {
                "fieldname": "face_updated_on",
                "label": "Face Updated On",
                "fieldtype": "Datetime",
                "insert_after": "face_embeddings",
            },
            {
                "fieldname": "face_model_version",
                "label": "Face Model Version",
                "fieldtype": "Data",
                "insert_after": "face_updated_on",
            },
            {
                "fieldname": "face_quality_score",
                "label": "Face Quality Score",
                "fieldtype": "Float",
                "insert_after": "face_model_version",
            },
            {
                "fieldname": "face_embedding_count",
                "label": "Face Embedding Count",
                "fieldtype": "Int",
                "insert_after": "face_quality_score",
            },
        ]
    }
    create_custom_fields(custom_fields, update=True)


def execute():
    create_employee_face_fields()

    doctype = "Employee Face Profile"
    fields = [
        {"fieldname": "employee", "label": "Employee", "fieldtype": "Link", "options": "Employee", "reqd": 1},
        {"fieldname": "employee_name", "label": "Employee Name", "fieldtype": "Data"},
        {"fieldname": "user_id", "label": "User ID", "fieldtype": "Data"},
        {"fieldname": "designation", "label": "Designation", "fieldtype": "Data"},
        {"fieldname": "department", "label": "Department", "fieldtype": "Data"},
        {"fieldname": "company", "label": "Company", "fieldtype": "Data"},
        {"fieldname": "shift", "label": "Shift", "fieldtype": "Data"},
        {"fieldname": "face_embedding", "label": "Face Embedding", "fieldtype": "Long Text"},
        {"fieldname": "sample_count", "label": "Sample Count", "fieldtype": "Int"},
        {"fieldname": "is_active", "label": "Is Active", "fieldtype": "Check", "default": "1"},
        {"fieldname": "registered_on", "label": "Registered On", "fieldtype": "Datetime"},
        {"fieldname": "registered_device_id", "label": "Registered Device ID", "fieldtype": "Data"},
        {"fieldname": "last_updated_on", "label": "Last Updated On", "fieldtype": "Datetime"},
    ]

    if not frappe.db.exists("DocType", doctype):
        doc = frappe.get_doc(
            {
                "doctype": "DocType",
                "name": doctype,
                "module": "HR",
                "custom": 1,
                "is_submittable": 0,
                "istable": 0,
                "track_changes": 1,
                "fields": fields,
                "permissions": [
                    {"role": "System Manager", "read": 1, "write": 1, "create": 1, "delete": 1},
                    {"role": "HR Manager", "read": 1, "write": 1, "create": 1, "delete": 1},
                    {"role": "Employee", "read": 1, "write": 0, "create": 0, "delete": 0},
                ],
            }
        )
        doc.insert(ignore_permissions=True)
    else:
        doc = frappe.get_doc("DocType", doctype)
        existing = {field.fieldname for field in doc.fields}
        idx = len(doc.fields)
        changed = False
        for field in fields:
            if field["fieldname"] in existing:
                continue
            idx += 1
            doc.append("fields", {**field, "idx": idx})
            changed = True
        if changed:
            doc.save(ignore_permissions=True)

    frappe.db.commit()
    frappe.clear_cache(doctype=doctype)


execute()
