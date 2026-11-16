import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../models/presence_event.dart';
import '../services/event_store.dart';
import '../services/presence_controller.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';

class EventsScreen extends StatefulWidget {
  final PresenceController presence;
  const EventsScreen({super.key, required this.presence});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  List<PresenceEvent> _events = [];
  final _fmt = DateFormat('EEE d MMM, HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _load();
    widget.presence.events.listen((_) => _load());
  }

  Future<void> _load() async {
    final events = await EventStore.instance.recent();
    if (mounted) setState(() => _events = events);
  }

  @override
  Widget build(BuildContext context) {
    if (_events.isEmpty) {
      return Center(
        child: Text('No entries or exits logged yet.', style: TextStyle(color: ClayColors.textSecondary)),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.all(20),
      itemCount: _events.length,
      separatorBuilder: (_, __) => SizedBox(height: 12),
      itemBuilder: (context, i) {
        final e = _events[i];
        final entered = e.type == PresenceEventType.entered;
        return ClayContainer(
          child: Row(
            children: [
              ClayBadge(
                icon: entered ? Icons.login : Icons.logout,
                iconColor: entered ? ClayColors.success : ClayColors.warning,
                size: 44,
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entered ? 'Someone entered' : 'Someone left',
                      style: TextStyle(fontWeight: FontWeight.w700, color: ClayColors.textPrimary),
                    ),
                    Text(
                      '${_fmt.format(e.timestamp)} • ${e.angle}°, ${e.distanceCm}cm',
                      style: TextStyle(color: ClayColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
