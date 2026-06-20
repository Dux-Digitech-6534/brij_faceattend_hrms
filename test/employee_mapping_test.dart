import 'package:brij_dairy_hrms/core/utils/erp_error.dart';
import 'package:brij_dairy_hrms/data/models/employee.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Employee active/inactive mapping', () {
    test('active Employee record is considered active', () {
      final employee = Employee.fromJson({
        'name': 'EMP-0001',
        'employee_name': 'Mohan Kumar',
        'user_id': 'mohan@example.com',
        'status': 'Active',
      });

      expect(employee.isActive, isTrue);
      expect(employee.name, 'EMP-0001');
    });

    test('Brij active Employee maps without optional face fields', () {
      final employee = Employee.fromJson({
        'name': 'HR-EMP-00017',
        'employee_name': 'Abhijeet Jha',
        'user_id': 'abhijeet.jha@thesvsgroup.org',
        'designation': 'Software Developer',
        'company': 'BRIJ VENTURES',
        'status': 'Active',
      });

      expect(employee.isActive, isTrue);
      expect(employee.name, 'HR-EMP-00017');
      expect(employee.userId, 'abhijeet.jha@thesvsgroup.org');
      expect(employee.faceRegistered, isFalse);
    });

    test('inactive Employee record is considered inactive', () {
      final employee = Employee.fromJson({
        'name': 'EMP-0002',
        'employee_name': 'Inactive User',
        'status': 'Inactive',
      });

      expect(employee.isActive, isFalse);
    });

    test('missing linked Employee message is distinct from inactive', () {
      final message = friendlyErrorMessage(
        const ErpError('No employee is mapped for this user'),
      );

      expect(message, noLinkedEmployeeMessage);
      expect(message, isNot(contains('inactive')));
    });

    test('inactive message is used only for inactive employees', () {
      final message = friendlyErrorMessage(
        const ErpError('Employee is not active'),
      );

      expect(message, 'Employee is inactive');
    });

    test('missing custom backend method is detectable for REST fallback', () {
      expect(
        isServerMethodMissingError(
          const ErpError('App faceattend_hrms is not installed'),
        ),
        isTrue,
      );
    });
  });
}
