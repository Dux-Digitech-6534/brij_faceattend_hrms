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
          width: size * 1.55,
          height: size * 1.15,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.16),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/icons/brij_logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.local_drink_rounded,
                color: AppColors.primary,
                size: size * 0.48,
              ),
            ),
          ),
        ),
        if (showText) ...[
          const SizedBox(height: 14),
          Text(
            AppConfig.appName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
              color: AppColors.primary,
            ),
          ),
        ],
      ],
    );
  }
}
