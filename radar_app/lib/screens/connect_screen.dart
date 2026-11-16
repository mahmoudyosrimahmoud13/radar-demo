import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/bluetooth_service.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';
import '../widgets/wiring_diagram.dart';

class ConnectScreen extends StatefulWidget {
  final RadarBluetoothService bluetooth;
  final VoidCallback onConnected;
  const ConnectScreen({super.key, required this.bluetooth, required this.onConnected});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  List<BluetoothDevice> _devices = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      await [Permission.bluetoothConnect, Permission.bluetoothScan, Permission.location].request();
      final devices = await widget.bluetooth.getBondedDevices();
      setState(() => _devices = devices);
    } catch (e) {
      setState(() => _error = 'Could not list paired devices: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() { _loading = true; _error = null; });
    try {
      await widget.bluetooth.connect(device);
      widget.onConnected();
    } catch (e) {
      setState(() => _error = 'Could not connect to ${device.name}: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          SizedBox(height: 20),
          Icon(Icons.radar, size: 64, color: ClayColors.primary),
          SizedBox(height: 12),
          Text('Pair your HC-05 in Android Bluetooth settings first, then pick it here. No hardware yet? Try demo mode.',
              textAlign: TextAlign.center, style: TextStyle(color: ClayColors.textSecondary)),
          SizedBox(height: 20),
          if (_loading) Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()),
          if (_error != null) Padding(
            padding: EdgeInsets.all(12),
            child: Text(_error!, style: TextStyle(color: ClayColors.danger)),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _devices.length,
              separatorBuilder: (_, __) => SizedBox(height: 12),
              itemBuilder: (context, i) {
                final d = _devices[i];
                return ClayContainer(
                  onTap: () => _connect(d),
                  child: Row(
                    children: [
                      ClayBadge(icon: Icons.bluetooth),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.name ?? 'Unknown device', style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w600)),
                            Text(d.address, style: TextStyle(color: ClayColors.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
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
                      Text('Try demo mode', style: TextStyle(color: ClayColors.success, fontWeight: FontWeight.w700)),
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
                      Text('Wiring diagram', style: TextStyle(color: ClayColors.primary, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
        ],
      ),
    );
  }
}
