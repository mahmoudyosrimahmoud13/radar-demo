import 'package:flutter/material.dart';
import 'theme/clay_theme.dart';
import 'services/bluetooth_service.dart';
import 'screens/connect_screen.dart';
import 'screens/home_shell.dart';

void main() {
  runApp(const RadarApp());
}

class RadarApp extends StatelessWidget {
  const RadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Arduino Radar',
      theme: buildClayTheme(),
      debugShowCheckedModeBanner: false,
      home: const _RootRouter(),
    );
  }
}

/// Simple two-state root: show the device picker until connected, then the
/// full app shell. Falling back here (rather than a Navigator push) also
/// means a dropped connection can route back to re-pairing cleanly.
class _RootRouter extends StatefulWidget {
  const _RootRouter();

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  final _bluetooth = RadarBluetoothService();
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _bluetooth.connectionState.listen((connected) {
      if (mounted) setState(() => _connected = connected);
    });
  }

  @override
  void dispose() {
    _bluetooth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_connected) {
      return Scaffold(
        appBar: AppBar(title: const Text('Connect to radar')),
        body: ConnectScreen(bluetooth: _bluetooth, onConnected: () => setState(() => _connected = true)),
      );
    }
    return HomeShell(bluetooth: _bluetooth);
  }
}
