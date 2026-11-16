import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/clay_theme.dart';
import 'services/bluetooth_service.dart';
import 'screens/assembly_guide_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/home_shell.dart';
import 'widgets/app_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeController.instance.load();
  runApp(const RadarApp());
}

class RadarApp extends StatelessWidget {
  const RadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds the whole app (with the new palette) when dark mode flips.
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.instance,
      builder: (context, isDark, _) => MaterialApp(
        title: 'EchoSweep',
        theme: buildClayTheme(),
        debugShowCheckedModeBanner: false,
        home: _RootRouter(),
      ),
    );
  }
}

/// Opens the assembly guide on the very first launch, then the device
/// picker until connected, then the full app shell.
class _RootRouter extends StatefulWidget {
  const _RootRouter();

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  static const _guideSeenKey = 'assembly_guide_seen';

  final _bluetooth = RadarBluetoothService();
  bool _connected = false;
  bool? _guideSeen; // null while loading

  @override
  void initState() {
    super.initState();
    _bluetooth.connectionState.listen((connected) {
      if (mounted) setState(() => _connected = connected);
    });
    _loadGuideFlag();
  }

  Future<void> _loadGuideFlag() async {
    bool seen = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      seen = prefs.getBool(_guideSeenKey) ?? false;
    } catch (_) {
      seen = false;
    }
    if (mounted) setState(() => _guideSeen = seen);
  }

  Future<void> _finishGuide() async {
    setState(() => _guideSeen = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_guideSeenKey, true);
    } catch (_) {}
  }

  void _openGuide() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => AssemblyGuideScreen(onDone: () => Navigator.of(ctx).pop()),
    ));
  }

  @override
  void dispose() {
    _bluetooth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_guideSeen == null) {
      return Scaffold(body: Center(child: AppLogo(size: 120)));
    }
    if (_guideSeen == false) {
      return AssemblyGuideScreen(onDone: _finishGuide);
    }
    if (!_connected) {
      return Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppLogo(size: 28),
              SizedBox(width: 10),
              Text('EchoSweep'),
            ],
          ),
          actions: [
            ThemeToggleButton(),
            IconButton(
              tooltip: 'Assembly guide',
              icon: Icon(Icons.menu_book_outlined),
              onPressed: _openGuide,
            ),
          ],
        ),
        body: ConnectScreen(bluetooth: _bluetooth, onConnected: () => setState(() => _connected = true)),
      );
    }
    return HomeShell(bluetooth: _bluetooth, onOpenGuide: _openGuide);
  }
}
