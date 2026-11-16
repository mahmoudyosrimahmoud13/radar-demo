import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/network_status.dart';
import '../services/bluetooth_service.dart';
import '../services/web_share_service.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';

/// Sends "WIFI,<ssid>,<password>" over Bluetooth to the Uno, which
/// forwards it to the ESP-01. The ESP-01 then tries to join that network
/// and remembers it (EEPROM) for next boot, falling back to its own
/// "RadarESP" hotspot if the credentials don't work.
///
/// The ESP-01 can only tell us its IP by sending it back over the same
/// Bluetooth link (as a "NETSTATUS,..." line) -- the app never connects
/// to the ESP-01 directly to ask. This screen listens for that line and
/// shows it, with a button to open the resulting web page.
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
  NetworkStatus? _network;
  bool _obscure = true;
  bool _sharing = WebShareService.instance.isRunning;
  List<String> _shareUrls = [];
  String? _shareError;

  Future<void> _toggleShare(bool on) async {
    setState(() => _shareError = null);
    try {
      if (on) {
        final urls = await WebShareService.instance.start(widget.bluetooth);
        if (!mounted) return;
        setState(() {
          _sharing = true;
          _shareUrls = urls;
        });
      } else {
        await WebShareService.instance.stop();
        if (!mounted) return;
        setState(() {
          _sharing = false;
          _shareUrls = [];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _shareError = 'Could not start sharing: $e');
    }
  }

  Widget _shareCard() {
    return Padding(
      padding: EdgeInsets.only(bottom: 20),
      child: ClayContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cast_connected, color: ClayColors.primary),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Share radar on WiFi',
                      style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w700)),
                ),
                Switch(value: _sharing, onChanged: _toggleShare),
              ],
            ),
            Text(
              'No ESP-01 needed: this phone serves the live radar page. Open the address below '
              'in any browser on the same WiFi. Keep this app open while sharing.',
              style: TextStyle(color: ClayColors.textSecondary, fontSize: 12, height: 1.4),
            ),
            if (_sharing && _shareUrls.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Sharing, but no WiFi address found. Is the phone connected to WiFi?',
                    style: TextStyle(color: ClayColors.warning)),
              ),
            for (final u in _shareUrls)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: SelectableText(u,
                    style: TextStyle(color: ClayColors.primary, fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            if (_shareError != null)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(_shareError!, style: TextStyle(color: ClayColors.danger)),
              ),
          ],
        ),
      ),
    );
  }

  void _send() {
    final ssid = _ssidCtrl.text.trim();
    final pass = _passCtrl.text;
    if (ssid.isEmpty) {
      setState(() => _status = 'Enter a network name first.');
      return;
    }
    widget.bluetooth.sendLine('WIFI,$ssid,$pass');
    setState(() {
      _status = 'Sent to the Arduino -- give it about 15 seconds to try '
          'connecting. Its address will show up below automatically.';
      _network = null; // old address is stale until we hear otherwise
    });
  }

  @override
  void initState() {
    super.initState();
    widget.bluetooth.lines.listen((line) {
      if (!mounted) return;
      if (line == 'WIFI_FORWARDED') {
        setState(() => _status = 'Credentials forwarded to the ESP-01. '
            'Waiting to hear back...');
        return;
      }
      final net = NetworkStatus.parse(line);
      if (net != null) {
        setState(() {
          _network = net;
          _status = null;
        });
      }
    });
  }

  Future<void> _openWebPage() async {
    final net = _network;
    if (net == null) return;
    final uri = Uri.parse(net.webUrl);
    // Call launchUrl directly: canLaunchUrl() returns false on Android 11+
    // for web links unless the manifest declares <queries>, even when a
    // browser is installed and launching would work fine.
    bool opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      setState(() => _status = "Couldn't open ${net.webUrl} -- if you're on "
          "the RadarESP hotspot, make sure your phone's WiFi is joined to "
          "it first (Bluetooth alone won't reach that page).");
    }
  }

  @override
  Widget build(BuildContext context) {
    final net = _network;
    return ListView(
      padding: EdgeInsets.all(20),
      children: [
          _shareCard(),
          if (net != null)
            Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: ClayContainer(
                onTap: _openWebPage,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          net.isHotspotMode ? Icons.wifi_tethering : Icons.wifi,
                          color: ClayColors.primary,
                        ),
                        SizedBox(width: 8),
                        Text(
                          net.isHotspotMode ? 'Running its own hotspot' : 'Connected to ${net.ssid}',
                          style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(net.webUrl, style: TextStyle(color: ClayColors.primary)),
                    SizedBox(height: 4),
                    Text(
                      net.isHotspotMode
                          ? 'Join your phone\'s WiFi to "${net.ssid}" first, then tap to open this page.'
                          : 'Tap to open the live radar page (your phone needs to be on the same WiFi network).',
                      style: TextStyle(color: ClayColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ClayContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WiFi network name', style: TextStyle(color: ClayColors.textSecondary, fontSize: 12)),
                TextField(
                  controller: _ssidCtrl,
                  style: TextStyle(color: ClayColors.textPrimary),
                  decoration: InputDecoration(border: InputBorder.none),
                ),
                Divider(color: ClayColors.shadowDark),
                SizedBox(height: 8),
                Text('Password', style: TextStyle(color: ClayColors.textSecondary, fontSize: 12)),
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  style: TextStyle(color: ClayColors.textPrimary),
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
          SizedBox(height: 20),
          ClayContainer(
            onTap: _send,
            child: Center(
              child: Text('Send to Arduino', style: TextStyle(color: ClayColors.primary, fontWeight: FontWeight.w700)),
            ),
          ),
          if (_status != null)
            Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(_status!, style: TextStyle(color: ClayColors.textSecondary), textAlign: TextAlign.center),
            ),
      ],
    );
  }
}
