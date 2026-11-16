import 'package:flutter/material.dart';
import '../models/battery_reading.dart';
import '../services/bluetooth_service.dart';
import '../services/presence_controller.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';
import 'radar_screen.dart';
import 'events_screen.dart';
import 'analytics_screen.dart';
import 'settings_screen.dart';
import 'web_share_screen.dart';
import 'ota_screen.dart';

/// Bottom-nav shell shown once Bluetooth is connected.
class HomeShell extends StatefulWidget {
  final RadarBluetoothService bluetooth;
  final VoidCallback? onOpenGuide;
  const HomeShell({super.key, required this.bluetooth, this.onOpenGuide});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final PresenceController _presence;
  int _index = 0;
  bool _connected = true;
  BatteryReading? _battery;

  static const _titles = ['Live radar', 'Events', 'Analytics', 'Settings', 'Web share', 'Firmware update'];

  @override
  void initState() {
    super.initState();
    _presence = PresenceController(widget.bluetooth)..start();
    widget.bluetooth.connectionState.listen((connected) {
      if (mounted) setState(() => _connected = connected);
    });
    widget.bluetooth.lines.listen((line) {
      final battery = BatteryReading.parse(line);
      if (battery != null && mounted) setState(() => _battery = battery);

    });
  }

  @override
  void dispose() {
    _presence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      RadarScreen(bluetooth: widget.bluetooth),
      EventsScreen(presence: _presence),
      AnalyticsScreen(presence: _presence),
      SettingsScreen(bluetooth: widget.bluetooth),
      WebShareScreen(bluetooth: widget.bluetooth),
      OtaScreen(bluetooth: widget.bluetooth),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        leading: widget.bluetooth.isDemo
            ? IconButton(
                tooltip: 'Exit demo',
                icon: Icon(Icons.logout),
                onPressed: () => widget.bluetooth.disconnect(),
              )
            : null,
        actions: [
          if (widget.bluetooth.isDemo)
            Padding(
              padding: EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: ClayColors.success, borderRadius: BorderRadius.circular(8)),
                  child: Text('DEMO', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ThemeToggleButton(),
          if (widget.onOpenGuide != null)
            IconButton(
              tooltip: 'Assembly guide',
              icon: Icon(Icons.menu_book_outlined),
              onPressed: widget.onOpenGuide,
            ),
          if (_battery != null)
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _battery!.isLow ? Icons.battery_alert : Icons.battery_std,
                      color: _battery!.isLow ? ClayColors.danger : ClayColors.textSecondary,
                      size: 20,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '${_battery!.roughPercent}%',
                      style: TextStyle(
                        color: _battery!.isLow ? ClayColors.danger : ClayColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: ClayBadge(
                icon: _connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                iconColor: _connected ? ClayColors.success : ClayColors.danger,
                size: 36,
              ),
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(begin: Offset(0.03, 0), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: ClayColors.background),
        child: NavigationBar(
          backgroundColor: ClayColors.background,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(icon: Icon(Icons.radar), label: 'Radar'),
            NavigationDestination(icon: Icon(Icons.event_note), label: 'Events'),
            NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Analytics'),
            NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
            NavigationDestination(icon: Icon(Icons.cast_connected), label: 'Share'),
            NavigationDestination(icon: Icon(Icons.memory), label: 'Firmware'),
          ],
        ),
      ),
    );
  }
}
