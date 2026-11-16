import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/radar_reading.dart';
import '../services/bluetooth_service.dart';
import '../services/radar_settings.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';
import 'room_map_screen.dart';

enum _LabTool { speed, heatmap, guard, measure, proximity }

/// Extra things the same radar can do, computed on the phone from the
/// normal readings, with no firmware change:
///  - Approach speed: how fast something moves toward or away from the
///    radar, from two distance readings at the same angle (one per sweep).
///  - Activity heatmap: which directions see the most movement over time.
///  - Room guard: compares the live sweep to a saved room map and flags
///    anything that wasn't there when the map was made.
///  - Tape measure: parks the sensor at one angle and shows a steady
///    distance reading (uses a "sweep from A to A" setting, then restores).
///  - Parking sensor: clicks and vibration that speed up as things get closer.
class RadarLabScreen extends StatefulWidget {
  final RadarBluetoothService bluetooth;
  const RadarLabScreen({super.key, required this.bluetooth});

  @override
  State<RadarLabScreen> createState() => _RadarLabScreenState();
}

class _SpeedEvent {
  final int angle;
  final double cmPerSec; // positive = approaching
  final int distanceCm;
  final DateTime at;
  _SpeedEvent(this.angle, this.cmPerSec, this.distanceCm, this.at);
}

class _RadarLabScreenState extends State<RadarLabScreen> with SingleTickerProviderStateMixin {
  static const int bucketDeg = 5;
  static const int maxRangeCm = 300;
  static const int buckets = 180 ~/ bucketDeg + 1;

  _LabTool _tool = _LabTool.speed;
  StreamSubscription<String>? _sub;
  late final AnimationController _pulse;

  // shared: last reading per angle bucket
  final List<int?> _lastCm = List<int?>.filled(buckets, null);
  final List<DateTime?> _lastAt = List<DateTime?>.filled(buckets, null);
  final List<int?> _liveCm = List<int?>.filled(buckets, null);
  int? _liveAngle;

  // speed
  final List<_SpeedEvent> _speedEvents = [];
  _SpeedEvent? _topMover;
  static const double fastCmPerSec = 60;

  // heatmap
  final List<int> _heat = List<int>.filled(buckets, 0);
  int _heatTotal = 0;
  DateTime _heatSince = DateTime.now();

  // guard
  List<RoomMap> _maps = [];
  RoomMap? _guardMap;
  final List<bool> _intrusion = List<bool>.filled(buckets, false);
  int _guardAlerts = 0;
  DateTime? _lastGuardBuzz;

  // measure
  double _aimAngle = 90;
  bool _holding = false;
  RadarSettings? _savedSettings;
  final List<int> _measureWindow = [];
  final List<String> _measurements = [];

  // proximity
  final List<MapEntry<DateTime, int>> _recent = [];
  bool _proxSound = true;
  Timer? _beepTimer;
  DateTime _lastBeep = DateTime.fromMillisecondsSinceEpoch(0);

  int? get _nearestRecent {
    final now = DateTime.now();
    _recent.removeWhere((e) => now.difference(e.key).inMilliseconds > 1200);
    if (_recent.isEmpty) return null;
    return _recent.map((e) => e.value).reduce(math.min);
  }

  void _setTool(_LabTool t) {
    if (_tool == _LabTool.measure && t != _LabTool.measure) _stopHold();
    setState(() => _tool = t);
  }

  Future<void> _startHold() async {
    _savedSettings ??= await RadarSettings.load();
    final s0 = _savedSettings!;
    widget.bluetooth.sendLine('CFG,${s0.alertCm},${_aimAngle.round()},${_aimAngle.round()},1,0,0');
    if (!mounted) return;
    setState(() {
      _holding = true;
      _measureWindow.clear();
    });
  }

  void _stopHold() {
    if (!_holding) return;
    final s0 = _savedSettings;
    widget.bluetooth.sendLine((s0 ?? RadarSettings()).toCommand());
    _holding = false;
    if (mounted) setState(() {});
  }

  int? get _measured {
    if (_measureWindow.length < 3) return null;
    final sorted = List<int>.of(_measureWindow)..sort();
    return sorted[sorted.length ~/ 2];
  }

  int get _spread {
    if (_measureWindow.length < 3) return 999;
    return _measureWindow.reduce(math.max) - _measureWindow.reduce(math.min);
  }

