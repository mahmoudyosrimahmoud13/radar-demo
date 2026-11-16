import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
import '../services/radar_settings.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';

/// Sends CFG,<alertCm>,<sweepMin>,<sweepMax>,<step>,<buzzerOn>,<relayOn>
/// over Bluetooth -- the Uno saves it to EEPROM immediately (see
/// uno_radar.ino's handleCommand).
class SettingsScreen extends StatefulWidget {
  final RadarBluetoothService bluetooth;
  const SettingsScreen({super.key, required this.bluetooth});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _alertDistance = 15;
  double _sweepMin = 15;
  double _sweepMax = 165;
  double _step = 2;
  bool _buzzerOn = true;
  bool _relayOn = true;
  String? _ack;

  void _send() {
    final cmd = 'CFG,${_alertDistance.round()},${_sweepMin.round()},${_sweepMax.round()},'
        '${_step.round()},${_buzzerOn ? 1 : 0},${_relayOn ? 1 : 0}';
    widget.bluetooth.sendLine(cmd);
    RadarSettings(
      alertCm: _alertDistance.round(),
      sweepMin: _sweepMin.round(),
      sweepMax: _sweepMax.round(),
      step: _step.round(),
      buzzer: _buzzerOn,
      relay: _relayOn,
    ).save();
    setState(() => _ack = 'Sent. Waiting for CFG_OK...');
  }

  @override
  void initState() {
    super.initState();
    RadarSettings.load().then((r) {
      if (!mounted) return;
      setState(() {
        _alertDistance = r.alertCm.toDouble().clamp(5.0, 100.0).toDouble();
        _sweepMin = r.sweepMin.toDouble().clamp(0.0, 90.0).toDouble();
        _sweepMax = r.sweepMax.toDouble().clamp(90.0, 180.0).toDouble();
        _step = r.step.toDouble().clamp(1.0, 10.0).toDouble();
        _buzzerOn = r.buzzer;
        _relayOn = r.relay;
      });
    });
    widget.bluetooth.lines.listen((line) {
      if (line == 'CFG_OK' && mounted) setState(() => _ack = 'Saved on the Arduino.');
      if (line == 'CFG_ERR' && mounted) setState(() => _ack = 'The Arduino rejected that -- try again.');
    });
  }

  Widget _preset(IconData icon, String title, String sub, int alert, int min, int max, int step, bool buzzer, bool relay) {
    return Padding(
      padding: EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 120,
        child: ClayContainer(
          padding: EdgeInsets.all(12),
          onTap: () {
            setState(() {
              _alertDistance = alert.toDouble();
              _sweepMin = min.toDouble();
              _sweepMax = max.toDouble();
              _step = step.toDouble();
              _buzzerOn = buzzer;
              _relayOn = relay;
            });
            _send();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: ClayColors.primary),
              SizedBox(height: 6),
              Text(title, style: TextStyle(color: ClayColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 13)),
              Text(sub, style: TextStyle(color: ClayColors.textSecondary, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(20),
      children: [
        Text('Quick presets', style: TextStyle(fontWeight: FontWeight.w800, color: ClayColors.textPrimary)),
        SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _preset(Icons.panorama_wide_angle, 'Whole room', 'Wide, calm', 40, 15, 165, 3, false, true),
              _preset(Icons.door_front_door_outlined, 'Doorway', 'Narrow, fast', 60, 60, 120, 2, true, true),
              _preset(Icons.desk_outlined, 'Desk guard', 'Close range', 25, 30, 150, 3, true, false),
              _preset(Icons.nightlight_outlined, 'Night watch', 'Silent, relay on', 80, 15, 165, 4, false, true),
            ],
          ),
        ),
        SizedBox(height: 20),
        ClayContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _slider('Alert distance', _alertDistance, 5, 100, (v) => setState(() => _alertDistance = v), suffix: 'cm'),
              _slider('Sweep min angle', _sweepMin, 0, 90, (v) => setState(() => _sweepMin = v), suffix: '°'),
              _slider('Sweep max angle', _sweepMax, 90, 180, (v) => setState(() => _sweepMax = v), suffix: '°'),
              _slider('Sweep step', _step, 1, 10, (v) => setState(() => _step = v)),
              SwitchListTile(
                title: Text('Buzzer', style: TextStyle(color: ClayColors.textPrimary)),
                value: _buzzerOn,
                activeColor: ClayColors.primary,
                onChanged: (v) => setState(() => _buzzerOn = v),
              ),
              SwitchListTile(
                title: Text('Relay', style: TextStyle(color: ClayColors.textPrimary)),
                value: _relayOn,
                activeColor: ClayColors.primary,
                onChanged: (v) => setState(() => _relayOn = v),
              ),
            ],
          ),
        ),
        SizedBox(height: 20),
        ClayContainer(
          onTap: _send,
          child: Center(
            child: Text('Save to Arduino', style: TextStyle(color: ClayColors.primary, fontWeight: FontWeight.w700)),
          ),
        ),
        if (_ack != null) Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(_ack!, style: TextStyle(color: ClayColors.textSecondary), textAlign: TextAlign.center),
        ),
      ],
    );
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged, {String suffix = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.round()}$suffix', style: TextStyle(color: ClayColors.textPrimary)),
        Slider(value: value, min: min, max: max, activeColor: ClayColors.primary, onChanged: onChanged),
      ],
    );
  }
}
