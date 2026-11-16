import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/radar_reading.dart';
import '../services/bluetooth_service.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';

/// Live radar sweep view, fed straight from the Bluetooth line stream.
class RadarScreen extends StatefulWidget {
  final RadarBluetoothService bluetooth;
  const RadarScreen({super.key, required this.bluetooth});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  RadarReading? _latest;

  @override
  void initState() {
    super.initState();
    widget.bluetooth.lines.listen((line) {
      final reading = RadarReading.parse(line);
      if (reading != null && mounted) setState(() => _latest = reading);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          ClayContainer(
            padding: const EdgeInsets.all(12),
            child: AspectRatio(
              aspectRatio: 1.6,
              child: CustomPaint(
                painter: _RadarPainter(reading: _latest),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ClayContainer(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat('Angle', _latest != null ? '${_latest!.angle}°' : '--'),
                _stat('Distance', _latest != null && _latest!.distanceCm > 0 ? '${_latest!.distanceCm} cm' : '--'),
                _stat('Status', _latest?.alert == true ? 'ALERT' : 'OK',
                    color: _latest?.alert == true ? ClayColors.danger : ClayColors.success),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: ClayColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color ?? ClayColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  final RadarReading? reading;
  _RadarPainter({required this.reading});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height;
    final maxR = math.min(size.width / 2, size.height) - 10;

    final ringPaint = Paint()
      ..color = ClayColors.primary.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (double r = maxR / 4; r <= maxR; r += maxR / 4) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        math.pi,
        math.pi,
        false,
        ringPaint,
      );
    }

    for (int a = 0; a <= 180; a += 30) {
      final rad = math.pi - (a * math.pi / 180);
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + maxR * math.cos(rad), cy - maxR * math.sin(rad)),
        ringPaint,
      );
    }

    if (reading == null) return;

    final sweepColor = reading!.alert ? ClayColors.danger : ClayColors.primary;
    final sweepPaint = Paint()
      ..color = sweepColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final rad = math.pi - (reading!.angle * math.pi / 180);
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + maxR * math.cos(rad), cy - maxR * math.sin(rad)),
      sweepPaint,
    );

    if (reading!.distanceCm > 0 && reading!.distanceCm <= 200) {
      final r = (reading!.distanceCm / 200) * maxR;
      canvas.drawCircle(
        Offset(cx + r * math.cos(rad), cy - r * math.sin(rad)),
        5,
        Paint()..color = sweepColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => true;
}
