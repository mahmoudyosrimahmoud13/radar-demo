import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/bluetooth_service.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';

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
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.radar, size: 64, color: ClayColors.primary),
          const SizedBox(height: 12),
          const Text('Pair your HC-05 in Android Bluetooth settings first, then pick it here.',
              textAlign: TextAlign.center, style: TextStyle(color: ClayColors.textSecondary)),
          const SizedBox(height: 20),
          if (_loading) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()),
          if (_error != null) Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: const TextStyle(color: ClayColors.danger)),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _devices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final d = _devices[i];
                return ClayContainer(
                  onTap: () => _connect(d),
                  child: Row(
                    children: [
                      const ClayBadge(icon: Icons.bluetooth),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.name ?? 'Unknown device', style: const TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w600)),
                            Text(d.address, style: const TextStyle(color: ClayColors.textSecondary, fontSize: 12)),
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
            child: const Center(child: Text('Refresh paired devices', style: TextStyle(color: ClayColors.primary))),
          ),
        ],
      ),
    );
  }
}
