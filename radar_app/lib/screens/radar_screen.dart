import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/radar_reading.dart';
import '../services/bluetooth_service.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';

/// One echo the sensor saw, kept for a few seconds so it can fade out.
class _Blip {
  final double angle;
  final int distanceCm;
  final bool alert;
  final DateTime seenAt;
  _Blip(this.angle, this.distanceCm, this.alert, this.seenAt);
}

/// Live radar: a dark scope with a glowing sweep beam that follows the
/// servo in real time, and echoes that stay on screen and fade out like a
/// real radar's phosphor trail.
class RadarScreen extends StatefulWidget {
  final RadarBluetoothService bluetooth;
  const RadarScreen({super.key, required this.bluetooth});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with SingleTickerProviderStateMixin {
  static const int maxRangeCm = 200;
  static const Duration fadeTime = Duration(seconds: 4);

  late final AnimationController _ticker;
  StreamSubscription<String>? _sub;
  RadarReading? _latest;
  final List<_Blip> _blips = [];
  DateTime? _lastReadingAt;
  int? _nearestCm;

  @override
  void initState() {
    super.initState();
    // Repaints ~60 times a second so the fade looks smooth even between readings.
    _ticker = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _sub = widget.bluetooth.lines.listen(_onLine);
  }

  void _onLine(String line) {
    final r = RadarReading.parse(line);
    if (r == null || !mounted) return;
    final now = DateTime.now();
    _latest = r;
    _lastReadingAt = now;
    if (r.distanceCm > 0 && r.distanceCm <= maxRangeCm) {
      _blips.add(_Blip(r.angle.toDouble(), r.distanceCm, r.alert, now));
    }
    _blips.removeWhere((b) => now.difference(b.seenAt) > fadeTime);
    _nearestCm = _blips.isEmpty ? null : _blips.map((b) => b.distanceCm).reduce(math.min);
    setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  bool get _live => _lastReadingAt != null && DateTime.now().difference(_lastReadingAt!) < const Duration(seconds: 2);

  @override
  Widget build(BuildContext context) {
    final alert = _latest?.alert == true;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ClayContainer(
          padding: const EdgeInsets.all(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              color: const Color(0xFF0B1220),
              child: AspectRatio(
                aspectRatio: 1.7,
                child: AnimatedBuilder(
                  animation: _ticker,
                  builder: (context, _) => CustomPaint(
                    painter: _ScopePainter(
                      angle: _latest?.angle.toDouble(),
                      alert: alert,
                      blips: List.of(_blips),
                      now: DateTime.now(),
                      fadeTime: fadeTime,
                      maxRangeCm: maxRangeCm,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.circle, size: 10, color: _live ? ClayColors.success : ClayColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              _live ? 'LIVE' : 'Waiting for the radar...',
              style: TextStyle(
                color: _live ? ClayColors.success : ClayColors.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _statCard('Angle', _latest != null ? '${_latest!.angle}°' : '--', Icons.explore_outlined)),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                'Distance',
                _latest != null && _latest!.distanceCm > 0 ? '${_latest!.distanceCm} cm' : '--',
                Icons.straighten,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _statCard('Nearest', _nearestCm != null ? '$_nearestCm cm' : '--', Icons.my_location)),
            const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                'Status',
                _latest == null ? '--' : (alert ? 'ALERT' : 'Clear'),
                alert ? Icons.warning_amber_rounded : Icons.verified_outlined,
                color: _latest == null ? null : (alert ? ClayColors.danger : ClayColors.success),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, {Color? color}) {
    return ClayContainer(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: color ?? ClayColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: ClayColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(color: color ?? ClayColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopePainter extends CustomPainter {
  final double? angle;
  final bool alert;
  final List<_Blip> blips;
  final DateTime now;
  final Duration fadeTime;
  final int maxRangeCm;

  _ScopePainter({
    required this.angle,
    required this.alert,
    required this.blips,
    required this.now,
    required this.fadeTime,
    required this.maxRangeCm,
  });

  static const _green = Color(0xFF4ECCA3);
  static const _red = Color(0xFFFF6B6B);

  Offset _point(Offset c, double radius, double deg) {
    final rad = math.pi - deg * math.pi / 180;
    return Offset(c.dx + radius * math.cos(rad), c.dy - radius * math.sin(rad));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height - 14);
    final maxR = math.min(size.width / 2 - 12, size.height - 26);

    final grid = Paint()
      ..color = _green.withOpacity(0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Range rings with labels
    for (int i = 1; i <= 4; i++) {
      final r = maxR * i / 4;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), math.pi, math.pi, false, grid);
      final tp = TextPainter(
        text: TextSpan(
          text: '${(maxRangeCm * i / 4).round()}',
          style: TextStyle(color: _green.withOpacity(0.55), fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(c.dx + r - tp.width - 2, c.dy - tp.height - 1));
    }
    // Angle spokes
    for (int a = 0; a <= 180; a += 30) {
      canvas.drawLine(c, _point(c, maxR, a.toDouble()), grid);
    }
    canvas.drawLine(Offset(c.dx - maxR, c.dy), Offset(c.dx + maxR, c.dy), grid);

    final beamColor = alert ? _red : _green;

    // Sweep beam with a glowing trailing wedge
    if (angle != null) {
      const trailDeg = 22.0;
      // Draw trail slices (degrees behind the beam, fading)
      for (int i = 0; i < 16; i++) {
        final behind = angle! + (i + 1) * (trailDeg / 16);
        final opacity = 0.28 * (1 - i / 16);
        final path = Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(_point(c, maxR, behind).dx, _point(c, maxR, behind).dy)
          ..lineTo(_point(c, maxR, behind - trailDeg / 16).dx, _point(c, maxR, behind - trailDeg / 16).dy)
          ..close();
        canvas.drawPath(path, Paint()..color = beamColor.withOpacity(opacity));
      }

      canvas.drawLine(
        c,
        _point(c, maxR, angle!),
        Paint()
          ..color = beamColor
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }

    // Echoes, fading with age
    final fadeMs = fadeTime.inMilliseconds;
    for (final b in blips) {
      final age = now.difference(b.seenAt).inMilliseconds;
      if (age > fadeMs) continue;
      final life = 1 - age / fadeMs;
      final p = _point(c, maxR * b.distanceCm / maxRangeCm, b.angle);
      final color = b.alert ? _red : _green;
      canvas.drawCircle(p, 9 * life + 2, Paint()..color = color.withOpacity(0.18 * life));
      canvas.drawCircle(p, 3.5, Paint()..color = color.withOpacity(0.25 + 0.75 * life));
    }

    canvas.drawCircle(c, 4, Paint()..color = _green);
  }

  @override
  bool shouldRepaint(covariant _ScopePainter oldDelegate) => true;
}
