import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/erp_error.dart';
import '../../shared/widgets/app_logo.dart';
import '../../shared/widgets/powered_by_footer.dart';
import '../auth/login_screen.dart';
import '../home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    final scope = AppScope.of(context);
    final hasSession = await scope.sessionStore.hasSession();
    if (!mounted) return;
    if (!hasSession) {
      _goTo(const LoginScreen());
      return;
    }

    try {
      final data = await scope.repository.loadDashboard();
      if (!mounted) return;
      _goTo(HomeScreen(initialData: data));
    } catch (error) {
      await scope.sessionStore.clear();
      if (!mounted) return;
      _goTo(LoginScreen(initialMessage: friendlyErrorMessage(error)));
    }
  }

  void _goTo(Widget page) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => page),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(22),
          child: Column(
            children: [
              Spacer(),
              AppLogo(size: 86),
              Spacer(),
              PoweredByFooter(),
            ],
          ),
        ),
      ),
    );
  }
}
