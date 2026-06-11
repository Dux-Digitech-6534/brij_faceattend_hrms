const inactiveEmployeeMessage =
    'Your employee profile is inactive or removed. Please contact HR.';

class ErpError implements Exception {
  const ErpError(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

bool isInactiveEmployeeError(Object error) {
  return error.toString() == inactiveEmployeeMessage;
}

String friendlyErrorMessage(
  Object? error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error == null) return fallback;
  if (error is ErpError) return error.message;

  final raw = error.toString().trim();
  if (raw.isEmpty) return fallback;
  final message = raw.toLowerCase();

  if (message.contains('failed to get method') ||
      message.contains('has no attribute') ||
      message.contains('attributeerror') ||
      message.contains('importerror')) {
    return 'Server method missing. Please restart ERPNext backend.';
  }
  if (message.contains('employee not found') ||
      message.contains('no employee is mapped')) {
    return 'Employee not found';
  }
  if (message.contains('employee is inactive') ||
      message.contains('employee is not active') ||
      message.contains('inactive or removed')) {
    return 'Employee is inactive';
  }
  if (message.contains('face not matched') ||
      message.contains('face verification failed')) {
    return 'Face not matched';
  }
  if (message.contains('socketexception') ||
      message.contains('connection timed out') ||
      message.contains('connection timeout') ||
      message.contains('receive timeout') ||
      message.contains('send timeout') ||
      message.contains('connection error') ||
      message.contains('network')) {
    return 'Network error. Please try again.';
  }
  if (message.contains('traceback') ||
      message.contains('frappe.exceptions') ||
      message.contains('validationerror:') ||
      message.contains('server error')) {
    return fallback;
  }

  return raw.replaceFirst('Exception: ', '');
}