  void _beepTick() {
    if (!mounted || _tool != _LabTool.proximity || !_proxSound) return;
    final d = _nearestRecent;
    if (d == null || d > 150) return;
    final interval = d < 15 ? 90 : (100 + (d - 15) * 900 ~/ 135);
    final now = DateTime.now();
    if (now.difference(_lastBeep).inMilliseconds >= interval) {
      _lastBeep = now;
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.selectionClick();
    }
  }

  @override
  void initState() {
    super.initState();
    _beepTimer = Timer.periodic(const Duration(milliseconds: 40), (_) => _beepTick());
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _sub = widget.bluetooth.lines.listen(_onLine);
    RoomMapStore.load().then((m) {
      if (!mounted) return;
      setState(() {
        _maps = m;
        if (m.isNotEmpty) _guardMap = m.first;
      });
    });
  }

  @override
  void dispose() {
    _stopHold();
    _beepTimer?.cancel();
    _sub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  int _bucketOf(int angle) => math.max(0, math.min(buckets - 1, (angle / bucketDeg).round()));

  void _onLine(String line) {
    final r = RadarReading.parse(line);
    if (r == null || !mounted) return;
    final now = DateTime.now();
    final b = _bucketOf(r.angle);
    final cm = (r.distanceCm > 0 && r.distanceCm <= maxRangeCm) ? r.distanceCm : null;
    _liveAngle = r.angle;
    _liveCm[b] = cm;
    if (cm != null) _recent.add(MapEntry(now, cm));
    if (_holding && cm != null && (r.angle - _aimAngle.round()).abs() <= 2) {
      _measureWindow.add(cm);
      if (_measureWindow.length > 9) _measureWindow.removeAt(0);
    }

    final prevCm = _lastCm[b];
    final prevAt = _lastAt[b];
    if (cm != null && prevCm != null && prevAt != null) {
      final dt = now.difference(prevAt).inMilliseconds / 1000.0;
      final dd = (prevCm - cm).toDouble(); // positive = got closer
      // speed: only trust moderate gaps (one sweep) and real movement
      if (dt > 0.2 && dt < 8 && dd.abs() >= 10) {
        final ev = _SpeedEvent(r.angle, dd / dt, cm, now);
        _speedEvents.insert(0, ev);
        if (_speedEvents.length > 30) _speedEvents.removeLast();
        if (_topMover == null ||
            now.difference(_topMover!.at).inSeconds > 6 ||
            ev.cmPerSec.abs() > _topMover!.cmPerSec.abs()) {
          _topMover = ev;
        }
        if (_tool == _LabTool.speed && ev.cmPerSec > fastCmPerSec) HapticFeedback.mediumImpact();
      }
      // heatmap: count a "change" when the distance at this angle jumps
      if (dd.abs() >= 15) {
        _heat[b]++;
        _heatTotal++;
      }
    }
    if (cm != null) {
      _lastCm[b] = cm;
      _lastAt[b] = now;
    }

    // room guard: closer than the saved wall by a clear margin = something new
    final map = _guardMap;
    if (map != null && b < map.distances.length) {
      final wall = map.distances[b];
      final intruding = cm != null && (wall == null ? cm < 200 : cm < wall - 30);
      if (intruding && !_intrusion[b]) {
        _guardAlerts++;
        final last = _lastGuardBuzz;
        if (_tool == _LabTool.guard && (last == null || now.difference(last).inMilliseconds > 1500)) {
          _lastGuardBuzz = now;
          HapticFeedback.heavyImpact();
        }
      }
      _intrusion[b] = intruding;
    }
    setState(() {});
  }

  void _resetHeat() {
    setState(() {
      for (int i = 0; i < buckets; i++) {
        _heat[i] = 0;
      }
      _heatTotal = 0;
      _heatSince = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Radar Lab')),
      body: ListView(
        padding: EdgeInsets.all(20),
        children: [
          SizedBox(
            height: 76,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final t in _LabTool.values)
                  Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: SizedBox(
                      width: 78,
                      child: ClayContainer(
                        pressed: _tool == t,
                        padding: EdgeInsets.symmetric(vertical: 10),
                        onTap: () => _setTool(t),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_iconFor(t), color: _tool == t ? ClayColors.primary : ClayColors.textSecondary),
                            SizedBox(height: 4),
                            Text(_labelFor(t),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _tool == t ? ClayColors.primary : ClayColors.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 18),
          AnimatedSwitcher(
            duration: Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(begin: Offset(0, 0.04), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: KeyedSubtree(key: ValueKey(_tool), child: _toolBody()),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(_LabTool t) {
    switch (t) {
      case _LabTool.speed:
        return Icons.speed;
      case _LabTool.heatmap:
        return Icons.local_fire_department_outlined;
      case _LabTool.guard:
        return Icons.shield_outlined;
      case _LabTool.measure:
        return Icons.straighten;
      case _LabTool.proximity:
        return Icons.sensors;
    }
  }

  String _labelFor(_LabTool t) {
    switch (t) {
      case _LabTool.speed:
        return 'Speed';
      case _LabTool.heatmap:
        return 'Heatmap';
      case _LabTool.guard:
        return 'Guard';
      case _LabTool.measure:
        return 'Measure';
      case _LabTool.proximity:
        return 'Parking';
    }
  }

  Widget _toolBody() {
    switch (_tool) {
      case _LabTool.speed:
        return _speedBody();
      case _LabTool.heatmap:
        return _heatBody();
      case _LabTool.guard:
        return _guardBody();
      case _LabTool.measure:
        return _measureBody();
      case _LabTool.proximity:
        return _proximityBody();
    }
  }

  Widget _scope(CustomPainter painter) {
    return ClayContainer(
      padding: EdgeInsets.all(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          color: Color(0xFF0B1220),
          child: AspectRatio(
            aspectRatio: 1.7,
            child: AnimatedBuilder(animation: _pulse, builder: (_, __) => CustomPaint(painter: painter)),
          ),
        ),
      ),
    );
  }

  Widget _note(String text) => Padding(
        padding: EdgeInsets.only(top: 14),
        child: Text(text, style: TextStyle(color: ClayColors.textSecondary, fontSize: 12, height: 1.4)),
      );

  // ---------------- speed ----------------
  Widget _speedBody() {
    final top = _topMover;
    final fresh = top != null && DateTime.now().difference(top.at).inSeconds <= 6;
    final speed = fresh ? top.cmPerSec : 0.0;
    final approaching = speed > 0;
    final fast = speed > fastCmPerSec;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClayContainer(
          child: Column(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: speed.abs()),
                duration: Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => SizedBox(
                  height: 150,
                  child: CustomPaint(
                    painter: _GaugePainter(value: v, max: 200, color: fast ? ClayColors.danger : ClayColors.primary),
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(v.toStringAsFixed(0),
                                style: TextStyle(
                                    fontSize: 40, fontWeight: FontWeight.w800, color: ClayColors.textPrimary)),
                            Text('cm/s', style: TextStyle(color: ClayColors.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 8),
              Text(
                !fresh
                    ? 'Nothing moving right now'
                    : '${approaching ? 'Approaching' : 'Moving away'} at ${top.angle}°, now ${top.distanceCm} cm away',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: !fresh ? ClayColors.textSecondary : (fast ? ClayColors.danger : ClayColors.textPrimary)),
                textAlign: TextAlign.center,
              ),
              if (fresh && fast)
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Fast approach!', style: TextStyle(color: ClayColors.danger, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
        ),
        SizedBox(height: 16),
        Text('Recent movement', style: TextStyle(fontWeight: FontWeight.w800, color: ClayColors.textPrimary)),
        SizedBox(height: 8),
        if (_speedEvents.isEmpty)
          Text('Walk in front of the radar to see readings here.', style: TextStyle(color: ClayColors.textSecondary)),
        for (final e in _speedEvents.take(8))
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: ClayContainer(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(e.cmPerSec > 0 ? Icons.south : Icons.north,
                      color: e.cmPerSec > fastCmPerSec ? ClayColors.danger : ClayColors.primary, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('${e.cmPerSec.abs().toStringAsFixed(0)} cm/s ${e.cmPerSec > 0 ? 'closer' : 'away'}',
                        style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w600)),
                  ),
                  Text('${e.angle}° · ${e.distanceCm} cm', style: TextStyle(color: ClayColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ),
        _note('Speed comes from two distance readings at the same angle, one sweep apart. It shows '
            'movement toward or away from the radar; sideways movement shows up on the heatmap instead.'),
      ],
    );
  }

  // ---------------- heatmap ----------------
  Widget _heatBody() {
    int hottest = 0;
    for (int i = 1; i < buckets; i++) {
      if (_heat[i] > _heat[hottest]) hottest = i;
    }
    final mins = DateTime.now().difference(_heatSince).inMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scope(_HeatPainter(heat: List.of(_heat), bucketDeg: bucketDeg, liveAngle: _liveAngle)),
        SizedBox(height: 14),
        ClayContainer(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_heatTotal == 0 ? 'No movement yet' : 'Busiest direction: ${hottest * bucketDeg}°',
                        style: TextStyle(fontWeight: FontWeight.w800, color: ClayColors.textPrimary)),
                    SizedBox(height: 4),
                    Text('$_heatTotal movements in ${mins < 1 ? 'under a minute' : '$mins min'}',
                        style: TextStyle(color: ClayColors.textSecondary)),
                  ],
                ),
              ),
              TextButton.icon(onPressed: _resetHeat, icon: Icon(Icons.restart_alt), label: Text('Reset')),
            ],
          ),
        ),
        _note('Each time the distance in a direction jumps by 15 cm or more, that direction warms up. '
            'Leave it running for a while to see the room\'s walkways and doorways glow.'),
      ],
    );
  }

  // ---------------- guard ----------------
  Widget _guardBody() {
    if (_maps.isEmpty) {
      return ClayContainer(
        child: Column(
          children: [
            Icon(Icons.map_outlined, size: 40, color: ClayColors.primary),
            SizedBox(height: 10),
            Text('Room guard needs a saved room map.',
                style: TextStyle(fontWeight: FontWeight.w800, color: ClayColors.textPrimary)),
            SizedBox(height: 6),
            Text('Scan the empty room first: Live radar > Map this room > Save map. Then come back here.',
                textAlign: TextAlign.center, style: TextStyle(color: ClayColors.textSecondary)),
          ],
        ),
      );
    }
    final active = _intrusion.where((x) => x).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: Duration(milliseconds: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            boxShadow: active > 0
                ? [BoxShadow(color: ClayColors.danger.withOpacity(0.55), blurRadius: 24, spreadRadius: 1)]
                : [],
          ),
          child: _scope(_GuardPainter(
            map: _guardMap,
            live: List.of(_liveCm),
            intrusion: List.of(_intrusion),
            bucketDeg: bucketDeg,
            maxRangeCm: maxRangeCm,
            pulse: _pulse.value,
            liveAngle: _liveAngle,
          )),
        ),
        SizedBox(height: 14),
        ClayContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(active > 0 ? Icons.warning_amber_rounded : Icons.verified_user_outlined,
                      color: active > 0 ? ClayColors.danger : ClayColors.success),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(active > 0 ? 'Something new in $active direction${active == 1 ? '' : 's'}' : 'Room matches the map',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: active > 0 ? ClayColors.danger : ClayColors.textPrimary)),
                  ),
                ],
              ),
              SizedBox(height: 6),
              Text('$_guardAlerts changes spotted since opening', style: TextStyle(color: ClayColors.textSecondary)),
              SizedBox(height: 10),
              DropdownButton<RoomMap>(
                isExpanded: true,
                value: _guardMap,
                items: [for (final m in _maps) DropdownMenuItem(value: m, child: Text('Compare with: ${m.name}'))],
                onChanged: (m) => setState(() {
                  _guardMap = m;
                  for (int i = 0; i < buckets; i++) {
                    _intrusion[i] = false;
                  }
                  _guardAlerts = 0;
                }),
              ),
            ],
          ),
        ),
        _note('Green line: the walls from your saved map. Red: anything at least 30 cm closer than the wall '
            'in that direction, such as a person or a moved chair. Keep the radar in the same spot as when you saved the map.'),
      ],
    );
  }

  // ---------------- measure ----------------
  Widget _measureBody() {
    final m = _measured;
    final steady = _spread <= 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClayContainer(
          child: Column(
            children: [
              Text(_holding ? (m == null ? 'Measuring...' : (steady ? 'Steady reading' : 'Hold still...')) : 'Point and measure',
                  style: TextStyle(color: steady && m != null ? ClayColors.success : ClayColors.textSecondary, fontWeight: FontWeight.w700)),
              SizedBox(height: 8),
              AnimatedSwitcher(
                duration: Duration(milliseconds: 250),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Text(
                  m == null ? '--' : '$m cm',
                  key: ValueKey(m),
                  style: TextStyle(fontSize: 52, fontWeight: FontWeight.w900, color: ClayColors.textPrimary),
                ),
              ),
              if (m != null)
                Text('${(m / 100).toStringAsFixed(2)} m  ·  ${(m / 2.54).toStringAsFixed(1)} in',
                    style: TextStyle(color: ClayColors.textSecondary)),
              SizedBox(height: 16),
              Row(
                children: [
                  Text('Aim', style: TextStyle(color: ClayColors.textSecondary)),
                  Expanded(
                    child: Slider(
                      value: _aimAngle,
                      min: 0,
                      max: 180,
                      divisions: 36,
                      label: '${_aimAngle.round()}°',
                      onChanged: (v) => setState(() => _aimAngle = v),
                      onChangeEnd: (_) {
                        if (_holding) _startHold();
                      },
                    ),
                  ),
                  Text('${_aimAngle.round()}°', style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w700)),
                ],
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClayContainer(
                      onTap: _holding ? _stopHold : _startHold,
                      child: Center(
                        child: Text(_holding ? 'Stop and resume sweep' : 'Start measuring',
                            style: TextStyle(color: ClayColors.primary, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  ClayContainer(
                    onTap: m == null
                        ? null
                        : () => setState(() => _measurements.insert(0, '$m cm at ${_aimAngle.round()}°')),
                    child: Icon(Icons.bookmark_add_outlined, color: m == null ? ClayColors.textSecondary : ClayColors.primary),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_measurements.isNotEmpty) ...[
          SizedBox(height: 16),
          Text('Saved measurements', style: TextStyle(fontWeight: FontWeight.w800, color: ClayColors.textPrimary)),
          SizedBox(height: 8),
          for (final x in _measurements)
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: ClayContainer(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Icon(Icons.straighten, color: ClayColors.primary, size: 18),
                  SizedBox(width: 10),
                  Text(x, style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ],
        _note('The servo stops at the angle you choose, so the sensor keeps measuring the same spot. '
            'Leaving this tool puts the normal sweep back. Hard flat surfaces measure best; '
            'curtains and sofas absorb sound.'),
      ],
    );
  }

  // ---------------- proximity ----------------
  Widget _proximityBody() {
    final d = _nearestRecent;
    final zone = d == null || d > 150 ? 0 : (d < 30 ? 3 : (d < 80 ? 2 : 1));
    final color = [ClayColors.textSecondary, ClayColors.success, ClayColors.warning, ClayColors.danger][zone];
    final label = ['All clear', 'Something ahead', 'Getting close', 'Very close!'][zone];
    final fill = d == null ? 0.0 : (1 - (math.min(d, 150) / 150)).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClayContainer(
          child: Column(
            children: [
              SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) {
                        final grow = zone == 3 ? 10 * _pulse.value : 0.0;
                        return AnimatedContainer(
                          duration: Duration(milliseconds: 250),
                          width: 90 + 90 * fill + grow,
                          height: 90 + 90 * fill + grow,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color.withOpacity(0.18),
                            border: Border.all(color: color, width: 4),
                          ),
                        );
                      },
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(d == null ? '--' : '$d',
                            style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: ClayColors.textPrimary)),
                        Text('cm', style: TextStyle(color: ClayColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(height: 8),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18)),
              SizedBox(height: 8),
              SwitchListTile(
                title: Text('Clicks and vibration', style: TextStyle(color: ClayColors.textPrimary)),
                value: _proxSound,
                activeColor: ClayColors.primary,
                onChanged: (v) => setState(() => _proxSound = v),
              ),
            ],
          ),
        ),
        _note('Like a car parking sensor: green beyond 80 cm, amber under 80 cm, red under 30 cm. The clicks '
            'speed up as the nearest object in the last sweep gets closer, and turn almost continuous under 15 cm. '
            'Clicks follow your phone\'s touch-sound setting; vibration always works.'),
      ],
    );
  }

}

Offset _polar(Offset c, double r, double deg) {
  final rad = math.pi - deg * math.pi / 180;
  return Offset(c.dx + r * math.cos(rad), c.dy - r * math.sin(rad));
}

void _grid(Canvas canvas, Offset c, double maxR) {
  final p = Paint()
    ..color = Color(0xFF4ECCA3).withOpacity(0.16)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  for (int i = 1; i <= 3; i++) {
    canvas.drawArc(Rect.fromCircle(center: c, radius: maxR * i / 3), math.pi, math.pi, false, p);
  }
  canvas.drawLine(Offset(c.dx - maxR, c.dy), Offset(c.dx + maxR, c.dy), p);
}

class _HeatPainter extends CustomPainter {
  final List<int> heat;
  final int bucketDeg;
  final int? liveAngle;
  _HeatPainter({required this.heat, required this.bucketDeg, required this.liveAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height - 12);
    final maxR = math.min(size.width / 2 - 12, size.height - 24);
    _grid(canvas, c, maxR);
    final maxHeat = heat.fold<int>(1, (a, b) => math.max(a, b));
    final rect = Rect.fromCircle(center: c, radius: maxR);
    final step = bucketDeg * math.pi / 180;
    for (int i = 0; i < heat.length; i++) {
      if (heat[i] == 0) continue;
      final t = heat[i] / maxHeat;
      final color = Color.lerp(Color(0xFF6C63FF), Color(0xFFFF6B6B), t)!.withOpacity(0.25 + 0.6 * t);
      final deg = (i * bucketDeg) * math.pi / 180;
      // A direction of [deg] points at canvas angle (pi + deg): 0 deg = left, 90 = up, 180 = right.
      canvas.drawArc(rect, math.pi + deg - step / 2, step, true, Paint()..color = color);
    }
    if (liveAngle != null) {
      canvas.drawLine(c, _polar(c, maxR, liveAngle!.toDouble()), Paint()
        ..color = Color(0xFF4ECCA3)
        ..strokeWidth = 2);
    }
    canvas.drawCircle(c, 4, Paint()..color = Color(0xFF4ECCA3));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _GuardPainter extends CustomPainter {
  final RoomMap? map;
  final List<int?> live;
  final List<bool> intrusion;
  final int bucketDeg;
  final int maxRangeCm;
  final double pulse;
  final int? liveAngle;
  _GuardPainter({
    required this.map,
    required this.live,
    required this.intrusion,
    required this.bucketDeg,
    required this.maxRangeCm,
    required this.pulse,
    required this.liveAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height - 12);
    final maxR = math.min(size.width / 2 - 12, size.height - 24);
    _grid(canvas, c, maxR);
    double r(int cm) => maxR * math.min(cm, maxRangeCm) / maxRangeCm;

    final m = map;
    if (m != null) {
      final outline = Path();
      bool pen = false;
      for (int i = 0; i < m.distances.length; i++) {
        final d = m.distances[i];
        if (d == null) {
          pen = false;
          continue;
        }
        final p = _polar(c, r(d), (i * m.bucketDeg).toDouble());
        if (pen) {
          outline.lineTo(p.dx, p.dy);
        } else {
          outline.moveTo(p.dx, p.dy);
          pen = true;
        }
      }
      canvas.drawPath(outline, Paint()
        ..color = Color(0xFF4ECCA3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5);
    }
    for (int i = 0; i < live.length; i++) {
      final d = live[i];
      if (d == null) continue;
      final p = _polar(c, r(d), (i * bucketDeg).toDouble());
      if (i < intrusion.length && intrusion[i]) {
        canvas.drawCircle(p, 6 + 8 * pulse, Paint()..color = Color(0xFFFF6B6B).withOpacity(0.25 * (1 - pulse) + 0.1));
        canvas.drawCircle(p, 5, Paint()..color = Color(0xFFFF6B6B));
      } else {
        canvas.drawCircle(p, 2.2, Paint()..color = Colors.white.withOpacity(0.55));
      }
    }
    if (liveAngle != null) {
      canvas.drawLine(c, _polar(c, maxR, liveAngle!.toDouble()), Paint()
        ..color = Color(0xFF4ECCA3).withOpacity(0.6)
        ..strokeWidth = 1.5);
    }
    canvas.drawCircle(c, 5, Paint()..color = Color(0xFF6C63FF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _GaugePainter extends CustomPainter {
  final double value;
  final double max;
  final Color color;
  _GaugePainter({required this.value, required this.max, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height - 10);
    final r = math.min(size.width / 2 - 20, size.height - 20);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(rect, math.pi, math.pi, false, Paint()
      ..color = ClayColors.shadowDark.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round);
    final t = (value / max).clamp(0.0, 1.0).toDouble();
    canvas.drawArc(rect, math.pi, math.pi * t, false, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.value != value || old.color != color;
}
