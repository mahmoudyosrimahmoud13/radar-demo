import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/clay_theme.dart';
import 'clay_container.dart';

/// Module ids used for highlighting: 'display', 'servo', 'buzzer',
/// 'sonar', 'relay', 'hc05', 'resetcap', 'power'.
class _Pin {
  final String name; // label on the module
  final String target; // Uno pin ('D7', 'A0', 'RESET') or a rail: '5V', '3.3V', 'GND', 'NC'
  final String? note; // e.g. 'via 1k/2k divider'
  const _Pin(this.name, this.target, [this.note]);
}

class _Module {
  final String id;
  final String title;
  final String subtitle;
  final Rect rect;
  final Color color;
  final List<_Pin> pins;
  const _Module(this.id, this.title, this.subtitle, this.rect, this.color, this.pins);
}

const _modules = <_Module>[
  _Module('display', '7-segment', 'each segment via 220Ω', Rect.fromLTWH(10, 40, 170, 120), Color(0xFFFFB84C), [
    _Pin('a', 'D2'), _Pin('b', 'D3'), _Pin('c', 'D12'), _Pin('d', 'D13'),
    _Pin('e', 'A0'), _Pin('f', 'A1'), _Pin('g', 'A2'), _Pin('COM', 'GND'),
  ]),
  _Module('servo', 'Servo', 'SG90', Rect.fromLTWH(350, 40, 95, 120), Color(0xFFAB47BC), [
    _Pin('SIG', 'D9'), _Pin('+', '5V'), _Pin('−', 'GND'),
  ]),
  _Module('buzzer', 'Buzzer', 'optional', Rect.fromLTWH(460, 40, 80, 120), Color(0xFFEF5350), [
    _Pin('+', 'D8'), _Pin('−', 'GND'),
  ]),
  _Module('sonar', 'HC-SR04', 'ultrasonic', Rect.fromLTWH(555, 40, 125, 120), Color(0xFF66BB6A), [
    _Pin('VCC', '5V'), _Pin('TRIG', 'D7'), _Pin('ECHO', 'D6'), _Pin('GND', 'GND'),
  ]),
  _Module('relay', 'Relay', 'module', Rect.fromLTWH(695, 40, 100, 120), Color(0xFF8D6E63), [
    _Pin('IN', 'D5'), _Pin('VCC', '5V'), _Pin('GND', 'GND'),
  ]),
  _Module('hc05', 'HC-05', 'Bluetooth, 6-pin board', Rect.fromLTWH(810, 40, 180, 120), Color(0xFF5C6BC0), [
    _Pin('TXD', 'D0'), _Pin('RXD', 'D1', '1k/2k divider'), _Pin('VCC', '5V'), _Pin('GND', 'GND'), _Pin('EN', 'NC'),
  ]),
];

/// The Uno, drawn like the real board: digital header along the top
/// (D13 on the left .. D0 on the right), power + analog along the bottom.
const _unoRect = Rect.fromLTWH(300, 360, 420, 230);

Offset _unoPin(String name) {
  final top = _unoRect.top;
  final bottom = _unoRect.bottom;
  if (name.startsWith('D')) {
    final n = int.parse(name.substring(1));
    return Offset(_unoRect.right - 24 - n * 27.0, top);
  }
  const bottomPins = ['RESET', '3.3V', '5V', 'GND', 'VIN', '', 'A0', 'A1', 'A2', 'A3', 'A4', 'A5'];
  final i = bottomPins.indexOf(name);
  return Offset(_unoRect.left + 30 + i * 32.0, bottom);
}

Color _railColor(String rail) {
  switch (rail) {
    case '5V':
      return const Color(0xFFE53935);
    case '3.3V':
      return const Color(0xFFFF9800);
    case 'GND':
      return const Color(0xFF616161);
    default:
      return const Color(0xFF9E9E9E);
  }
}

