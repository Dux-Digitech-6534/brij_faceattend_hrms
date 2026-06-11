import json
import math

import frappe
from frappe.utils import now

from hrms_mobile.api.employee import get_logged_employee_doc, resolve_active_shift


DOCTYPE = "Employee Face Profile"


def _employee_fieldnames():
    return {df.fieldname for df in frappe.get_meta("Employee").fields}


def _parse_embeddings(value):
    if isinstance(value, str):
        value = json.loads(value)
    if isinstance(value, dict):
        embeddings = value.get("embeddings") or []
        average = value.get("average_embedding") or value.get("averageEmbedding")
    else:
        embeddings = value or []
        average = None

    if not isinstance(embeddings, list) or not embeddings:
        frappe.throw("Face embeddings are required.")

    parsed = []
    for sample in embeddings:
        if not isinstance(sample, list) or not sample:
            continue
        parsed.append([float(item) for item in sample])
    if not parsed:
        frappe.throw("Face embeddings are required.")

    if isinstance(average, list) and average:
        avg = [float(item) for item in average]
    else:
        avg = _average_embeddings(parsed)
    return parsed, avg


def _parse_embedding(value):
    if isinstance(value, str):
        value = json.loads(value)
    if not isinstance(value, list) or not value:
        frappe.throw("Face embedding is required.")
    return [float(item) for item in value]


def _average_embeddings(samples):
    length = min(len(sample) for sample in samples)
    values = []
    for idx in range(length):
        values.append(sum(sample[idx] for sample in samples) / len(samples))
    return _l2_normalize(values)


def _l2_normalize(values):
    magnitude = math.sqrt(sum(float(item) * float(item) for item in values))
    if not magnitude:
        return values
    return [float(item) / magnitude for item in values]


def _encode_embeddings(embeddings, average, model_version=None, quality_score=0):
    return json.dumps(
        {
            "embeddings": [
                [round(float(item), 6) for item in sample] for sample in embeddings
            ],
            "average_embedding": [round(float(item), 6) for item in average],
            "model_version": model_version,
            "quality_score": float(quality_score or 0),
        }
    )


def _profile_payload_from_employee(employee):
    fields = _employee_fieldnames()
    payload = {
        "name": employee.name,
        "employee": employee.name,
        "employee_name": employee.employee_name or employee.name,
        "user_id": getattr(employee, "user_id", None) or frappe.session.user,
        "designation": getattr(employee, "designation", None),
        "department": getattr(employee, "department", None),
        "company": getattr(employee, "company", None),
        "shift": resolve_active_shift(employee),
        "sample_count": 0,
        "is_active": 1,
        "registered_on": None,
        "registered_device_id": None,
        "last_updated_on": None,
    }
    for fieldname in (
        "face_registered",
        "face_embeddings",
        "face_updated_on",
        "face_model_version",
        "face_quality_score",
        "face_embedding_count",
    ):
        payload[fieldname] = getattr(employee, fieldname, None) if fieldname in fields else None

    payload["sample_count"] = payload.get("face_embedding_count") or 0
    payload["registered_on"] = payload.get("face_updated_on")
    payload["last_updated_on"] = payload.get("face_updated_on")
    return payload


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
    if not frappe.db.exists("DocType", DOCTYPE):
        return None
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
    fields = _employee_fieldnames()
    if "face_embeddings" in fields and getattr(logged_employee, "face_embeddings", None):
        return _profile_payload_from_employee(logged_employee)

    profile_name = _get_active_profile_name(logged_employee.name)
    if not profile_name:
        return None
    return _profile_payload(frappe.get_doc(DOCTYPE, profile_name))


@frappe.whitelist()
def save_employee_face_embeddings(
    employee=None,
    embeddings=None,
    model_version=None,
    quality_score=0,
    **kwargs,
):
    logged_employee = get_logged_employee_doc()
    if employee and employee != logged_employee.name:
        frappe.throw("You can register only your own employee face.")

    parsed_embeddings, average = _parse_embeddings(
        embeddings or kwargs.get("face_embeddings") or kwargs.get("face_embedding")
    )
    fields = _employee_fieldnames()
    if "face_embeddings" not in fields:
        frappe.throw("Employee face custom fields are not installed.")

    encoded = _encode_embeddings(
        parsed_embeddings,
        average,
        model_version=model_version,
        quality_score=quality_score,
    )
    employee_doc = frappe.get_doc("Employee", logged_employee.name)
    employee_doc.face_embeddings = encoded
    employee_doc.face_registered = 1
    employee_doc.face_updated_on = now()
    employee_doc.face_model_version = model_version
    employee_doc.face_quality_score = float(quality_score or 0)
    employee_doc.face_embedding_count = len(parsed_embeddings)
    employee_doc.save(ignore_permissions=True)
    frappe.db.commit()
    frappe.clear_cache(doctype="Employee")
    return _profile_payload_from_employee(employee_doc)


@frappe.whitelist()
def remove_employee_face_embeddings(employee=None):
    logged_employee = get_logged_employee_doc()
    if employee and employee != logged_employee.name:
        frappe.throw("You can remove only your own employee face.")

    fields = _employee_fieldnames()
    if "face_embeddings" not in fields:
        return {"success": True, "employee": logged_employee.name}

    employee_doc = frappe.get_doc("Employee", logged_employee.name)
    employee_doc.face_embeddings = None
    employee_doc.face_registered = 0
    employee_doc.face_updated_on = None
    employee_doc.face_model_version = None
    employee_doc.face_quality_score = 0
    employee_doc.face_embedding_count = 0
    employee_doc.save(ignore_permissions=True)
    frappe.db.commit()
    frappe.clear_cache(doctype="Employee")
    return {"success": True, "employee": employee_doc.name}


@frappe.whitelist()
def save_face_profile(**kwargs):
    embedding = kwargs.get("face_embedding")
    if embedding and not kwargs.get("embeddings"):
        parsed = _parse_embedding(embedding)
        kwargs["embeddings"] = json.dumps(
            {"embeddings": [parsed], "average_embedding": parsed}
        )
    return save_employee_face_embeddings(**kwargs)


@frappe.whitelist()
def verify_face_profile(face_embedding=None, threshold=0.65):
    logged_employee = get_logged_employee_doc()
    fields = _employee_fieldnames()
    if "face_embeddings" not in fields or not getattr(logged_employee, "face_embeddings", None):
        return {"matched": False, "message": "Face not registered."}

    live = _parse_embedding(face_embedding)
    embeddings, average = _parse_embeddings(logged_employee.face_embeddings)
    candidates = [average] + embeddings
    threshold = float(threshold)
    best_score = max(_cosine_similarity(stored, live) for stored in candidates)
    return {
        "matched": best_score >= threshold,
        "cosine_similarity": best_score,
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
