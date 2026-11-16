import '../models/radar_reading.dart';
import '../models/presence_event.dart';

/// Turns the raw sweep stream into entry/exit events.
///
/// HONEST LIMITATION: a single rotating ultrasonic sensor sees one echo
/// per angle -- the nearest surface in that direction, nothing behind it.
/// This is NOT real multi-person tracking or a security-grade sensor; it's
/// a presence heuristic: "did the pattern of near-range echoes across the
/// sweep change in a way that looks like a person-sized object showed up
/// or disappeared near the doorway angle". Good for a hobby occupancy log,
/// not for anything safety-critical.
///
/// How it works:
///  - Keeps a rolling baseline distance for each angle bucket (the "empty
///    room" reading at that angle).
///  - A reading well below its baseline (by [deltaThresholdCm] or more,
///    and closer than [maxRangeCm]) at the configured [doorwayAngleMin]..
///    [doorwayAngleMax] range counts as "occupied at this angle".
///  - Tracks how many angle-buckets in the doorway range are currently
///    "occupied". A rise from 0 -> >0 emits `entered`; a drop from >0 -> 0
///    emits `left`. [debounceReadings] consecutive confirming readings are
///    required before flipping state, to absorb sensor noise.
class PresenceDetector {
  final int doorwayAngleMin;
  final int doorwayAngleMax;
  final int deltaThresholdCm;
  final int maxRangeCm;
  final int debounceReadings;
  final int baselineBucketSizeDeg;

  final Map<int, double> _baseline = {}; // angle bucket -> running baseline cm
  int _occupiedStreak = 0;
  int _emptyStreak = 0;
  bool _currentlyOccupied = false;

  PresenceDetector({
    this.doorwayAngleMin = 60,
    this.doorwayAngleMax = 120,
    this.deltaThresholdCm = 40,
    this.maxRangeCm = 150,
    this.debounceReadings = 3,
    this.baselineBucketSizeDeg = 5,
  });

  int _bucket(int angle) => (angle ~/ baselineBucketSizeDeg) * baselineBucketSizeDeg;

  /// Feed one reading in; returns a PresenceEvent if this reading caused a
  /// state transition, otherwise null.
  PresenceEvent? ingest(RadarReading r) {
    final inDoorway = r.angle >= doorwayAngleMin && r.angle <= doorwayAngleMax;
    final bucket = _bucket(r.angle);
    final baseline = _baseline[bucket];

    // Learn/slowly adapt the baseline whenever nothing anomalous is seen,
    // so the detector tolerates furniture being moved etc. over time.
    final measured = r.distanceCm > 0 ? r.distanceCm.toDouble() : maxRangeCm.toDouble();
    if (baseline == null) {
      _baseline[bucket] = measured;
      return null;
    }

    final isAnomalous = r.distanceCm > 0 &&
        r.distanceCm < maxRangeCm &&
        (baseline - r.distanceCm) >= deltaThresholdCm;

    if (!isAnomalous) {
      // slow exponential update toward the current (empty) reading
      _baseline[bucket] = baseline * 0.95 + measured * 0.05;
    }

    if (!inDoorway) return null; // only the doorway angles decide occupancy

    if (isAnomalous) {
      _occupiedStreak++;
      _emptyStreak = 0;
    } else {
      _emptyStreak++;
      _occupiedStreak = 0;
    }

    if (!_currentlyOccupied && _occupiedStreak >= debounceReadings) {
      _currentlyOccupied = true;
      return PresenceEvent(
        type: PresenceEventType.entered,
        timestamp: r.timestamp,
        distanceCm: r.distanceCm,
        angle: r.angle,
      );
    }

    if (_currentlyOccupied && _emptyStreak >= debounceReadings) {
      _currentlyOccupied = false;
      return PresenceEvent(
        type: PresenceEventType.left,
        timestamp: r.timestamp,
        distanceCm: r.distanceCm,
        angle: r.angle,
      );
    }

    return null;
  }
}
