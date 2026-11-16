import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/clay_theme.dart';
import 'app_logo.dart';

/// Opening animation: the logo pops in with a radar sweep circling it,
/// then the name and tagline fade up.
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: Duration(milliseconds: 1300))..forward();
    _spin = AnimationController(vsync: this, duration: Duration(milliseconds: 1600))..repeat();
  }

  @override
  void dispose() {
    _intro.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logoScale = CurvedAnimation(parent: _intro, curve: Interval(0.0, 0.6, curve: Curves.elasticOut));
    final textFade = CurvedAnimation(parent: _intro, curve: Interval(0.45, 1.0, curve: Curves.easeOut));
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _spin,
                    builder: (_, __) => CustomPaint(
                      size: Size(220, 220),
                      painter: _SweepRingPainter(_spin.value),
                    ),
                  ),
                  ScaleTransition(scale: logoScale, child: AppLogo(size: 130)),
                ],
              ),
            ),
            SizedBox(height: 18),
            FadeTransition(
              opacity: textFade,
              child: SlideTransition(
                position: Tween<Offset>(begin: Offset(0, 0.4), end: Offset.zero).animate(textFade),
                child: Column(
                  children: [
                    Text('EchoSweep',
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: ClayColors.textPrimary)),
                    SizedBox(height: 4),
                    Text('Your room, on radar.',
                        style: TextStyle(fontSize: 15, color: ClayColors.primary, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SweepRingPainter extends CustomPainter {
  final double t;
  _SweepRingPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final ring = Paint()
      ..color = ClayColors.primary.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(c, r, ring);
    canvas.drawCircle(c, r * 0.82, ring);
    final start = t * 2 * math.pi;
    final rect = Rect.fromCircle(center: c, radius: r);
    for (int i = 0; i < 12; i++) {
      canvas.drawArc(rect, start - i * 0.07, 0.07, false, Paint()
        ..color = Color(0xFF4ECCA3).withOpacity(0.9 * (1 - i / 12))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(covariant _SweepRingPainter old) => old.t != t;
}
