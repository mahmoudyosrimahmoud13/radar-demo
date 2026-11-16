import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/presence_event.dart';

/// Android local notifications for presence events and sensor alerts.
/// No server/push involved -- these fire straight from the app while the
/// Bluetooth connection is live (the Arduino has no internet of its own
/// for this channel; the ESP-01's WiFi page is a separate, pull-based view).
class RadarNotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(InitializationSettings(android: androidInit));

    const channel = AndroidNotificationChannel(
      'radar_presence',
      'Room presence',
      description: 'Someone entered or left the room',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  Future<void> notifyPresenceEvent(PresenceEvent event) async {
    await init();
    final entered = event.type == PresenceEventType.entered;
    await _plugin.show(
      entered ? 1 : 2, // reuse two fixed ids so rapid events replace, don't pile up
      entered ? 'Someone entered the room' : 'Someone left the room',
      'Detected at ${event.angle}°, ${event.distanceCm}cm • '
          '${event.timestamp.hour.toString().padLeft(2, '0')}:'
          '${event.timestamp.minute.toString().padLeft(2, '0')}',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'radar_presence',
          'Room presence',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> notifyAlert(String message) async {
    await init();
    await _plugin.show(
      3,
      'Radar alert',
      message,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'radar_presence',
          'Room presence',
          importance: Importance.max,
          priority: Priority.max,
        ),
      ),
    );
  }
}
