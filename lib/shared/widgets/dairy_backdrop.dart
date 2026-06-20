import 'package:flutter/material.dart';

class DairyBackdrop extends StatelessWidget {
  const DairyBackdrop({
    this.alignment = Alignment.bottomCenter,
    this.opacity = 0.14,
    super.key,
  });

  final Alignment alignment;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Opacity(
          opacity: opacity,
          child: Image.asset(
            'assets/icons/dairy_plant_graphic.png',
            width: double.infinity,
            fit: BoxFit.fitWidth,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
