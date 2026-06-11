import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
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
          width: size * 2.7,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.28),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              'assets/icons/dux_logo.jpg',
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.face_retouching_natural_rounded,
                color: AppColors.primary,
                size: size * 0.48,
              ),
            ),
          ),
        ),
        if (showText) ...[
          const SizedBox(height: 18),
          Text(
            AppConfig.appName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppConfig.tagline,
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
