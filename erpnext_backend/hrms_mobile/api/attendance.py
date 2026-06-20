import json
import math
from datetime import datetime, timedelta, timezone

import frappe
from frappe.utils import add_to_date, date_diff, get_datetime, getdate, now_datetime, today
from hrms_mobile.api.geofence import validate_geofence
from hrms_mobile.utils.device_security import get_active_device
from hrms_mobile.utils.permissions import fail, require_employee_access, success

FACE_THRESHOLD = 80
MAX_GPS_ACCURACY_M = 100
IST = timezone(timedelta(hours=5, minutes=30))


def _log(employee=None, log_type=None, timestamp=None, latitude=None, longitude=None, distance=None, face_match_score=None, device_id=None, app_version=None, status='Failed', failure_reason=None, linked_employee_checkin=None):
	doc = frappe.new_doc('Mobile Attendance Log')
	doc.employee = employee
	doc.log_type = log_type
	doc.checkin_time = timestamp or now_datetime()
	doc.latitude = latitude
	doc.longitude = longitude
	doc.distance_from_site = distance
	doc.face_match_score = face_match_score
	doc.device_id = device_id
	doc.app_version = app_version
	doc.ip_address = getattr(frappe.local, 'request_ip', None)
	doc.status = status
	doc.failure_reason = failure_reason
	doc.linked_employee_checkin = linked_employee_checkin
	doc.flags.ignore_links = True
	doc.insert(ignore_permissions=True)
	return doc


def _ist_date(value=None):
	if value:
		return str(getdate(value))
	return datetime.now(IST).date().isoformat()


def _ist_day_bounds(value=None):
	for_date = _ist_date(value)
	return for_date, f'{for_date} 00:00:00', f'{for_date} 23:59:59'


def _today_checkins(employee, for_date=None):
	day, start, end = _ist_day_bounds(for_date)
	rows = frappe.get_all(
		'Employee Checkin',
		filters={'employee': employee, 'time': ['between', [start, end]]},
		fields=['name', 'employee', 'employee_name', 'log_type', 'time', 'shift', 'device_id', 'skip_auto_attendance'],
		order_by='time asc',
		ignore_permissions=True,
	)
	for row in rows:
		row['for_date'] = day
	return rows


def _resolve_log_type(employee, requested=None):
	if requested:
		return requested
	rows = _today_checkins(employee)
	has_in = any(row.log_type == 'IN' for row in rows)
	has_out = any(row.log_type == 'OUT' for row in rows)
	if not has_in:
		return 'IN'
	if not has_out:
		return 'OUT'
	return None


def _checkin_payload(row):
	return {
		'name': row.get('name'),
		'employee': row.get('employee'),
		'employee_name': row.get('employee_name'),
		'log_type': row.get('log_type'),
		'time': str(row.get('time')) if row.get('time') else None,
		'shift': row.get('shift'),
		'device_id': row.get('device_id'),
		'skip_auto_attendance': row.get('skip_auto_attendance'),
	}


MOBILE_EMPLOYEE_FIELDS = (
	'name',
	'employee_name',
	'user_id',
	'personal_email',
	'company_email',
	'prefered_email',
	'designation',
	'department',
	'company',
	'default_shift',
	'branch',
	'holiday_list',
	'status',
	'image',
	'cell_number',
	'modified',
	'face_registered',
	'face_embeddings',
	'face_updated_on',
	'face_model_version',
	'face_quality_score',
	'face_embedding_count',
)


def _doctype_fields(doctype):
	return {df.fieldname for df in frappe.get_meta(doctype).fields}


def _employee_fields():
	return _doctype_fields('Employee')


def _get_doc_value(doc, fieldname, fields):
	if fieldname not in fields:
		return None
	return doc.get(fieldname) if hasattr(doc, 'get') else getattr(doc, fieldname, None)


def _set_if_field_exists(doc, fieldname, value):
	if value is not None and doc.meta.has_field(fieldname):
		doc.set(fieldname, value)


