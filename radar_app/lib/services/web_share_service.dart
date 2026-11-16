import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/radar_reading.dart';
import 'bluetooth_service.dart';

/// Serves the live radar web page from the PHONE, so any browser on the
/// same WiFi can watch the radar. The radar talks to the phone over
/// Bluetooth (HC-05); the phone relays the readings to the page.
///
/// Runs while the app is open (Android pauses it when the app is in the
/// background for a long time).
class WebShareService {
  WebShareService._();
  static final WebShareService instance = WebShareService._();

  static const int port = 8080;

  HttpServer? _server;
  StreamSubscription<String>? _sub;
  RadarReading? _latest;

  bool get isRunning => _server != null;

  Future<List<String>> start(RadarBluetoothService bluetooth) async {
    if (_server == null) {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      _server!.listen(_handle);
    }
    _sub ??= bluetooth.lines.listen((line) {
      final r = RadarReading.parse(line);
      if (r != null) _latest = r;
    });
    return addresses();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await _server?.close(force: true);
    _server = null;
  }

  /// The phone's WiFi addresses, as full URLs to open in a browser.
  Future<List<String>> addresses() async {
    final urls = <String>[];
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      for (final i in interfaces) {
        for (final a in i.addresses) {
          urls.add('http://${a.address}:$port/');
        }
      }
    } catch (_) {}
    return urls;
  }

  void _handle(HttpRequest req) {
    final path = req.uri.path;
    final res = req.response;
    res.headers.set('Access-Control-Allow-Origin', '*');
    if (path == '/data') {
      final r = _latest;
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({
        'angle': r?.angle ?? 90,
        'distance': r?.distanceCm ?? -1,
        'alert': r?.alert ?? false,
      }));
    } else if (path == '/status') {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'mode': 'phone', 'port': port}));
    } else {
      res.headers.contentType = ContentType.html;
      res.write(_page);
    }
    res.close();
  }
}

const String _page = r'''<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>EchoSweep</title>
<style>
  body { background:#000; color:#0f0; font-family:monospace; text-align:center; margin:0; padding:10px; }
  canvas { background:#001a00; border:2px solid #0f0; border-radius:4px; }
  #status { font-size:18px; margin-top:8px; }
  .alert { color:#f33; font-weight:bold; }
</style>
</head>
<body>
<h2>ECHOSWEEP LIVE RADAR</h2>
<canvas id="radar" width="400" height="220"></canvas>
<div id="status">Angle: -- &nbsp; Distance: -- cm</div>
<script>
const canvas = document.getElementById('radar');
const ctx = canvas.getContext('2d');
const cx = 200, cy = 210, maxR = 190, maxDist = 200;

function drawBackground(){
  ctx.clearRect(0,0,400,220);
  ctx.strokeStyle = '#0f0';
  ctx.globalAlpha = 0.35;
  for (let r = maxR/4; r <= maxR; r += maxR/4){
    ctx.beginPath();
    ctx.arc(cx, cy, r, Math.PI, 2*Math.PI);
    ctx.stroke();
  }
  for (let a = 0; a <= 180; a += 30){
    const rad = Math.PI - (a*Math.PI/180);
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.lineTo(cx + maxR*Math.cos(rad), cy - maxR*Math.sin(rad));
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
}

function draw(angle, distance, alert){
  drawBackground();
  const rad = Math.PI - (angle*Math.PI/180);
  ctx.strokeStyle = alert ? '#f33' : '#0f0';
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(cx, cy);
  ctx.lineTo(cx + maxR*Math.cos(rad), cy - maxR*Math.sin(rad));
  ctx.stroke();
  if (distance > 0 && distance <= maxDist){
    const r = (distance/maxDist)*maxR;
    ctx.fillStyle = alert ? '#f33' : '#0f0';
    ctx.beginPath();
    ctx.arc(cx + r*Math.cos(rad), cy - r*Math.sin(rad), 5, 0, 2*Math.PI);
    ctx.fill();
  }
  const statusEl = document.getElementById('status');
  statusEl.innerHTML = 'Angle: ' + angle + '&deg; &nbsp; Distance: ' +
    (distance > 0 ? distance + ' cm' : '--') +
    (alert ? ' <span class="alert">ALERT</span>' : '');
}

async function poll(){
  try {
    const res = await fetch('/data');
    const d = await res.json();
    draw(d.angle, d.distance, d.alert);
  } catch (e) {}
  setTimeout(poll, 100);
}
drawBackground();
poll();
</script>
</body>
</html>
''';
