import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/clay_theme.dart';

/// The EchoSweep logo, drawn in code so it stays sharp at any size and
/// matches the launcher icon in branding/logo.png.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.225),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6C63FF), Color(0xFF4034BE)],
          ),
          boxShadow: [
            BoxShadow(color: ClayColors.shadowDark, offset: Offset(6, 6), blurRadius: 14),
            BoxShadow(color: ClayColors.shadowLight, offset: Offset(-6, -6), blurRadius: 14),
          ],
        ),
        child: CustomPaint(painter: _LogoPainter()),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s * 0.70);
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.025
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: s * 0.37),
      -75 * math.pi / 180,
      40 * math.pi / 180,
      true,
      Paint()..color = const Color(0xFF4ECCA3).withOpacity(0.35),
    );
    for (final r in [0.127, 0.249, 0.371]) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: s * r), math.pi, math.pi, false, white);
    }
    canvas.drawLine(Offset(s * 0.11, c.dy), Offset(s * 0.89, c.dy), white);
    final a = -35 * math.pi / 180;
    canvas.drawLine(
      c,
      Offset(c.dx + s * 0.37 * math.cos(a), c.dy + s * 0.37 * math.sin(a)),
      Paint()
        ..color = const Color(0xFF4ECCA3)
        ..strokeWidth = s * 0.03
        ..strokeCap = StrokeCap.round,
    );
    final b = -55 * math.pi / 180;
    canvas.drawCircle(
      Offset(c.dx + s * 0.29 * math.cos(b), c.dy + s * 0.29 * math.sin(b)),
      s * 0.037,
      Paint()..color = ClayColors.danger,
    );
    canvas.drawCircle(c, s * 0.033, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
