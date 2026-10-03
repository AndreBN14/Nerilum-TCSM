import 'package:flutter/material.dart';

import '../theme/nerilum_theme.dart';

class BrandBackdrop extends StatelessWidget {
  const BrandBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.65, 0.28),
          radius: 1.1,
          colors: [colors.glow, colors.background],
          stops: const [0, 0.78],
        ),
      ),
      child: child,
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72, this.showName = true});

  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    return Semantics(
      label: 'Nerilum',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/nerilum-mark-512.png',
            width: size,
            height: size,
            color: Theme.of(context).brightness == Brightness.light
                ? colors.mint
                : null,
            colorBlendMode: BlendMode.srcIn,
            excludeFromSemantics: true,
          ),
          if (showName) ...[
            const SizedBox(height: 8),
            Text(
              'NERILUM',
              style: TextStyle(
                fontSize: size * 0.22,
                fontWeight: FontWeight.w400,
                letterSpacing: size * 0.09,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
