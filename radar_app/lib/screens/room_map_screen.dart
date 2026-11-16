import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/radar_reading.dart';
import '../services/bluetooth_service.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';

/// A finished room map: for each angle bucket, the typical distance (cm)
/// to the nearest surface, or null if nothing echoed back in range.
class RoomMap {
  final String name;
  final DateTime createdAt;
  final int bucketDeg;
  final List<int?> distances; // index = angle / bucketDeg

  RoomMap(this.name, this.createdAt, this.bucketDeg, this.distances);

  Map<String, dynamic> toJson() => {
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'bucketDeg': bucketDeg,
        'distances': distances,
      };

  static RoomMap fromJson(Map<String, dynamic> j) => RoomMap(
        j['name'] as String,
        DateTime.parse(j['createdAt'] as String),
        j['bucketDeg'] as int,
        (j['distances'] as List).map((e) => e == null ? null : (e as num).toInt()).toList(),
      );

  int? get nearestCm {
    final v = distances.whereType<int>().toList();
    return v.isEmpty ? null : v.reduce(math.min);
  }

  int? get farthestCm {
    final v = distances.whereType<int>().toList();
    return v.isEmpty ? null : v.reduce(math.max);
  }

  int get coveragePercent {
    if (distances.isEmpty) return 0;
    return (distances.whereType<int>().length * 100 / distances.length).round();
  }

  /// Rough floor area of the scanned half-circle, in m², from the outline
  /// (sum of thin triangles between neighbouring angle buckets).
  double get areaM2 {
    double area = 0;
    final step = bucketDeg * math.pi / 180;
    for (int i = 0; i + 1 < distances.length; i++) {
      final a = distances[i];
      final b = distances[i + 1];
      if (a == null || b == null) continue;
      area += 0.5 * a * b * math.sin(step);
    }
    return area / 10000.0;
  }
}

class _MapStore {
  static const _key = 'room_maps';

  static Future<List<RoomMap>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) => RoomMap.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<RoomMap> maps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(maps.map((m) => m.toJson()).toList()));
  }
}

/// Maps the room from one fixed spot: records a few full servo sweeps,
/// takes the median distance at each angle (so one noisy echo or someone
/// walking past doesn't distort the walls), and draws the outline.
class RoomMapScreen extends StatefulWidget {
  final RadarBluetoothService bluetooth;
  const RoomMapScreen({super.key, required this.bluetooth});

  @override
  State<RoomMapScreen> createState() => _RoomMapScreenState();
}

class _RoomMapScreenState extends State<RoomMapScreen> {
  static const int bucketDeg = 5;
  static const int maxRangeCm = 300;
  static const Duration scanDuration = Duration(seconds: 20);

  StreamSubscription<String>? _sub;
  Timer? _timer;
  bool _scanning = false;
  double _progress = 0;
  DateTime? _scanStart;
  final Map<int, List<int>> _samples = {};
  RoomMap? _current;
  List<RoomMap> _saved = [];

  int get _bucketCount => 180 ~/ bucketDeg + 1;

  @override
  void initState() {
    super.initState();
    _MapStore.load().then((m) {
      if (mounted) setState(() => _saved = m);
    });
  }

  void _startScan() {
    _samples.clear();
    _scanStart = DateTime.now();
    setState(() {
      _scanning = true;
      _progress = 0;
      _current = null;
    });
    _sub = widget.bluetooth.lines.listen((line) {
      final r = RadarReading.parse(line);
      if (r == null || r.distanceCm <= 0 || r.distanceCm > maxRangeCm) return;
      final int bucket = math.max(0, math.min(_bucketCount - 1, (r.angle / bucketDeg).round()));
      _samples.putIfAbsent(bucket, () => <int>[]).add(r.distanceCm);
    });
    _timer = Timer.periodic(Duration(milliseconds: 200), (_) {
      final elapsed = DateTime.now().difference(_scanStart!);
      if (elapsed >= scanDuration) {
        _finishScan();
      } else if (mounted) {
        setState(() => _progress = elapsed.inMilliseconds / scanDuration.inMilliseconds);
      }
    });
  }