class WiringDiagramPainter extends CustomPainter {
  final Set<String> highlight; // empty = everything bright
  final bool dark;
  WiringDiagramPainter({required this.highlight, required this.dark});

  static const Size canvasSize = Size(1000, 800);

  bool _on(String id) => highlight.isEmpty || highlight.contains(id);

  void _text(Canvas canvas, String s, Offset at, {double size = 15, Color? color, FontWeight weight = FontWeight.w500, bool center = true, double opacity = 1}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: (color ?? (dark ? Colors.white : Colors.black87)).withOpacity(opacity), fontWeight: weight)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / canvasSize.width, size.height / canvasSize.height);
    canvas.save();
    canvas.translate((size.width - canvasSize.width * scale) / 2, (size.height - canvasSize.height * scale) / 2);
    canvas.scale(scale);

    final ink = dark ? Colors.white : Colors.black87;

    // ---- wires (drawn first so boxes sit on top) ----
    int lane = 0;
    for (final m in _modules) {
      final on = _on(m.id);
      for (int i = 0; i < m.pins.length; i++) {
        final p = m.pins[i];
        final from = Offset(m.rect.left + (i + 0.5) * m.rect.width / m.pins.length, m.rect.bottom);
        final isRail = p.target == '5V' || p.target == '3.3V' || p.target == 'GND' || p.target == 'NC';
        if (isRail) {
          // short colored stub + rail label (rails are shared buses, not drawn as long wires)
          final c = _railColor(p.target);
          canvas.drawLine(from, from + const Offset(0, 22), Paint()
            ..color = c.withOpacity(on ? 1 : 0.15)
            ..strokeWidth = 3);
          _text(canvas, p.target == 'NC' ? 'n/c' : p.target, from + const Offset(0, 34),
              size: 11, color: c, weight: FontWeight.w700, opacity: on ? 1 : 0.2);
          continue;
        }
        final to = _unoPin(p.target);
        final laneY = 205.0 + (lane % 22) * 6.5;
        lane++;
        final path = Path()..moveTo(from.dx, from.dy);
        if (p.target.startsWith('A')) {
          // route down the left side of the board to the bottom header
          final sideX = _unoRect.left - 30 - (lane % 6) * 7.0;
          final belowY = _unoRect.bottom + 45 + (lane % 6) * 7.0;
          path
            ..lineTo(from.dx, laneY)
            ..lineTo(sideX, laneY)
            ..lineTo(sideX, belowY)
            ..lineTo(to.dx, belowY)
            ..lineTo(to.dx, to.dy);
        } else {
          path
            ..lineTo(from.dx, laneY)
            ..lineTo(to.dx, laneY)
            ..lineTo(to.dx, to.dy);
        }
        canvas.drawPath(path, Paint()
          ..color = m.color.withOpacity(on ? 1 : 0.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = on && highlight.isNotEmpty ? 4 : 3
          ..strokeJoin = StrokeJoin.round);
        if (p.note != null && on) {
          final mid = Offset((from.dx + to.dx) / 2, laneY - 9);
          _text(canvas, p.note!, mid, size: 11, color: m.color, weight: FontWeight.w700);
        }
      }
    }

    // reset capacitor: D4 -> 0.1uF -> RESET, routed around the right side
    {
      final on = _on('resetcap');
      final a = _unoPin('D4');
      final b = _unoPin('RESET');
      final c = const Color(0xFF26A69A).withOpacity(on ? 1 : 0.12);
      final rx = _unoRect.right + 40;
      final by = _unoRect.bottom + 95;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(a.dx, a.dy - 20)
        ..lineTo(rx, a.dy - 20)
        ..lineTo(rx, by)
        ..lineTo(b.dx, by)
        ..lineTo(b.dx, b.dy);
      canvas.drawPath(path, Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3);
      // capacitor symbol on the right-hand vertical
      final capY = (a.dy + by) / 2;
      final bg = Paint()..color = dark ? const Color(0xFF272B36) : const Color(0xFFE6E7EE);
      canvas.drawRect(Rect.fromCenter(center: Offset(rx, capY), width: 30, height: 14), bg);
      final plate = Paint()
        ..color = c
        ..strokeWidth = 4;
      canvas.drawLine(Offset(rx - 14, capY - 5), Offset(rx + 14, capY - 5), plate);
      canvas.drawLine(Offset(rx - 14, capY + 5), Offset(rx + 14, capY + 5), plate);
      _text(canvas, '0.1µF', Offset(rx + 42, capY), size: 12, color: const Color(0xFF26A69A), weight: FontWeight.w700, opacity: on ? 1 : 0.2);
      _text(canvas, 'auto-reset (optional)', Offset(rx + 70, capY + 18), size: 10, color: const Color(0xFF26A69A), opacity: on ? 1 : 0.2);
    }

    // ---- the Uno ----
    final unoOn = highlight.isEmpty || highlight.contains('power') || highlight.isNotEmpty;
    final board = RRect.fromRectAndRadius(_unoRect, const Radius.circular(14));
    canvas.drawRRect(board, Paint()..color = const Color(0xFF00796B).withOpacity(unoOn ? 1 : 0.5));
    canvas.drawRRect(board, Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    _text(canvas, 'ARDUINO UNO', _unoRect.center - const Offset(0, 10), size: 26, color: Colors.white, weight: FontWeight.w800);
    _text(canvas, 'powered by USB power bank', _unoRect.center + const Offset(0, 22), size: 13, color: Colors.white70);
    // USB port
    canvas.drawRect(Rect.fromLTWH(_unoRect.left - 18, _unoRect.top + 40, 34, 46), Paint()..color = const Color(0xFFB0BEC5));
    _text(canvas, 'USB', Offset(_unoRect.left - 1, _unoRect.top + 100), size: 11, color: Colors.white, weight: FontWeight.w700);

    // header pins + labels
    for (int n = 0; n <= 13; n++) {
      final p = _unoPin('D$n');
      canvas.drawRect(Rect.fromCenter(center: p + const Offset(0, 8), width: 14, height: 14), Paint()..color = Colors.black87);
      _text(canvas, 'D$n', p + const Offset(0, 28), size: 11, color: Colors.white, weight: FontWeight.w700);
    }
    for (final name in ['RESET', '3.3V', '5V', 'GND', 'VIN', 'A0', 'A1', 'A2', 'A3', 'A4', 'A5']) {
      final p = _unoPin(name);
      canvas.drawRect(Rect.fromCenter(center: p - const Offset(0, 8), width: 14, height: 14), Paint()..color = Colors.black87);
      _text(canvas, name, p - const Offset(0, 28), size: name.length > 3 ? 9 : 11, color: Colors.white, weight: FontWeight.w700);
    }

    // power bus legend under the board
    final legendY = _unoRect.bottom + 125;
    final rails = [
      ['5V', 'Uno 5V pin: servo, HC-SR04, relay, HC-05'],
      ['3.3V', 'Uno 3.3V pin: HC-05 EN, only during setup'],
      ['GND', 'every GND joins the Uno GND'],
    ];
    for (int i = 0; i < rails.length; i++) {
      final y = legendY + i * 24.0;
      final on = highlight.isEmpty || highlight.contains('power');
      canvas.drawLine(Offset(300, y), Offset(340, y), Paint()
        ..color = _railColor(rails[i][0]).withOpacity(on ? 1 : 0.3)
        ..strokeWidth = 5);
      _text(canvas, '${rails[i][0]}  ${rails[i][1]}', Offset(352, y - 9), size: 13, center: false, color: ink, opacity: on ? 1 : 0.4);
    }

    // ---- module boxes ----
    for (final m in _modules) {
      final on = _on(m.id);
      final r = RRect.fromRectAndRadius(m.rect, const Radius.circular(12));
      canvas.drawRRect(r, Paint()..color = m.color.withOpacity(on ? 0.95 : 0.15));
      _text(canvas, m.title, Offset(m.rect.center.dx, m.rect.top + 24), size: 17, color: Colors.white, weight: FontWeight.w800, opacity: on ? 1 : 0.5);
      _text(canvas, m.subtitle, Offset(m.rect.center.dx, m.rect.top + 46), size: 10.5, color: Colors.white, opacity: on ? 0.9 : 0.4);
      for (int i = 0; i < m.pins.length; i++) {
        final x = m.rect.left + (i + 0.5) * m.rect.width / m.pins.length;
        _text(canvas, m.pins[i].name, Offset(x, m.rect.bottom - 30), size: 11.5, color: Colors.white, weight: FontWeight.w700, opacity: on ? 1 : 0.4);
        _text(canvas, m.pins[i].target, Offset(x, m.rect.bottom - 13), size: 9.5, color: Colors.white, opacity: on ? 0.85 : 0.3);
        canvas.drawCircle(Offset(x, m.rect.bottom), 4, Paint()..color = Colors.white.withOpacity(on ? 1 : 0.3));
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WiringDiagramPainter old) => old.highlight != highlight || old.dark != dark;
}

/// Compact diagram card: tap to open it full screen (pinch to zoom).
class WiringDiagramCard extends StatelessWidget {
  final Set<String> highlight;
  final String? caption;
  const WiringDiagramCard({super.key, this.highlight = const {}, this.caption});

  @override
  Widget build(BuildContext context) {
    return ClayContainer(
      padding: EdgeInsets.all(10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => WiringDiagramScreen(initialHighlight: highlight),
      )),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: WiringDiagramPainter.canvasSize.width / WiringDiagramPainter.canvasSize.height,
            child: CustomPaint(painter: WiringDiagramPainter(highlight: highlight, dark: ClayColors.dark)),
          ),
          SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.zoom_in, size: 16, color: ClayColors.textSecondary),
              SizedBox(width: 4),
              Text(caption ?? 'Tap to open the full wiring diagram',
                  style: TextStyle(color: ClayColors.textSecondary, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Full-screen, zoomable wiring diagram. Tap a part below to highlight
/// just its wires.
class WiringDiagramScreen extends StatefulWidget {
  final Set<String> initialHighlight;
  const WiringDiagramScreen({super.key, this.initialHighlight = const {}});

  @override
  State<WiringDiagramScreen> createState() => _WiringDiagramScreenState();
}

class _WiringDiagramScreenState extends State<WiringDiagramScreen> {
  late Set<String> _highlight = Set.of(widget.initialHighlight);

  static const _parts = [
    ['hc05', 'HC-05'],
    ['sonar', 'HC-SR04'],
    ['servo', 'Servo'],
    ['relay', 'Relay'],
    ['buzzer', 'Buzzer'],
    ['display', '7-segment'],
    ['resetcap', 'Auto-reset'],
    ['power', 'Power'],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Wiring diagram')),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 6,
              boundaryMargin: EdgeInsets.all(40),
              child: Center(
                child: AspectRatio(
                  aspectRatio: WiringDiagramPainter.canvasSize.width / WiringDiagramPainter.canvasSize.height,
                  child: CustomPaint(painter: WiringDiagramPainter(highlight: Set.of(_highlight), dark: ClayColors.dark)),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Text('Pinch to zoom. Tap a part to show only its wires.',
                style: TextStyle(color: ClayColors.textSecondary, fontSize: 12)),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('All'),
                    selected: _highlight.isEmpty,
                    onSelected: (_) => setState(() => _highlight = <String>{}),
                  ),
                ),
                for (final p in _parts)
                  Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(p[1]),
                      selected: _highlight.length == 1 && _highlight.contains(p[0]),
                      onSelected: (_) => setState(() => _highlight = {p[0]}),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 12),
        ],
      ),
    );
  }
}
