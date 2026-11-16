/// Parses "BATT,<volts>" lines from the Uno (raw single-cell li-ion
/// voltage, no fuel-gauge chip -- so this is a rough estimate from the
/// voltage curve, not a precise percentage).
class BatteryReading {
  final double volts;
  BatteryReading(this.volts);

  static BatteryReading? parse(String line) {
    if (!line.startsWith('BATT,')) return null;
    final v = double.tryParse(line.substring(5).trim());
    if (v == null) return null;
    return BatteryReading(v);
  }

  /// Rough single-cell li-ion percentage from voltage: ~4.2V = 100%,
  /// ~3.3V = 0% (below that the cell is over-discharged). Linear
  /// approximation, not the real discharge curve -- good enough for a
  /// "charge soon" indicator, not a precise fuel gauge.
  int get roughPercent {
    const empty = 3.3;
    const full = 4.2;
    final pct = ((volts - empty) / (full - empty) * 100).clamp(0, 100);
    return pct.round();
  }

  bool get isLow => volts < 3.5;
}
