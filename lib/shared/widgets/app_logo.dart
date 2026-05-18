import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({this.size = 72, this.showText = true, super.key});

  final double size;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.secondary],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.28),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Icon(
            Icons.face_retouching_natural_rounded,
            color: Colors.white,
            size: size * 0.48,
          ),
        ),
        if (showText) ...[
          const SizedBox(height: 18),
          Text(
            'FaceAttend HRMS',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Smart. Secure. Seamless.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.faint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
