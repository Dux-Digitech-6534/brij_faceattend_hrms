import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';

class PoweredByFooter extends StatelessWidget {
  const PoweredByFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      AppConfig.poweredBy,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppColors.faint,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }
}
