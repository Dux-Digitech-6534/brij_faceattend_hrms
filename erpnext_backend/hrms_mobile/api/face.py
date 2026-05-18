import json
import math

import frappe
from frappe.utils import now

from hrms_mobile.api.employee import get_logged_employee_doc


DOCTYPE = "Employee Face Profile"


def _parse_embedding(value):
    if isinstance(value, str):
        value = json.loads(value)
    if not isinstance(value, list) or not value:
        frappe.throw("Face embedding is required.")
    return [float(item) for item in value]


def _encode_embedding(value):
    return json.dumps([round(float(item), 6) for item in value])


def _profile_payload(profile):
    if not profile:
        return None
    return {
        "name": profile.name,
        "employee": profile.employee,
        "employee_name": profile.employee_name,
        "user_id": profile.user_id,
        "designation": profile.designation,
        "department": profile.department,
        "company": profile.company,
        "shift": profile.shift,
        "face_embedding": profile.face_embedding,
        "sample_count": profile.sample_count,
        "is_active": profile.is_active,
        "registered_on": profile.registered_on,
        "registered_device_id": profile.registered_device_id,
        "last_updated_on": profile.last_updated_on,
    }


def _get_active_profile_name(employee_name):
    profiles = frappe.get_all(
        DOCTYPE,
        filters={"employee": employee_name, "is_active": 1},
        fields=["name"],
        order_by="modified desc",
        limit=1,
        ignore_permissions=True,
    )
    return profiles[0].name if profiles else None


@frappe.whitelist()
def get_face_profile(employee=None):
    logged_employee = get_logged_employee_doc()
    profile_name = _get_active_profile_name(logged_employee.name)
    if not profile_name:
        return None
    return _profile_payload(frappe.get_doc(DOCTYPE, profile_name))


@frappe.whitelist()
def save_face_profile(**kwargs):
    logged_employee = get_logged_employee_doc()
    embedding = _parse_embedding(kwargs.get("face_embedding"))
    profile_name = _get_active_profile_name(logged_employee.name)

    if profile_name:
        profile = frappe.get_doc(DOCTYPE, profile_name)
    else:
        profile = frappe.new_doc(DOCTYPE)
        profile.employee = logged_employee.name
        profile.registered_on = now()

    profile.employee = logged_employee.name
    profile.employee_name = logged_employee.employee_name or logged_employee.name
    profile.user_id = frappe.session.user
    profile.designation = getattr(logged_employee, "designation", None)
    profile.department = getattr(logged_employee, "department", None)
    profile.company = getattr(logged_employee, "company", None)
    profile.shift = getattr(logged_employee, "default_shift", None)
    profile.face_embedding = _encode_embedding(embedding)
    profile.sample_count = int(kwargs.get("sample_count") or len(embedding))
    profile.is_active = 1
    profile.registered_device_id = kwargs.get("device_id") or kwargs.get("registered_device_id")
    profile.last_updated_on = now()
    profile.save(ignore_permissions=True)
    frappe.db.commit()
    return _profile_payload(profile)


@frappe.whitelist()
def verify_face_profile(face_embedding=None, threshold=0.75):
    logged_employee = get_logged_employee_doc()
    profile_name = _get_active_profile_name(logged_employee.name)
    if not profile_name:
        return {"matched": False, "message": "Face not registered."}

    live = _parse_embedding(face_embedding)
    profile = frappe.get_doc(DOCTYPE, profile_name)
    stored = _parse_embedding(profile.face_embedding)
    score = _cosine_similarity(stored, live)
    threshold = float(threshold)
    return {
        "matched": score >= threshold,
        "cosine_similarity": score,
        "threshold": threshold,
    }


def _cosine_similarity(a, b):
    length = min(len(a), len(b))
    if not length:
        return 0
    dot = sum(a[i] * b[i] for i in range(length))
    mag_a = math.sqrt(sum(a[i] * a[i] for i in range(length)))
    mag_b = math.sqrt(sum(b[i] * b[i] for i in range(length)))
    if not mag_a or not mag_b:
        return 0
    return dot / (mag_a * mag_b)