def _get_employee_doc_for_user(user):
	fields = _employee_fields()
	for fieldname in ('user_id', 'prefered_email', 'company_email', 'personal_email'):
		if fieldname not in fields:
			continue
		employees = frappe.get_all(
			'Employee',
			filters={fieldname: user},
			fields=['name'],
			limit=1,
			ignore_permissions=True,
		)
		if employees:
			return frappe.get_doc('Employee', employees[0].name)
	if frappe.db.exists('Employee', user):
		return frappe.get_doc('Employee', user)
	frappe.throw('Your employee profile is inactive or removed. Please contact HR.')


def _get_logged_employee_doc():
	user = frappe.session.user
	if not user or user == 'Guest':
		frappe.throw('Login required.', frappe.PermissionError)
	return _get_employee_doc_for_user(user)


def _resolve_active_shift_for_mobile(employee):
	fields = _employee_fields()
	default_shift = _get_doc_value(employee, 'default_shift', fields)
	if default_shift:
		return default_shift
	if not frappe.db.exists('DocType', 'Shift Assignment'):
		return None
	current_date = getdate(today())
	assignments = frappe.get_all(
		'Shift Assignment',
		filters={
			'employee': employee.name,
			'status': 'Active',
			'start_date': ['<=', current_date],
		},
		fields=['name', 'shift_type', 'start_date', 'end_date', 'status'],
		order_by='start_date desc, creation desc',
		limit=20,
		ignore_permissions=True,
	)
	for assignment in assignments:
		end_date = assignment.get('end_date')
		if end_date and getdate(end_date) < current_date:
			continue
		if assignment.get('shift_type'):
			return assignment.shift_type
	return None


def _mobile_employee_payload(employee, user=None):
	fields = _employee_fields()
	status = _get_doc_value(employee, 'status', fields) or 'Active'
	active_shift = _resolve_active_shift_for_mobile(employee)
	return {
		'employee_id': employee.name,
		'employee': employee.name,
		'name': employee.name,
		'employee_name': employee.employee_name or employee.name,
		'user_id': _get_doc_value(employee, 'user_id', fields) or user,
		'personal_email': _get_doc_value(employee, 'personal_email', fields),
		'company_email': _get_doc_value(employee, 'company_email', fields),
		'prefered_email': _get_doc_value(employee, 'prefered_email', fields),
		'designation': _get_doc_value(employee, 'designation', fields),
		'department': _get_doc_value(employee, 'department', fields),
		'company': _get_doc_value(employee, 'company', fields),
		'branch': _get_doc_value(employee, 'branch', fields),
		'default_shift': _get_doc_value(employee, 'default_shift', fields),
		'active_shift': active_shift,
		'holiday_list': _get_doc_value(employee, 'holiday_list', fields),
		'status': status,
		'is_active': status == 'Active',
		'image': _get_doc_value(employee, 'image', fields),
		'cell_number': _get_doc_value(employee, 'cell_number', fields),
		'modified': getattr(employee, 'modified', None) or _get_doc_value(employee, 'modified', fields),
		'face_registered': _get_doc_value(employee, 'face_registered', fields) or 0,
		'face_embeddings': _get_doc_value(employee, 'face_embeddings', fields),
		'face_updated_on': _get_doc_value(employee, 'face_updated_on', fields),
		'face_model_version': _get_doc_value(employee, 'face_model_version', fields),
		'face_quality_score': _get_doc_value(employee, 'face_quality_score', fields) or 0,
		'face_embedding_count': _get_doc_value(employee, 'face_embedding_count', fields) or 0,
	}


def _parse_embedding(value, required_message='Face embedding is required.'):
	if isinstance(value, str):
		value = json.loads(value)
	if not isinstance(value, list) or not value:
		frappe.throw(required_message)
	return [float(item) for item in value]


def _average_embeddings(samples):
	length = min(len(sample) for sample in samples)
	values = []
	for idx in range(length):
		values.append(sum(sample[idx] for sample in samples) / len(samples))
	magnitude = math.sqrt(sum(float(item) * float(item) for item in values))
	if not magnitude:
		return values
	return [float(item) / magnitude for item in values]


