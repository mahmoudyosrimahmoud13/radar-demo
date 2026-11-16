import 'package:flutter/material.dart';
import '../services/bluetooth_service.dart';
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
    setState(() => _ack = 'Sent. Waiting for CFG_OK...');
  }

  @override
  void initState() {
    super.initState();
    widget.bluetooth.lines.listen((line) {
      if (line == 'CFG_OK' && mounted) setState(() => _ack = 'Saved on the Arduino.');
      if (line == 'CFG_ERR' && mounted) setState(() => _ack = 'The Arduino rejected that -- try again.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ClayContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _slider('Alert distance', _alertDistance, 5, 100, (v) => setState(() => _alertDistance = v), suffix: 'cm'),
              _slider('Sweep min angle', _sweepMin, 0, 90, (v) => setState(() => _sweepMin = v), suffix: '°'),
              _slider('Sweep max angle', _sweepMax, 90, 180, (v) => setState(() => _sweepMax = v), suffix: '°'),
              _slider('Sweep step', _step, 1, 10, (v) => setState(() => _step = v)),
              SwitchListTile(
                title: const Text('Buzzer', style: TextStyle(color: ClayColors.textPrimary)),
                value: _buzzerOn,
                activeColor: ClayColors.primary,
                onChanged: (v) => setState(() => _buzzerOn = v),
              ),
              SwitchListTile(
                title: const Text('Relay', style: TextStyle(color: ClayColors.textPrimary)),
                value: _relayOn,
                activeColor: ClayColors.primary,
                onChanged: (v) => setState(() => _relayOn = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ClayContainer(
          onTap: _send,
          child: const Center(
            child: Text('Save to Arduino', style: TextStyle(color: ClayColors.primary, fontWeight: FontWeight.w700)),
          ),
        ),
        if (_ack != null) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_ack!, style: const TextStyle(color: ClayColors.textSecondary), textAlign: TextAlign.center),
        ),
      ],
    );
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged, {String suffix = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.round()}$suffix', style: const TextStyle(color: ClayColors.textPrimary)),
        Slider(value: value, min: min, max: max, activeColor: ClayColors.primary, onChanged: onChanged),
      ],
    );
  }
}
