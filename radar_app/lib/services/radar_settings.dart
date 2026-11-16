import 'package:shared_preferences/shared_preferences.dart';

/// The radar's settings as last sent to the Uno, remembered on the phone,
/// so screens that temporarily change the sweep (like the Radar Lab's
/// tape measure) can put it back exactly as it was.
class RadarSettings {
  int alertCm;
  int sweepMin;
  int sweepMax;
  int step;
  bool buzzer;
  bool relay;

  RadarSettings({
    this.alertCm = 15,
    this.sweepMin = 15,
    this.sweepMax = 165,
    this.step = 2,
    this.buzzer = true,
    this.relay = true,
  });

  String toCommand() => 'CFG,$alertCm,$sweepMin,$sweepMax,$step,${buzzer ? 1 : 0},${relay ? 1 : 0}';

  static const _key = 'radar_settings';

  static Future<RadarSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key)?.split(',');
      if (v == null || v.length != 6) return RadarSettings();
      int n(int i, int d) => int.tryParse(v[i]) ?? d;
      return RadarSettings(
        alertCm: n(0, 15),
        sweepMin: n(1, 15),
        sweepMax: n(2, 165),
        step: n(3, 2),
        buzzer: n(4, 1) != 0,
        relay: n(5, 1) != 0,
      );
    } catch (_) {
      return RadarSettings();
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, '$alertCm,$sweepMin,$sweepMax,$step,${buzzer ? 1 : 0},${relay ? 1 : 0}');
    } catch (_) {}
  }
}
