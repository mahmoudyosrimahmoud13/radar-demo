import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/presence_event.dart';
import '../services/event_store.dart';
import '../services/presence_controller.dart';
import '../theme/clay_theme.dart';
import '../widgets/clay_container.dart';

/// Turns the raw entry/exit log into something actually useful: how long
/// the room was occupied today, which hours are busiest, and the trend
/// over the last week -- not just a flat list of timestamps.
class AnalyticsScreen extends StatefulWidget {
  final PresenceController presence;
  const AnalyticsScreen({super.key, required this.presence});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  List<PresenceEvent> _week = [];

  @override
  void initState() {
    super.initState();
    _load();
    widget.presence.events.listen((_) => _load());
  }

  Future<void> _load() async {
    final from = DateTime.now().subtract(Duration(days: 7));
    final events = await EventStore.instance.since(from);
    if (mounted) setState(() => _week = events);
  }

  /// Pairs each "entered" with the next "left" to estimate occupied
  /// durations. Unpaired trailing "entered" (still inside) is ignored for
  /// the total -- we only count completed visits.
  List<Duration> _occupiedDurations(List<PresenceEvent> events) {
    final durations = <Duration>[];
    DateTime? openEnter;
    for (final e in events) {
      if (e.type == PresenceEventType.entered) {
        openEnter = e.timestamp;
      } else if (e.type == PresenceEventType.left && openEnter != null) {
        durations.add(e.timestamp.difference(openEnter));
        openEnter = null;
      }
    }
    return durations;
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todaysEvents = _week.where((e) =>
        e.timestamp.year == today.year && e.timestamp.month == today.month && e.timestamp.day == today.day).toList();

    final todaysEntries = todaysEvents.where((e) => e.type == PresenceEventType.entered).length;
    final todaysDurations = _occupiedDurations(todaysEvents);
    final totalOccupiedToday = todaysDurations.fold<Duration>(Duration.zero, (a, b) => a + b);

    final hourly = List<int>.filled(24, 0);
    for (final e in _week.where((e) => e.type == PresenceEventType.entered)) {
      hourly[e.timestamp.hour]++;
    }

    final dailyCounts = <DateTime, int>{};
    for (int i = 6; i >= 0; i--) {
      final day = DateTime(today.year, today.month, today.day).subtract(Duration(days: i));
      dailyCounts[day] = 0;
    }
    for (final e in _week.where((e) => e.type == PresenceEventType.entered)) {
      final day = DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day);
      if (dailyCounts.containsKey(day)) dailyCounts[day] = dailyCounts[day]! + 1;
    }

    return ListView(
      padding: EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: _summaryCard('Entries today', '$todaysEntries', ClayColors.primary)),
            SizedBox(width: 16),
            Expanded(child: _summaryCard('Time occupied today', _fmtDuration(totalOccupiedToday), ClayColors.success)),
          ],
        ),
        SizedBox(height: 20),
        ClayContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Busiest hours (last 7 days)',
                  style: TextStyle(fontWeight: FontWeight.w700, color: ClayColors.textPrimary)),
              SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: BarChart(
                  BarChartData(
                    gridData: FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 6,
                          getTitlesWidget: (value, meta) => Text(
                            '${value.toInt()}h',
                            style: TextStyle(color: ClayColors.textSecondary, fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                    barGroups: List.generate(
                      24,
                      (h) => BarChartGroupData(x: h, barRods: [
                        BarChartRodData(
                          toY: hourly[h].toDouble(),
                          color: ClayColors.primary,
                          width: 6,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 20),
        ClayContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Entries per day (last 7 days)',
                  style: TextStyle(fontWeight: FontWeight.w700, color: ClayColors.textPrimary)),
              SizedBox(height: 12),
              SizedBox(
                height: 160,
                child: BarChart(
                  BarChartData(
                    gridData: FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final days = dailyCounts.keys.toList();
                            final idx = value.toInt();
                            if (idx < 0 || idx >= days.length) return SizedBox();
                            return Text('${days[idx].day}/${days[idx].month}',
                                style: TextStyle(color: ClayColors.textSecondary, fontSize: 10));
                          },
                        ),
                      ),
                    ),
                    barGroups: List.generate(
                      dailyCounts.length,
                      (i) => BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: dailyCounts.values.elementAt(i).toDouble(),
                          color: ClayColors.warning,
                          width: 18,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Based on a single rotating ultrasonic sensor watching the doorway angle -- '
            'a presence heuristic, not verified multi-person tracking.',
            style: TextStyle(color: ClayColors.textSecondary, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(String label, String value, Color color) {
    return ClayContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: ClayColors.textSecondary, fontSize: 12)),
          SizedBox(height: 6),
          Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }
}
