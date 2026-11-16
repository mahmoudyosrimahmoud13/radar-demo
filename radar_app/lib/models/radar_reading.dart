/// One sweep reading from the Arduino: "A,<angle>,D,<distance>,<OK|ALERT>"
class RadarReading {
  final int angle;
  final int distanceCm; // -1 means "no echo / nothing in range"
  final bool alert;
  final DateTime timestamp;

  RadarReading({
    required this.angle,
    required this.distanceCm,
    required this.alert,
    required this.timestamp,
  });

  /// Returns null if the line isn't a valid radar reading (could be an
  /// ack like "CFG_OK" instead).
  static RadarReading? parse(String line) {
    final aPos = line.indexOf('A,');
    final dPos = line.indexOf(',D,');
    if (aPos < 0 || dPos < 0) return null;
    final lastComma = line.lastIndexOf(',');
    if (lastComma <= dPos) return null;

    final angle = int.tryParse(line.substring(aPos + 2, dPos));
    final distance = int.tryParse(line.substring(dPos + 3, lastComma));
    if (angle == null || distance == null) return null;

    final flag = line.substring(lastComma + 1).trim();
    return RadarReading(
      angle: angle,
      distanceCm: distance,
      alert: flag == 'ALERT',
      timestamp: DateTime.now(),
    );
  }
}