def _parse_embeddings(value):
	if isinstance(value, str):
		value = json.loads(value)
	if isinstance(value, dict):
		embeddings = value.get('embeddings') or []
		average = value.get('average_embedding') or value.get('averageEmbedding')
	else:
		embeddings = value or []
		average = None
	if not isinstance(embeddings, list) or not embeddings:
		frappe.throw('Face embeddings are required.')
	parsed = []
	for sample in embeddings:
		if not isinstance(sample, list) or not sample:
			continue
		parsed.append([float(item) for item in sample])
	if not parsed:
		frappe.throw('Face embeddings are required.')
	if isinstance(average, list) and average:
		average_embedding = [float(item) for item in average]
	else:
		average_embedding = _average_embeddings(parsed)
	return parsed, average_embedding


def _encode_embeddings(embeddings, average, model_version=None, quality_score=0):
	return json.dumps(
		{
			'embeddings': [
				[round(float(item), 6) for item in sample] for sample in embeddings
			],
			'average_embedding': [round(float(item), 6) for item in average],
			'model_version': model_version,
			'quality_score': float(quality_score or 0),
		}
	)


def _face_profile_payload_from_employee(employee):
	payload = _mobile_employee_payload(employee)
	payload.update(
		{
			'sample_count': payload.get('face_embedding_count') or 0,
			'is_active': 1,
			'registered_on': payload.get('face_updated_on'),
			'registered_device_id': None,
			'last_updated_on': payload.get('face_updated_on'),
		}
	)
	return payload


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


@frappe.whitelist()
def get_logged_employee():
	employee = _get_logged_employee_doc()
	return _mobile_employee_payload(employee, frappe.session.user)


@frappe.whitelist()
def get_my_employee_profile():
	employee = _get_logged_employee_doc()
	return _mobile_employee_payload(employee, frappe.session.user)


@frappe.whitelist()
def get_today_employee_checkins(employee=None, for_date=None):
	logged_employee = _get_logged_employee_doc()
	target_employee = employee or logged_employee.name
	if target_employee != logged_employee.name:
		require_employee_access(target_employee)
	day, _start, _end = _ist_day_bounds(for_date)
	return {
		'employee': target_employee,
		'for_date': day,
		'timezone': 'Asia/Kolkata',
		'checkins': [_checkin_payload(row) for row in _today_checkins(target_employee, day)],
	}


@frappe.whitelist()
def get_mobile_employees(modified_after=None, include_inactive=0):
	fields = _employee_fields()
	selected_fields = [
		field for field in MOBILE_EMPLOYEE_FIELDS if field in fields or field in ('name', 'modified')
	]
	filters = []
	if not int(include_inactive or 0) and 'status' in fields:
		filters.append(['status', '=', 'Active'])
	if modified_after:
		filters.append(['modified', '>', modified_after])
	employees = frappe.get_all(
		'Employee',
		filters=filters,
		fields=selected_fields,
		order_by='modified asc',
		ignore_permissions=True,
	)
	rows = []
	for row in employees:
		doc = frappe._dict(row)
		doc.name = row.get('name')
		rows.append(_mobile_employee_payload(doc))
	return {'employees': rows, 'count': len(rows), 'modified_after': modified_after}


@frappe.whitelist()
def sync_deleted_or_inactive_employees(employee_ids=None):
	if isinstance(employee_ids, str):
		try:
			employee_ids = json.loads(employee_ids)
		except Exception:
			employee_ids = [item.strip() for item in employee_ids.split(',') if item.strip()]
	employee_ids = employee_ids or []
	inactive_or_missing = []
	fields = _employee_fields()
	for employee in employee_ids:
		if not frappe.db.exists('Employee', employee):
			inactive_or_missing.append(employee)
			continue
		status = frappe.db.get_value('Employee', employee, 'status') if 'status' in fields else 'Active'
		if status and status != 'Active':
			inactive_or_missing.append(employee)
	return {'employees_removed': inactive_or_missing, 'count': len(inactive_or_missing)}


