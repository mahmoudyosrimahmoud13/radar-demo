/*
  ARDUINO RADAR — ESP-01 web display, v2
  ------------------------------------------------------------
  Flash this ONTO THE ESP-01 ITSELF (ESP8266 Arduino core —
  "Generic ESP8266 Module", flash size 1M). See the flashing
  instructions at the bottom of this file.

  New in v2: it now tries to join a home/phone WiFi network using
  credentials relayed from the phone app (via the Uno over serial),
  persisted in EEPROM so it reconnects on its own after a power cycle.
  If it has no saved credentials, or can't connect, it falls back to
  its own hotspot so you're never locked out.

  Serial line protocol from the Uno (its SoftwareSerial, 9600 baud):
    "A,<angle>,D,<distance>,<OK|ALERT>"   -> radar reading, as before
    "WIFI,<ssid>,<password>"              -> join this network and
                                              remember it

  Web page:
    /          live animated radar screen
    /data      JSON {angle, distance, alert} for the page's polling
    /status    JSON {mode: "sta"|"ap", ip, ssid} so the phone app (or
               you, in a browser) can confirm which network it's on
*/

#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <EEPROM.h>

const char* AP_SSID     = "RadarESP";
const char* AP_PASSWORD = "radar1234";

const int EEPROM_SIZE        = 128;
const int EEPROM_MAGIC_ADDR  = 0;
const byte EEPROM_MAGIC_VAL  = 0x5A;
const int EEPROM_SSID_ADDR   = 1;   // up to 32 bytes
const int EEPROM_PASS_ADDR   = 33;  // up to 64 bytes

ESP8266WebServer server(80);

int  lastAngle    = 90;
int  lastDistance = -1;
bool lastAlert    = false;
String serialBuffer = "";
bool staMode = false;

void saveCreds(const String& ssid, const String& pass) {
  EEPROM.write(EEPROM_MAGIC_ADDR, EEPROM_MAGIC_VAL);
  for (int i = 0; i < 32; i++) EEPROM.write(EEPROM_SSID_ADDR + i, i < ssid.length() ? ssid[i] : 0);
  for (int i = 0; i < 64; i++) EEPROM.write(EEPROM_PASS_ADDR + i, i < pass.length() ? pass[i] : 0);
  EEPROM.commit();
}

bool loadCreds(String& ssid, String& pass) {
  if (EEPROM.read(EEPROM_MAGIC_ADDR) != EEPROM_MAGIC_VAL) return false;
  ssid = ""; pass = "";
  for (int i = 0; i < 32; i++) { char c = EEPROM.read(EEPROM_SSID_ADDR + i); if (c == 0) break; ssid += c; }
  for (int i = 0; i < 64; i++) { char c = EEPROM.read(EEPROM_PASS_ADDR + i); if (c == 0) break; pass += c; }
  return ssid.length() > 0;
}

bool connectToWiFi(const String& ssid, const String& pass, unsigned long timeoutMs = 15000) {
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), pass.c_str());
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < timeoutMs) {
    delay(200);
  }
  return WiFi.status() == WL_CONNECTED;
}

void startAPFallback() {
  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID, AP_PASSWORD);
  staMode = false;
}

const char PAGE[] PROGMEM = R"HTML(
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Arduino Radar</title>
<style>
  body { background:#000; color:#0f0; font-family:monospace; text-align:center; margin:0; padding:10px; }
  canvas { background:#001a00; border:2px solid #0f0; border-radius:4px; }
  #status { font-size:18px; margin-top:8px; }
  .alert { color:#f33; font-weight:bold; }
</style>
</head>
<body>
<h2>ARDUINO RADAR</h2>
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
)HTML";

void handleRoot() { server.send_P(200, "text/html", PAGE); }

void handleData() {
  String json = "{\"angle\":" + String(lastAngle) +
                ",\"distance\":" + String(lastDistance) +
                ",\"alert\":" + (lastAlert ? "true" : "false") + "}";
  server.send(200, "application/json", json);
}

void handleStatus() {
  String json = "{\"mode\":\"" + String(staMode ? "sta" : "ap") +
                "\",\"ip\":\"" + (staMode ? WiFi.localIP().toString() : WiFi.softAPIP().toString()) +
                "\",\"ssid\":\"" + (staMode ? WiFi.SSID() : String(AP_SSID)) + "\"}";
  server.send(200, "application/json", json);
}

void parseRadarLine(String line) {
  int aPos = line.indexOf("A,");
  int dPos = line.indexOf(",D,");
  if (aPos < 0 || dPos < 0) return;
  int lastComma = line.lastIndexOf(',');
  if (lastComma <= dPos) return;
  lastAngle    = line.substring(aPos + 2, dPos).toInt();
  lastDistance = line.substring(dPos + 3, lastComma).toInt();
  lastAlert    = line.substring(lastComma + 1) == "ALERT";
}

void parseWifiLine(String line) {
  // WIFI,<ssid>,<password>
  int c1 = line.indexOf(',');
  int c2 = line.indexOf(',', c1 + 1);
  if (c1 < 0 || c2 < 0) return;
  String ssid = line.substring(c1 + 1, c2);
  String pass = line.substring(c2 + 1);
  saveCreds(ssid, pass);
  if (connectToWiFi(ssid, pass)) {
    staMode = true;
  } else {
    startAPFallback();
  }
}

void handleSerialLine(String line) {
  if (line.startsWith("WIFI,")) parseWifiLine(line);
  else parseRadarLine(line);
}

void setup() {
  Serial.begin(9600);
  EEPROM.begin(EEPROM_SIZE);

  String ssid, pass;
  if (loadCreds(ssid, pass) && connectToWiFi(ssid, pass)) {
    staMode = true;
  } else {
    startAPFallback();
  }

  server.on("/", handleRoot);
  server.on("/data", handleData);
  server.on("/status", handleStatus);
  server.begin();
}

void loop() {
  server.handleClient();

  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n') {
      handleSerialLine(serialBuffer);
      serialBuffer = "";
    } else if (c != '\r') {
      serialBuffer += c;
    }
  }
}

/*
  FLASHING THE ESP-01 (one-time, before wiring it into the circuit):
  1) Wire a USB-to-serial (FTDI) adapter to the ESP-01:
       FTDI 3.3V -> ESP-01 VCC and CH_PD (CH_EN)
       FTDI GND  -> ESP-01 GND and GPIO0 (GPIO0 to GND = flash mode)
       FTDI TX   -> ESP-01 RX
       FTDI RX   -> ESP-01 TX
  2) Arduino IDE: Tools > Board > "Generic ESP8266 Module",
     Flash Size "1M (FS:none OTA:~470KB)", Upload Speed 115200.
  3) Reset/power-cycle the ESP-01 with GPIO0 grounded, then Upload.
  4) After success, disconnect GPIO0 from GND and reset again — it
     now boots this program instead of flash mode.
  5) Only then wire it into the radar circuit per the wiring diagram.
*/
