import 'package:brij_dairy_hrms/shared/widgets/app_logo.dart';
import 'package:brij_dairy_hrms/data/models/dashboard_data.dart';
import 'package:brij_dairy_hrms/data/models/employee.dart';
import 'package:brij_dairy_hrms/data/models/shift_details.dart';
import 'package:brij_dairy_hrms/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Brij Dairy logo renders app name without tagline', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AppLogo())));

    expect(find.text('Brij Dairy HRMS'), findsOneWidget);
    expect(find.text('Red Corporate HRMS'), findsNothing);
  });

  testWidgets('dashboard keeps FaceAttend flow and hides generic HRMS modules', (
    tester,
  ) async {
    final data = DashboardData(
      user: 'abhijeet.jha@thesvsgroup.org',
      employee: const Employee(
        name: 'HR-EMP-00017',
        employeeName: 'Abhijeet Jha',
        userId: 'abhijeet.jha@thesvsgroup.org',
        designation: 'Software Developer',
        company: 'BRIJ VENTURES',
        defaultShift: 'General Shift',
        status: 'Active',
      ),
      shiftDetails: const ShiftDetails(),
      history: const [],
      holidays: const [],
    );

    await tester.pumpWidget(MaterialApp(home: HomeScreen(initialData: data)));

    expect(find.text('Home'), findsWidgets);
    expect(find.text('History'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);
    expect(find.text('Mark In'), findsOneWidget);
    expect(find.text('Update Face'), findsNothing);
    expect(find.text('Face'), findsNothing);
    expect(find.text('Shift & Holidays'), findsOneWidget);
    expect(find.text('Recent Activity'), findsOneWidget);

    for (final hiddenModule in [
      'Leave',
      'Payroll',
      'Notices',
      'Documents',
      'Reports',
      'More',
    ]) {
      expect(find.text(hiddenModule), findsNothing);
    }
  });
}
