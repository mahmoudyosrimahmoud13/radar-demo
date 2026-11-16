/// Parses the "NETSTATUS,<STA|AP>,<ip>,<ssid>" line the ESP-01 sends back
/// (relayed by the Uno) once it knows what network it's on. This is how
/// the app learns the ESP-01's IP address -- it's never guessed, and it's
/// never anything the app connects to directly; it only ever comes over
/// the existing Bluetooth link to the HC-05.
class NetworkStatus {
  final bool isHotspotMode; // true = ESP-01's own "RadarESP" fallback hotspot
  final String ip;
  final String ssid;

  NetworkStatus({required this.isHotspotMode, required this.ip, required this.ssid});

  String get webUrl => 'http://$ip/';

  static NetworkStatus? parse(String line) {
    if (!line.startsWith('NETSTATUS,')) return null;
    final parts = line.substring('NETSTATUS,'.length).split(',');
    if (parts.length < 3) return null;
    return NetworkStatus(
      isHotspotMode: parts[0].trim() == 'AP',
      ip: parts[1].trim(),
      ssid: parts[2].trim(),
    );
  }
}
