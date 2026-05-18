import 'package:faceattend_hrms/shared/widgets/app_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FaceAttend logo renders app name and tagline', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AppLogo())));

    expect(find.text('FaceAttend HRMS'), findsOneWidget);
    expect(find.text('Smart. Secure. Seamless.'), findsOneWidget);
  });
}
