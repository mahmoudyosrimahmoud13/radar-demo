import 'dart:async';
import '../models/radar_reading.dart';
import '../models/presence_event.dart';
import 'bluetooth_service.dart';
import 'presence_detector.dart';
import 'event_store.dart';
import 'notification_service.dart';

/// Wires the pieces together: Bluetooth lines -> PresenceDetector ->
/// EventStore (persisted) + RadarNotificationService (Android notification)
/// + a broadcast stream the Events/Analytics screens listen to for live
/// updates without re-querying the database on every reading.
class PresenceController {
  final RadarBluetoothService bluetooth;
  final PresenceDetector detector = PresenceDetector();
  final RadarNotificationService notifications = RadarNotificationService();
  final _eventsController = StreamController<PresenceEvent>.broadcast();

  StreamSubscription<String>? _sub;

  PresenceController(this.bluetooth);

  Stream<PresenceEvent> get events => _eventsController.stream;

  void start() {
    _sub ??= bluetooth.lines.listen((line) {
      final reading = RadarReading.parse(line);
      if (reading == null) return;
      final event = detector.ingest(reading);
      if (event != null) _handleEvent(event);
    });
  }

  Future<void> _handleEvent(PresenceEvent event) async {
    await EventStore.instance.insert(event);
    _eventsController.add(event);
    await notifications.notifyPresenceEvent(event);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void dispose() {
    stop();
    _eventsController.close();
  }
}
