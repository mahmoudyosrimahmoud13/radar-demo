import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';

/// Sends "WIFI,<ssid>,<password>" over Bluetooth to the Uno, which
/// forwards it to the ESP-01. The ESP-01 then tries to join that network
/// and remembers it (EEPROM) for next boot, falling back to its own
/// "RadarESP" hotspot if the credentials don't work.
class WifiSetupScreen extends StatefulWidget {
  final RadarBluetoothService bluetooth;
  const WifiSetupScreen({super.key, required this.bluetooth});

  @override
  State<WifiSetupScreen> createState() => _WifiSetupScreenState();
}

class _WifiSetupScreenState extends State<WifiSetupScreen> {
  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String? _status;
  bool _obscure = true;

  void _send() {
    final ssid = _ssidCtrl.text.trim();
    final pass = _passCtrl.text;
    if (ssid.isEmpty) {
      setState(() => _status = 'Enter a network name first.');
      return;
    }
    widget.bluetooth.sendLine('WIFI,$ssid,$pass');
    setState(() => _status = 'Sent to the Arduino -- check the ESP-01\'s web '
        'page at its new address once it reconnects, or 192.168.4.1 if it '
        'had to fall back to its own hotspot.');
  }

  @override
  void initState() {
    super.initState();
    widget.bluetooth.lines.listen((line) {
      if (line == 'WIFI_FORWARDED' && mounted) {
        setState(() => _status = 'Credentials forwarded to the ESP-01. Give it ~15 seconds to try connecting.');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          ClayContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('WiFi network name', style: TextStyle(color: ClayColors.textSecondary, fontSize: 12)),
                TextField(
                  controller: _ssidCtrl,
                  style: const TextStyle(color: ClayColors.textPrimary),
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
                const Divider(color: ClayColors.shadowDark),
                const SizedBox(height: 8),
                const Text('Password', style: TextStyle(color: ClayColors.textSecondary, fontSize: 12)),
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  style: const TextStyle(color: ClayColors.textPrimary),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: ClayColors.textSecondary),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ClayContainer(
            onTap: _send,
            child: const Center(
              child: Text('Send to Arduino', style: TextStyle(color: ClayColors.primary, fontWeight: FontWeight.w700)),
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_status!, style: const TextStyle(color: ClayColors.textSecondary), textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }
}
