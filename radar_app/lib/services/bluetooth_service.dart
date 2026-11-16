import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

/// Thin wrapper around classic Bluetooth SPP (flutter_bluetooth_serial) for
/// talking to the HC-05. Android only -- iOS can't do classic SPP, which is
/// why this project is Android-only by choice.
///
/// Exposes:
///  - a broadcast stream of raw lines received from the Uno
///  - sendLine() to push a command ("CFG,...", "WIFI,...", "ENTERUPDATE")
///  - connect()/disconnect() and connection-state notifications
class RadarBluetoothService {
  BluetoothConnection? _connection;
  final _lineController = StreamController<String>.broadcast();
  final _stateController = StreamController<bool>.broadcast();
  final _rawController = StreamController<Uint8List>.broadcast();
  String _recvBuffer = '';

  Stream<String> get lines => _lineController.stream;
  Stream<bool> get connectionState => _stateController.stream;

  /// Every raw chunk received, unparsed. The OTA flasher reads STK500's
  /// binary responses from this instead of [lines], since bootloader
  /// replies aren't newline-delimited text and would corrupt the line
  /// buffer (and vice versa -- don't run normal radar traffic and OTA
  /// flashing at the same time).
  Stream<Uint8List> get rawBytes => _rawController.stream;

  bool get isConnected => _demo || (_connection?.isConnected ?? false);

  // ---------------------------------------------------------------------
  // DEMO MODE: a simulated radar so the whole app can be tried before any
  // hardware exists. It feeds the exact same text lines the Uno sends
  // (A,<angle>,D,<cm>,<OK|ALERT> / BATT / CFG_OK / NETSTATUS), so every
  // screen works unchanged. The virtual room is 3.6 m wide and 2.6 m deep,
  // with a round table on the left, and a person who walks in towards the
  // radar and back out every 20 seconds.
  // ---------------------------------------------------------------------
  bool _demo = false;
  bool get isDemo => _demo;
  Timer? _demoTimer;
  final _rng = math.Random();
  int _demoAngle = 15;
  int _demoDir = 1;
  int _demoAlertCm = 15, _demoMin = 15, _demoMax = 165, _demoStep = 3;
  DateTime _demoStart = DateTime.now();
  DateTime _demoLastBatt = DateTime.fromMillisecondsSinceEpoch(0);

  void startDemo() {
    _demoTimer?.cancel();
    _demo = true;
    _demoStart = DateTime.now();
    _stateController.add(true);
    _demoTimer = Timer.periodic(const Duration(milliseconds: 40), (_) => _demoTick());
  }

  void stopDemo() {
    _demoTimer?.cancel();
    _demoTimer = null;
    if (_demo) {
      _demo = false;
      _stateController.add(false);
    }
  }

  /// Distance from the radar (at 0,0, facing +y) along [deg] to the nearest
  /// thing in the virtual room, in cm.
  double _demoDistance(int deg) {
    final rad = deg * math.pi / 180;
    final dx = -math.cos(rad); // 0 deg = left, 180 = right, same as the scope
    final dy = math.sin(rad);
    double best = 400;
    // walls: x = -180, x = +180, y = 260
    if (dy > 1e-6) best = math.min(best, 260 / dy);
    if (dx > 1e-6) best = math.min(best, 180 / dx);
    if (dx < -1e-6) best = math.min(best, -180 / dx);
    double hitCircle(double cx, double cy, double r) {
      final b = dx * cx + dy * cy;
      final c = cx * cx + cy * cy - r * r;
      final disc = b * b - c;
      if (disc < 0 || b < 0) return 400;
      return b - math.sqrt(disc);
    }
    best = math.min(best, hitCircle(-95, 120, 28)); // round table
    // person: walks from the door (y=250) to y=30 and back, 8 s of every 20 s
    final cycleMs = DateTime.now().difference(_demoStart).inMilliseconds % 20000;
    if (cycleMs > 6000 && cycleMs < 14000) {
      final t = (cycleMs - 6000) / 8000; // 0..1
      final y = 250 - 220 * math.sin(t * math.pi);
      best = math.min(best, hitCircle(10, y, 18));
    }
    return best;
  }

