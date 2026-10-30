import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/theme/nerilum_theme.dart';
import '../widgets/brand_backdrop.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_animation.isAnimating || _animation.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToWelcome());
    } else {
      _animation.forward().then((_) => _goToWelcome());
    }
  }

  void _goToWelcome() {
    if (!mounted) return;
    final session = AppScope.of(context).accountRepository.currentAccount;
    Navigator.of(context)
        .pushReplacementNamed(session == null ? '/welcome' : '/app');
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BrandBackdrop(
        child: SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, _) {
                final progress = _animation.value;
                final appear = (progress / 0.1).clamp(0.0, 1.0);
                final reveal = ((progress - 0.1) / 0.35).clamp(0.0, 1.0);
                final exit = (1 - (progress - 0.82) / 0.18).clamp(0.0, 1.0);
                return Opacity(
                  opacity: appear * exit,
                  child: Semantics(
                    label: 'Nerilum',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: 0.96 + 0.04 * appear,
                          child: Image.asset(
                            'assets/nerilum-mark-512.png',
                            width: 112,
                            height: 112,
                            color:
                                Theme.of(context).brightness == Brightness.light
                                ? NerilumPalette.of(context).mint
                                : null,
                            colorBlendMode: BlendMode.srcIn,
                            excludeFromSemantics: true,
                          ),
                        ),
                        ClipRect(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: reveal,
                            child: const Padding(
                              padding: EdgeInsets.only(left: 12),
                              child: Text(
                                'NERILUM',
                                style: TextStyle(
                                  fontSize: 24,
                                  letterSpacing: 4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