@frappe.whitelist()
def get_face_profile(employee=None):
	logged_employee = _get_logged_employee_doc()
	if employee and employee != logged_employee.name:
		require_employee_access(employee)
		target_employee = frappe.get_doc('Employee', employee)
	else:
		target_employee = logged_employee
	fields = _employee_fields()
	if 'face_embeddings' in fields and getattr(target_employee, 'face_embeddings', None):
		return _face_profile_payload_from_employee(target_employee)
	return None


@frappe.whitelist()
def save_employee_face_embeddings(
	employee=None,
	embeddings=None,
	model_version=None,
	quality_score=0,
	**kwargs,
):
	logged_employee = _get_logged_employee_doc()
	if employee and employee != logged_employee.name:
		frappe.throw('You can register only your own employee face.')
	parsed_embeddings, average = _parse_embeddings(
		embeddings or kwargs.get('face_embeddings') or kwargs.get('face_embedding')
	)
	fields = _employee_fields()
	if 'face_embeddings' not in fields:
		frappe.throw('Employee face custom fields are not installed.')
	encoded = _encode_embeddings(
		parsed_embeddings,
		average,
		model_version=model_version,
		quality_score=quality_score,
	)
	employee_doc = frappe.get_doc('Employee', logged_employee.name)
	employee_doc.face_embeddings = encoded
	employee_doc.face_registered = 1
	employee_doc.face_updated_on = now_datetime()
	employee_doc.face_model_version = model_version
	employee_doc.face_quality_score = float(quality_score or 0)
	employee_doc.face_embedding_count = len(parsed_embeddings)
	employee_doc.save(ignore_permissions=True)
	frappe.db.commit()
	frappe.clear_cache(doctype='Employee')
	return _face_profile_payload_from_employee(employee_doc)


@frappe.whitelist()
def remove_employee_face_embeddings(employee=None):
	logged_employee = _get_logged_employee_doc()
	if employee and employee != logged_employee.name:
		frappe.throw('You can remove only your own employee face.')
	fields = _employee_fields()
	if 'face_embeddings' not in fields:
		return {'success': True, 'employee': logged_employee.name}
	employee_doc = frappe.get_doc('Employee', logged_employee.name)
	employee_doc.face_embeddings = None
	employee_doc.face_registered = 0
	employee_doc.face_updated_on = None
	employee_doc.face_model_version = None
	employee_doc.face_quality_score = 0
	employee_doc.face_embedding_count = 0
	employee_doc.save(ignore_permissions=True)
	frappe.db.commit()
	frappe.clear_cache(doctype='Employee')
	return {'success': True, 'employee': employee_doc.name}


@frappe.whitelist()
def save_face_profile(**kwargs):
	embedding = kwargs.get('face_embedding')
	if embedding and not kwargs.get('embeddings'):
		parsed = _parse_embedding(embedding)
		kwargs['embeddings'] = json.dumps(
			{'embeddings': [parsed], 'average_embedding': parsed}
		)
	return save_employee_face_embeddings(**kwargs)


@frappe.whitelist()
def verify_face_profile(face_embedding=None, threshold=0.65):
	logged_employee = _get_logged_employee_doc()
	fields = _employee_fields()
	if 'face_embeddings' not in fields or not getattr(logged_employee, 'face_embeddings', None):
		return {'matched': False, 'message': 'Face not registered.'}
	live = _parse_embedding(face_embedding)
	embeddings, average = _parse_embeddings(logged_employee.face_embeddings)
	candidates = [average] + embeddings
	threshold = float(threshold)
	best_score = max(_cosine_similarity(stored, live) for stored in candidates)
	return {'matched': best_score >= threshold, 'cosine_similarity': best_score, 'threshold': threshold}


