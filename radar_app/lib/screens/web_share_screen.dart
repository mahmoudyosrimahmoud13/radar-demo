import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../services/web_share_service.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';

/// Lets the phone serve the live radar page on the home WiFi, so any
/// browser (laptop, tablet, another phone) on the same network can watch.
/// The radar itself stays on Bluetooth (HC-05); the phone relays it.
class WebShareScreen extends StatefulWidget {
  final RadarBluetoothService bluetooth;
  const WebShareScreen({super.key, required this.bluetooth});

  @override
  State<WebShareScreen> createState() => _WebShareScreenState();
}

class _WebShareScreenState extends State<WebShareScreen> {
  bool _sharing = WebShareService.instance.isRunning;
  List<String> _urls = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_sharing) {
      WebShareService.instance.addresses().then((u) {
        if (mounted) setState(() => _urls = u);
      });
    }
  }

  Future<void> _toggle(bool on) async {
    setState(() => _error = null);
    try {
      if (on) {
        final urls = await WebShareService.instance.start(widget.bluetooth);
        if (!mounted) return;
        setState(() {
          _sharing = true;
          _urls = urls;
        });
      } else {
        await WebShareService.instance.stop();
        if (!mounted) return;
        setState(() {
          _sharing = false;
          _urls = [];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start sharing: $e');
    }
  }

  Widget _step(String n, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClayBadge(icon: Icons.circle, size: 26, iconColor: ClayColors.primary),
          SizedBox(width: 10),
          Expanded(
            child: Text('$n  $text', style: TextStyle(color: ClayColors.textPrimary, height: 1.4)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(20),
      children: [
        ClayContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.cast_connected, color: ClayColors.primary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('Share live radar on WiFi',
                        style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  Switch(value: _sharing, onChanged: _toggle),
                ],
              ),
              SizedBox(height: 6),
              Text(
                'This phone serves the live radar page. Anyone on the same WiFi can open it in a browser.',
                style: TextStyle(color: ClayColors.textSecondary, height: 1.4),
              ),
              if (_sharing && _urls.isEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Sharing, but no WiFi address found. Is this phone connected to WiFi?',
                      style: TextStyle(color: ClayColors.warning)),
                ),
              for (final u in _urls)
                Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: SelectableText(u,
                      style: TextStyle(color: ClayColors.primary, fontWeight: FontWeight.w800, fontSize: 18)),
                ),
              if (_error != null)
                Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: ClayColors.danger)),
                ),
            ],
          ),
        ),
        SizedBox(height: 20),
        ClayContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How to watch from another device',
                  style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w700)),
              SizedBox(height: 12),
              _step('1.', 'Connect this device to the radar, and to your home WiFi.'),
              _step('2.', 'Turn on the switch above.'),
              _step('3.', 'On a laptop or tablet on the same WiFi, type the address shown above into the browser.'),
              _step('4.', 'Keep this app open while others are watching.'),
            ],
          ),
        ),
      ],
    );
  }
}