  void _finishScan() {
    _timer?.cancel();
    _sub?.cancel();
    final distances = List<int?>.generate(_bucketCount, (i) {
      final s = _samples[i];
      if (s == null || s.isEmpty) return null;
      final sorted = List<int>.of(s)..sort();
      return sorted[sorted.length ~/ 2];
    });
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _progress = 1;
      _current = RoomMap('Unsaved scan', DateTime.now(), bucketDeg, distances);
    });
  }

  Future<void> _saveCurrent() async {
    final map = _current;
    if (map == null) return;
    final ctrl = TextEditingController(text: 'Room ${_saved.length + 1}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Name this map'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final named = RoomMap(name, map.createdAt, map.bucketDeg, map.distances);
    final updated = [named, ..._saved];
    await _MapStore.save(updated);
    if (mounted) {
      setState(() {
        _saved = updated;
        _current = named;
      });
    }
  }

  Future<void> _delete(RoomMap m) async {
    final updated = _saved.where((x) => !identical(x, m)).toList();
    await _MapStore.save(updated);
    if (mounted) setState(() => _saved = updated);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final map = _current;
    return Scaffold(
      appBar: AppBar(title: Text('Room map')),
      body: ListView(
        padding: EdgeInsets.all(20),
        children: [
          ClayContainer(
            padding: EdgeInsets.all(10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                color: Color(0xFF0B1220),
                child: AspectRatio(
                  aspectRatio: 1.7,
                  child: CustomPaint(
                    painter: _MapPainter(
                      map: map,
                      liveSamples: _scanning ? Map.of(_samples) : null,
                      bucketDeg: bucketDeg,
                      maxRangeCm: maxRangeCm,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 16),
          if (_scanning) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: _progress, minHeight: 8),
            ),
            SizedBox(height: 8),
            Text(
              'Scanning... keep the radar still and stay out of the room if you can.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ClayColors.textSecondary),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: ClayContainer(
                    onTap: _startScan,
                    child: Center(
                      child: Text(map == null ? 'Scan this room' : 'Scan again',
                          style: TextStyle(color: ClayColors.primary, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                if (map != null && map.name == 'Unsaved scan') ...[
                  SizedBox(width: 12),
                  Expanded(
                    child: ClayContainer(
                      onTap: _saveCurrent,
                      child: Center(
                        child: Text('Save map', style: TextStyle(color: ClayColors.success, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          if (map != null && !_scanning) ...[
            SizedBox(height: 16),
            ClayContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(map.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ClayColors.textPrimary)),
                  SizedBox(height: 10),
                  _row('Nearest surface', map.nearestCm != null ? '${map.nearestCm} cm' : '--'),
                  _row('Farthest surface', map.farthestCm != null ? '${map.farthestCm} cm' : '--'),
                  _row('Approx. area in view', '${map.areaM2.toStringAsFixed(1)} m²'),
                  _row('Angles with an echo', '${map.coveragePercent}%'),
                ],
              ),
            ),
          ],
          if (!_scanning && map == null)
            Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'Place the radar where it will stay (a shelf or corner works well), '
                'then tap Scan. It records about 20 seconds of sweeps and draws the '
                'walls and furniture it sees from that spot.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ClayColors.textSecondary, height: 1.4),
              ),
            ),
          if (_saved.isNotEmpty) ...[
            SizedBox(height: 24),
            Text('Saved maps', style: TextStyle(fontWeight: FontWeight.w800, color: ClayColors.textPrimary, fontSize: 16)),
            SizedBox(height: 10),
            for (final m in _saved)
              Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: ClayContainer(
                  onTap: () => setState(() => _current = m),
                  padding: EdgeInsets.fromLTRB(16, 8, 4, 8),
                  child: Row(
                    children: [
                      Icon(Icons.map_outlined, color: ClayColors.primary),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.name, style: TextStyle(fontWeight: FontWeight.w700, color: ClayColors.textPrimary)),
                            Text(
                              '${m.createdAt.day}/${m.createdAt.month}/${m.createdAt.year} • ${m.areaM2.toStringAsFixed(1)} m²',
                              style: TextStyle(color: ClayColors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: ClayColors.textSecondary),
                        onPressed: () => _delete(m),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: ClayColors.textSecondary))),
          Text(value, style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final RoomMap? map;
  final Map<int, List<int>>? liveSamples;
  final int bucketDeg;
  final int maxRangeCm;

  _MapPainter({required this.map, required this.liveSamples, required this.bucketDeg, required this.maxRangeCm});

  static const _green = Color(0xFF4ECCA3);

  Offset _point(Offset c, double radius, double deg) {
    final rad = math.pi - deg * math.pi / 180;
    return Offset(c.dx + radius * math.cos(rad), c.dy - radius * math.sin(rad));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height - 14);
    final maxR = math.min(size.width / 2 - 12, size.height - 26);
    final grid = Paint()
      ..color = _green.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      final r = maxR * i / 3;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), math.pi, math.pi, false, grid);
      final tp = TextPainter(
        text: TextSpan(text: '${(maxRangeCm * i / 3 / 100).toStringAsFixed(0)} m', style: TextStyle(color: _green.withOpacity(0.5), fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(c.dx + r - tp.width - 2, c.dy - tp.height - 1));
    }
    canvas.drawLine(Offset(c.dx - maxR, c.dy), Offset(c.dx + maxR, c.dy), grid);

    // While scanning: every raw sample as a faint dot
    final live = liveSamples;
    if (live != null) {
      final dot = Paint()..color = _green.withOpacity(0.45);
      live.forEach((bucket, values) {
        for (final v in values) {
          canvas.drawCircle(_point(c, maxR * v / maxRangeCm, (bucket * bucketDeg).toDouble()), 1.8, dot);
        }
      });
    }

    final m = map;
    if (m != null) {
      // Filled floor area + wall outline, broken where nothing echoed
      final fill = Path()..moveTo(c.dx, c.dy);
      final outline = Path();
      bool penDown = false;
      for (int i = 0; i < m.distances.length; i++) {
        final d = m.distances[i];
        final deg = (i * m.bucketDeg).toDouble();
        if (d == null) {
          fill.lineTo(c.dx, c.dy);
          penDown = false;
          continue;
        }
        final p = _point(c, maxR * math.min(d, maxRangeCm) / maxRangeCm, deg);
        fill.lineTo(p.dx, p.dy);
        if (penDown) {
          outline.lineTo(p.dx, p.dy);
        } else {
          outline.moveTo(p.dx, p.dy);
          penDown = true;
        }
      }
      fill.close();
      canvas.drawPath(fill, Paint()..color = const Color(0xFF6C63FF).withOpacity(0.35));
      canvas.drawPath(
        outline,
        Paint()
          ..color = _green
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round,
      );
      for (int i = 0; i < m.distances.length; i++) {
        final d = m.distances[i];
        if (d == null) continue;
        canvas.drawCircle(_point(c, maxR * math.min(d, maxRangeCm) / maxRangeCm, (i * m.bucketDeg).toDouble()), 2.5, Paint()..color = Colors.white);
      }
    }

    // The fixed point the radar sits at
    canvas.drawCircle(c, 6, Paint()..color = const Color(0xFFFF6B6B));
    canvas.drawCircle(c, 11, Paint()
      ..color = const Color(0xFFFF6B6B).withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => true;
}