@frappe.whitelist()
def mark_employee_checkin(employee=None, log_type=None, time=None, latitude=None, longitude=None, device_id=None, shift=None, **kwargs):
	if not employee:
		frappe.throw('Employee is required')
	if not log_type:
		frappe.throw('Log type is required')

	log_type = str(log_type).upper().strip()
	if log_type not in ('IN', 'OUT'):
		frappe.throw('Log type must be IN or OUT')

	if not frappe.db.exists('Employee', employee):
		frappe.throw(f'Employee not found: {employee}')

	emp_status = frappe.db.get_value('Employee', employee, 'status')
	if emp_status and emp_status != 'Active':
		frappe.throw(f'Employee is not active: {employee}')

	checkin_time = get_datetime(time) if time else now_datetime()
	rows = _today_checkins(employee, getdate(checkin_time))
	has_in = any(row.get('log_type') == 'IN' for row in rows)
	has_out = any(row.get('log_type') == 'OUT' for row in rows)
	if has_in and has_out:
		frappe.throw("Today's attendance completed.")
	if log_type == 'IN' and has_in:
		frappe.throw('Mark In is already recorded today.')
	if log_type == 'OUT' and not has_in:
		frappe.throw('Please Mark In first.')
	if log_type == 'OUT' and has_out:
		frappe.throw('Mark Out is already recorded today.')

	doc = frappe.new_doc('Employee Checkin')
	doc.employee = employee
	doc.log_type = log_type
	doc.time = checkin_time

	_set_if_field_exists(doc, 'shift', shift)
	_set_if_field_exists(doc, 'device_id', device_id)
	_set_if_field_exists(doc, 'custom_device_id', device_id)
	_set_if_field_exists(doc, 'custom_app_device_id', device_id)

	_set_if_field_exists(doc, 'latitude', latitude)
	_set_if_field_exists(doc, 'longitude', longitude)
	_set_if_field_exists(doc, 'custom_latitude', latitude)
	_set_if_field_exists(doc, 'custom_longitude', longitude)
	_set_if_field_exists(doc, 'custom_location', kwargs.get('location') or kwargs.get('address') or f'{latitude}, {longitude}')
	_set_if_field_exists(doc, 'custom_device_time', kwargs.get('device_time') or checkin_time)
	_set_if_field_exists(doc, 'custom_app_source', kwargs.get('app_source') or kwargs.get('source') or 'Brij Dairy HRMS Android App')
	_set_if_field_exists(doc, 'custom_gps_accuracy', kwargs.get('gps_accuracy') or kwargs.get('accuracy'))
	_set_if_field_exists(doc, 'custom_face_verified', kwargs.get('face_verified') if kwargs.get('face_verified') is not None else 1)
	_set_if_field_exists(doc, 'custom_source', kwargs.get('source') or 'Brij Dairy HRMS Android App')

	doc.insert(ignore_permissions=True)
	frappe.db.commit()

	return {
		'success': True,
		'message': f'Marked {log_type} successfully',
		'name': doc.name,
		'employee': employee,
		'log_type': log_type,
		'time': str(doc.time),
	}


