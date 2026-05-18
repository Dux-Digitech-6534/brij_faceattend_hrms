import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/app_logo.dart';
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
      _goTo(LoginScreen(initialMessage: '$error'));
    }
  }

  void _goTo(Widget page) {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: AppLogo(size: 86)),
    );
  }
}
