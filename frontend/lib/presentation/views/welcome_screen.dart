import 'package:flutter/material.dart';

import '../../core/theme/nerilum_theme.dart';
import '../widgets/brand_backdrop.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final colors = NerilumPalette.of(context);
    return Scaffold(
      body: BrandBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            children: [
                              Text(
                                'Explora imágenes\ncerebrales',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      height: 1.15,
                                    ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Una herramienta académica\nde análisis orientativo.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.4,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(
                                begin: reducedMotion ? 1 : 0,
                                end: 1,
                              ),
                              duration: reducedMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 550),
                              builder: (context, value, child) => Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, (1 - value) * 8),
                                  child: child,
                                ),
                              ),
                              child: ExcludeSemantics(
                                child: Image.asset(
                                  'assets/nerilum-welcome-hero.png',
                                  height: (constraints.maxHeight * 0.47).clamp(
                                    210.0,
                                    420.0,
                                  ),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.pushNamed(context, '/register'),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Center(child: Text('Comenzar')),
                                    ),
                                    Icon(Icons.arrow_forward),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () =>
                                    Navigator.pushNamed(context, '/login'),
                                child: const Text(
                                  'Ya tengo cuenta',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