@frappe.whitelist()
def mark_attendance(employee=None, log_type=None, timestamp=None, latitude=None, longitude=None, gps_accuracy=None, mock_location=False, device_id=None, face_match_score=None, app_version=None, device_time=None, location=None, app_source=None):
	require_employee_access(employee)
	timestamp = get_datetime(timestamp) if timestamp else now_datetime()
	try:
		if not employee or not frappe.db.exists('Employee', employee):
			raise ValueError('Employee must exist')
		emp = frappe.db.get_value('Employee', employee, ['status', 'employee_name'], as_dict=True)
		if emp.status != 'Active':
			raise ValueError('Employee status must be Active')
		if str(mock_location).lower() in ('1', 'true', 'yes'):
			raise ValueError('Mock location detected')
		if gps_accuracy not in (None, '') and float(gps_accuracy) > MAX_GPS_ACCURACY_M:
			raise ValueError('GPS accuracy is poor. Please try again in open area')
		if not get_active_device(employee, device_id):
			raise ValueError('Device is not registered or approved')
		face = frappe.db.get_value('Employee Face Profile', {'employee': employee, 'enrollment_status': 'Active'}, 'name')
		if not face:
			raise ValueError('Active face profile not found')
		if float(face_match_score or 0) < FACE_THRESHOLD:
			raise ValueError('Face verification failed')
		resolved_log_type = _resolve_log_type(employee, log_type)
		if not resolved_log_type:
			raise ValueError('Attendance already completed for today. Manual approval required')
		duplicate = frappe.db.exists('Employee Checkin', {'employee': employee, 'log_type': resolved_log_type, 'time': ['between', [add_to_date(timestamp, minutes=-2), add_to_date(timestamp, minutes=2)]]})
		if duplicate:
			raise ValueError('Duplicate attendance blocked within 2 minutes')
		fence, distance, geo_error = validate_geofence(employee, latitude, longitude)
		if geo_error:
			raise ValueError(geo_error)
		checkin = frappe.get_doc({'doctype': 'Employee Checkin', 'employee': employee, 'log_type': resolved_log_type, 'time': timestamp, 'device_id': device_id})
		_set_if_field_exists(checkin, 'latitude', latitude)
		_set_if_field_exists(checkin, 'longitude', longitude)
		_set_if_field_exists(checkin, 'custom_latitude', latitude)
		_set_if_field_exists(checkin, 'custom_longitude', longitude)
		_set_if_field_exists(checkin, 'custom_location', location or f'{latitude}, {longitude}')
		_set_if_field_exists(checkin, 'custom_device_time', device_time or timestamp)
		_set_if_field_exists(checkin, 'custom_app_source', app_source or 'Brij Dairy HRMS Android App')
		_set_if_field_exists(checkin, 'custom_app_device_id', device_id)
		_set_if_field_exists(checkin, 'custom_gps_accuracy', gps_accuracy)
		checkin.insert(ignore_permissions=True)
		log = _log(employee, resolved_log_type, timestamp, latitude, longitude, distance, face_match_score, device_id, app_version, 'Success', None, checkin.name)
		frappe.db.commit()
		return success({'employee_checkin': checkin.name, 'attendance_log': log.name, 'log_type': resolved_log_type, 'time': timestamp, 'site': fence.site_name if fence else None, 'distance': distance}, 'Attendance marked')
	except Exception as exc:
		reason = str(exc)
		_log(employee, log_type, timestamp, latitude, longitude, None, face_match_score, device_id, app_version, 'Failed', reason)
		frappe.db.commit()
		return fail(reason)


@frappe.whitelist()
def get_attendance_calendar(employee=None, month=None, year=None):
	require_employee_access(employee)
	if not employee:
		return fail('Employee is required')
	month = int(month or getdate().month)
	year = int(year or getdate().year)
	start = getdate(f'{year}-{month:02d}-01')
	end = add_to_date(start, months=1, days=-1)
	attendance = {str(row.attendance_date): row for row in frappe.get_all('Attendance', filters={'employee': employee, 'attendance_date': ['between', [start, end]]}, fields=['attendance_date', 'status', 'working_hours', 'shift', 'late_entry', 'early_exit'])}
	checkins = frappe.get_all('Employee Checkin', filters={'employee': employee, 'time': ['between', [f'{start} 00:00:00', f'{end} 23:59:59']]}, fields=['time', 'log_type'], order_by='time asc')
	by_date = {}
	for row in checkins:
		key = str(getdate(row.time))
		by_date.setdefault(key, {})['checkin' if row.log_type == 'IN' else 'checkout'] = row.time
	data = []
	for i in range(date_diff(end, start) + 1):
		d = str(add_to_date(start, days=i))
		att = attendance.get(d)
		data.append({'date': d, 'status': att.status if att else '', 'checkin': by_date.get(d, {}).get('checkin'), 'checkout': by_date.get(d, {}).get('checkout'), 'working_hours': att.working_hours if att else None, 'shift': att.shift if att else None, 'late_entry': att.late_entry if att else 0, 'early_exit': att.early_exit if att else 0})
	return success({'calendar': data})