  void _demoTick() {
    if (!_demo) return;
    final d = _demoDistance(_demoAngle) + (_rng.nextDouble() * 4 - 2);
    final cm = d >= 399 ? -1 : d.round();
    final alert = cm > 0 && cm < _demoAlertCm;
    _emitDemoLine('A,$_demoAngle,D,$cm,${alert ? "ALERT" : "OK"}');
    _demoAngle += _demoDir * _demoStep;
    if (_demoAngle >= _demoMax) { _demoAngle = _demoMax; _demoDir = -1; }
    if (_demoAngle <= _demoMin) { _demoAngle = _demoMin; _demoDir = 1; }
    final now = DateTime.now();
    if (now.difference(_demoLastBatt) > const Duration(seconds: 10)) {
      _demoLastBatt = now;
      _emitDemoLine('BATT,3.92');
    }
  }

  void _emitDemoLine(String line) {
    if (_lineController.isClosed) return;
    _lineController.add(line);
  }

  void _demoHandleCommand(String command) {
    if (command.startsWith('CFG,')) {
      final v = command.substring(4).split(',').map((e) => int.tryParse(e.trim()) ?? 0).toList();
      if (v.length == 6) {
        _demoAlertCm = v[0];
        _demoMin = math.max(0, math.min(180, v[1]));
        _demoMax = math.max(_demoMin + 1, math.min(180, v[2]));
        _demoStep = math.max(1, v[3]);
        _demoAngle = _demoMin;
        _demoDir = 1;
        _emitDemoLine('CFG_OK');
      } else {
        _emitDemoLine('CFG_ERR');
      }
    } else if (command.startsWith('WIFI,')) {
      final parts = command.split(',');
      final ssid = parts.length > 1 ? parts[1] : 'HomeWiFi';
      _emitDemoLine('WIFI_FORWARDED');
      Timer(const Duration(seconds: 3), () => _emitDemoLine('NETSTATUS,STA,192.168.1.42,$ssid'));
    }
  }

  Future<List<BluetoothDevice>> getBondedDevices() async {
    return await FlutterBluetoothSerial.instance.getBondedDevices();
  }

  Future<void> connect(BluetoothDevice device) async {
    await disconnect();
    _connection = await BluetoothConnection.toAddress(device.address);
    _stateController.add(true);

    _connection!.input!.listen(
      (Uint8List data) {
        _rawController.add(data);
        _recvBuffer += utf8.decode(data, allowMalformed: true);
        while (_recvBuffer.contains('\n')) {
          final idx = _recvBuffer.indexOf('\n');
          final line = _recvBuffer.substring(0, idx).trim();
          _recvBuffer = _recvBuffer.substring(idx + 1);
          if (line.isNotEmpty) _lineController.add(line);
        }
      },
      onDone: () => _stateController.add(false),
      onError: (_) => _stateController.add(false),
    );
  }

  Future<void> disconnect() async {
    stopDemo();
    await _connection?.finish();
    _connection = null;
    _stateController.add(false);
  }

  void sendLine(String command) {
    if (_demo) {
      _demoHandleCommand(command);
      return;
    }
    final conn = _connection;
    if (conn == null || !conn.isConnected) return;
    conn.output.add(utf8.encode('$command\n'));
  }

  /// Hands raw bytes directly to the output sink, for the OTA flasher
  /// which needs to send raw STK500 binary frames, not text lines.
  void sendRaw(List<int> bytes) {
    final conn = _connection;
    if (conn == null || !conn.isConnected) return;
    conn.output.add(Uint8List.fromList(bytes));
  }

  void dispose() {
    _demoTimer?.cancel();
    _lineController.close();
    _stateController.close();
    _rawController.close();
  }
}
