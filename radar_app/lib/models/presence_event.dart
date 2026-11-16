enum PresenceEventType { entered, left }

class PresenceEvent {
  final int? id;
  final PresenceEventType type;
  final DateTime timestamp;
  final int distanceCm;
  final int angle;

  PresenceEvent({
    this.id,
    required this.type,
    required this.timestamp,
    required this.distanceCm,
    required this.angle,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'type': type.name,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'distanceCm': distanceCm,
        'angle': angle,
      };

  static PresenceEvent fromMap(Map<String, Object?> m) => PresenceEvent(
        id: m['id'] as int?,
        type: (m['type'] as String) == 'entered'
            ? PresenceEventType.entered
            : PresenceEventType.left,
        timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
        distanceCm: m['distanceCm'] as int,
        angle: m['angle'] as int,
      );
}
