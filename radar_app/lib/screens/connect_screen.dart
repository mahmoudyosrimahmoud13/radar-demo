import 'dart:async';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/bluetooth_service.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';
import '../widgets/wiring_diagram.dart';

/// Pick, pair and connect to the radar's HC-05, all inside the app.
/// Paired devices are listed first; "Scan" finds unpaired ones nearby and
/// pairs them with the HC-05's PIN automatically, so Android's own
/// Bluetooth settings screen isn't needed.
class ConnectScreen extends StatefulWidget {
  final RadarBluetoothService bluetooth;
  final VoidCallback onConnected;
  const ConnectScreen({super.key, required this.bluetooth, required this.onConnected});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  List<BluetoothDevice> _paired = [];
  final Map<String, BluetoothDiscoveryResult> _found = {};
  StreamSubscription<BluetoothDiscoveryResult>? _scanSub;
  bool _scanning = false;
  String? _busyAddress; // device currently pairing/connecting
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    widget.bluetooth.stopScan();
    super.dispose();
  }

  Future<bool> _permissions() async {
    final r = await [Permission.bluetoothConnect, Permission.bluetoothScan, Permission.location].request();
    final denied = r.values.any((s) => s.isPermanentlyDenied);
    if (denied && mounted) {
      setState(() => _error = 'Bluetooth permission is blocked. Open Android settings > Apps > EchoSweep > '
          'Permissions and allow "Nearby devices" and "Location".');
    }
    return !denied;
  }

  Future<void> _refresh() async {
    setState(() => _error = null);
    try {
      await _permissions();
      final enabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
      if (!enabled) await FlutterBluetoothSerial.instance.requestEnable();
      final devices = await widget.bluetooth.getBondedDevices();
      if (mounted) setState(() => _paired = devices);
    } catch (e) {
      if (mounted) setState(() => _error = RadarBluetoothService.friendlyError(e));
    }
  }

  Future<void> _scan() async {
    if (_scanning) return;
    await _permissions();
    setState(() {
      _scanning = true;
      _found.clear();
      _error = null;
    });
    _scanSub?.cancel();
    _scanSub = widget.bluetooth.scan().listen(
      (r) {
        if (!mounted || r.device.isBonded) return;
        setState(() => _found[r.device.address] = r);
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
      onError: (_) {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  Future<void> _pairAndConnect(BluetoothDevice d) async {
    setState(() {
      _busyAddress = d.address;
      _error = null;
      _status = 'Pairing with ${d.name ?? 'device'}...';
    });
    try {
      var ok = await widget.bluetooth.pair(d, pin: '1234');
      if (!ok) {
        if (mounted) setState(() => _status = 'Trying the factory PIN 0000...');
        ok = await widget.bluetooth.pair(d, pin: '0000');
      }
      if (!ok) {
        throw Exception('Pairing was refused. If Android shows a PIN box, enter 1234 (or 0000).');
      }
      await _refresh();
      await _connect(d);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _status = null;
          _busyAddress = null;
        });
      }
    }
  }

  Future<void> _connect(BluetoothDevice d) async {
    setState(() {
      _busyAddress = d.address;
      _error = null;
      _status = 'Connecting to ${d.name ?? 'device'}... (tries 3 times)';
    });
    try {
      await widget.bluetooth.connect(d);
      if (!mounted) return;
      setState(() {
        _status = null;
        _busyAddress = null;
      });
      widget.onConnected();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _status = null;
          _busyAddress = null;
        });
      }
    }
  }

  bool _looksLikeRadar(BluetoothDevice d) {
    final n = (d.name ?? '').toLowerCase();
    return n.contains('echosweep') || n.contains('hc-05') || n.contains('hc05');
  }

  Widget _deviceTile(BluetoothDevice d, {int? rssi, required bool paired}) {
    final busy = _busyAddress == d.address;
    final radar = _looksLikeRadar(d);
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: ClayContainer(
        onTap: _busyAddress != null ? null : () => paired ? _connect(d) : _pairAndConnect(d),
        child: Row(
          children: [
            ClayBadge(icon: radar ? Icons.radar : Icons.bluetooth, iconColor: radar ? ClayColors.primary : ClayColors.textSecondary),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.name ?? 'Unknown device',
                      style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w700)),
                  Text(
                    paired ? 'Paired · tap to connect' : 'Not paired · tap to pair and connect${rssi != null ? ' · signal $rssi' : ''}',
                    style: TextStyle(color: ClayColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (busy) SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            if (!busy) Icon(Icons.chevron_right, color: ClayColors.textSecondary),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // radar-looking devices first
    final paired = List<BluetoothDevice>.of(_paired)
      ..sort((a, b) => (_looksLikeRadar(b) ? 1 : 0) - (_looksLikeRadar(a) ? 1 : 0));
    final found = _found.values.toList()
      ..sort((a, b) => (_looksLikeRadar(b.device) ? 1 : 0) - (_looksLikeRadar(a.device) ? 1 : 0));

    return ListView(
      padding: EdgeInsets.all(20),
      children: [
        Icon(Icons.radar, size: 56, color: ClayColors.primary),
        SizedBox(height: 10),
        Text('Connect to your radar', textAlign: TextAlign.center,
            style: TextStyle(color: ClayColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        Text('Power the radar on, then tap it below. Not listed? Tap Scan: the app pairs it for you (PIN 1234).',
            textAlign: TextAlign.center, style: TextStyle(color: ClayColors.textSecondary, height: 1.4)),
        SizedBox(height: 16),
        AnimatedSwitcher(
          duration: Duration(milliseconds: 250),
          child: _status != null
              ? Padding(
                  key: ValueKey(_status),
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(_status!, textAlign: TextAlign.center,
                      style: TextStyle(color: ClayColors.primary, fontWeight: FontWeight.w600)),
                )
              : SizedBox.shrink(),
        ),
        if (_error != null)
          Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: ClayContainer(
              color: ClayColors.danger.withOpacity(0.12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: ClayColors.danger),
                  SizedBox(width: 10),
                  Expanded(child: Text(_error!, style: TextStyle(color: ClayColors.textPrimary, height: 1.4))),
                ],
              ),
            ),
          ),
        Text('Paired devices', style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w800)),
        SizedBox(height: 10),
        if (paired.isEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('None yet. Use Scan below.', style: TextStyle(color: ClayColors.textSecondary)),
          ),
        for (final d in paired) _deviceTile(d, paired: true),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text('Nearby devices', style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w800)),
            ),
            if (_scanning) SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        SizedBox(height: 10),
        for (final r in found) _deviceTile(r.device, rssi: r.rssi, paired: false),
        ClayContainer(
          onTap: _scanning ? null : _scan,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bluetooth_searching, color: ClayColors.primary),
              SizedBox(width: 8),
              Text(_scanning ? 'Scanning... (about 12 s)' : 'Scan for devices',
                  style: TextStyle(color: ClayColors.primary, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        SizedBox(height: 12),
        ClayContainer(
          onTap: _refresh,
          child: Center(child: Text('Refresh paired devices', style: TextStyle(color: ClayColors.primary))),
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ClayContainer(
                onTap: () {
                  widget.bluetooth.startDemo();
                  widget.onConnected();
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_circle_outline, color: ClayColors.success),
                    SizedBox(width: 8),
                    Text('Demo mode', style: TextStyle(color: ClayColors.success, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: ClayContainer(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WiringDiagramScreen())),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cable, color: ClayColors.primary),
                    SizedBox(width: 8),
                    Text('Wiring', style: TextStyle(color: ClayColors.primary, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
