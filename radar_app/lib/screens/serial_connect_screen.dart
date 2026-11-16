import 'dart:async';
import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';
import '../widgets/wiring_diagram.dart';

/// Linux desktop connect screen: USB cable only, no Bluetooth.
/// Lists /dev/ttyACM* and /dev/ttyUSB* and refreshes every 2 seconds, so
/// plugging the Uno in makes it show up by itself.
class SerialConnectScreen extends StatefulWidget {
  final RadarBluetoothService bluetooth;
  final VoidCallback onConnected;
  const SerialConnectScreen({super.key, required this.bluetooth, required this.onConnected});

  @override
  State<SerialConnectScreen> createState() => _SerialConnectScreenState();
}

class _SerialConnectScreenState extends State<SerialConnectScreen> {
  List<String> _ports = [];
  String? _busy;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final ports = await RadarBluetoothService.listSerialPorts();
    if (mounted) setState(() => _ports = ports);
  }

  Future<void> _connect(String port) async {
    setState(() {
      _busy = port;
      _error = null;
    });
    try {
      await widget.bluetooth.connectSerial(port);
      _poll?.cancel();
      widget.onConnected();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _portTile(String port) {
    final busy = _busy == port;
    final acm = port.contains('ttyACM');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClayContainer(
        onTap: _busy != null ? null : () => _connect(port),
        child: Row(
          children: [
            ClayBadge(icon: Icons.usb, iconColor: acm ? ClayColors.primary : ClayColors.textSecondary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(port, style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w700)),
                  Text(
                    busy
                        ? 'Opening... the Uno restarts, give it 2 seconds'
                        : (acm ? 'Arduino Uno (USB) · tap to connect' : 'USB serial adapter · tap to connect'),
                    style: TextStyle(color: ClayColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (busy) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            if (!busy) Icon(Icons.chevron_right, color: ClayColors.textSecondary),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(Icons.usb, size: 56, color: ClayColors.primary),
            const SizedBox(height: 10),
            Text('Connect over USB', textAlign: TextAlign.center,
                style: TextStyle(color: ClayColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Plug the Uno into this computer with its USB cable and pick its port below. '
              'Unplug the HC-05 TX/RX wires (pins 0 and 1) first, they share the same line as USB.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ClayColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClayContainer(
                  color: ClayColors.danger.withOpacity(0.12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, color: ClayColors.danger),
                      const SizedBox(width: 10),
                      Expanded(child: SelectableText(_error!, style: TextStyle(color: ClayColors.textPrimary, height: 1.4))),
                    ],
                  ),
                ),
              ),
            Text('USB ports', style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (_ports.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('No Arduino found yet. Plug it in, it shows up here by itself.',
                    style: TextStyle(color: ClayColors.textSecondary)),
              ),
            for (final p in _ports) _portTile(p),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClayContainer(
                    onTap: () {
                      _poll?.cancel();
                      widget.bluetooth.startDemo();
                      widget.onConnected();
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_circle_outline, color: ClayColors.success),
                        const SizedBox(width: 8),
                        Text('Demo mode', style: TextStyle(color: ClayColors.success, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClayContainer(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WiringDiagramScreen())),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cable, color: ClayColors.primary),
                        const SizedBox(width: 8),
                        Text('Wiring', style: TextStyle(color: ClayColors.primary, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
