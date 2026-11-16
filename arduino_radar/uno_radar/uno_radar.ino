/*
  ARDUINO RADAR — Main controller (runs on the Arduino Uno)
  ------------------------------------------------------------
  v2: adds a Bluetooth command channel so a phone app can change
  settings live, relay WiFi credentials to the ESP-01, and trigger
  a wireless firmware update (see the big OTA warning below).

  What it does every loop:
  - Sweeps a servo back and forth across SWEEP_MIN..SWEEP_MAX
  - At every angle, pings the HC-SR04 for distance
  - If something is closer than cfg.alertDistanceCm: buzzer + relay ON
  - Streams every reading out BOTH:
      1) Hardware Serial (pins 0/1) -> HC-05 (Bluetooth, phone app)
      2) SoftwareSerial (pins 10/11) -> ESP-01 (WiFi web radar)
    Line format:  A,<angle>,D,<distance_cm>,<OK|ALERT>

  Phone -> Uno commands (received on hardware Serial from HC-05),
  one per line:
      CFG,<alertCm>,<sweepMin>,<sweepMax>,<step>,<buzzerOn 0/1>,<relayOn 0/1>
          -> updates settings, saves to EEPROM, replies "CFG_OK"
      WIFI,<ssid>,<password>
          -> forwarded as-is to the ESP-01 over SoftwareSerial, which
             tries to join that network; Uno immediately replies
             "WIFI_FORWARDED" just to confirm it relayed the command.
             The ESP-01 then reports the real outcome a moment later
             (and again every ~5s afterwards, so it's never silent even
             if the app connects after the ESP-01 already joined WiFi
             on its own) as its own line, which the Uno relays as-is:
      NETSTATUS,<STA|AP>,<ip>,<ssid>
          -> relayed straight through from the ESP-01: STA means it
             joined your WiFi (ip is its DHCP address on your network);
             AP means it fell back to its own "RadarESP" hotspot
             (ip is always 192.168.4.1)
      ENTERUPDATE
          -> replies "RESETTING", then pulses the auto-reset pin to
             drop into the bootloader so the phone app can flash new
             firmware. See the giant warning block below before you
             wire this up or use it.

  Also streamed periodically (every ~10s) on both links:
      BATT,<volts>   e.g. "BATT,3.87" -- raw li-ion cell voltage

  A single-digit 7-segment display shows a "closer = lower number"
  countdown live (9 = nothing nearby, 0 = right at the alert distance),
  blinking 0 while actually in ALERT -- no phone needed to see it.

  ====================================================================
  BLUETOOTH FIRMWARE UPDATE (OTA) — READ THIS BEFORE WIRING IT UP
  ====================================================================
  This works by: (1) wiring the HC-05 onto the Uno's hardware serial
  pins (0/1) — the same pins the bootloader uses — so the phone's
  Bluetooth link IS the programming link, no different from a USB
  cable electrically; (2) wiring a spare pin through a small capacitor
  to RESET, the same trick USB-serial adapters use (their DTR line),
  so the sketch can reset itself into the bootloader on command;
  (3) the phone app then speaks the STK500v1 protocol (the same one
  avrdude/USB-upload uses) to rewrite flash, page by page.

  This is genuinely more fragile than USB upload:
    - If the Bluetooth link drops mid-flash, the board can be left
      with half-written, non-functional firmware ("bricked" until you
      reflash over USB — it is NOT permanently destroyed, the chip is
      fine, you just need a USB cable and the Arduino IDE to recover).
    - Classic Bluetooth (HC-05) adds latency/retries a USB cable
      doesn't have, so the bootloader's timeouts are tighter relative
      to the link than they are over USB.
    - ALWAYS test a new .hex by uploading it over USB first. Only use
      the wireless path once you know the firmware itself is good —
      BT-OTA should update firmware you've already proven works, not
      be your first way of testing new code.
    - Keep a USB cable within reach whenever you use this feature.

  Auto-reset wiring (required for OTA, optional if you never use it):
      Uno pin D4  --[ 0.1uF ceramic capacitor, in series ]--  RESET pin
  That's it — no transistor needed. A HIGH->LOW->HIGH pulse on D4
  couples a brief dip through the capacitor onto RESET (which already
  has a pull-up resistor on the Uno board), long enough to reset the
  chip into the bootloader without needing to hold RESET down.
  ====================================================================

  WIRING (v3):
  - HC-05: your module is the BARE chip board (no breakout PCB), which
    means it is NOT 5V tolerant on VCC like the usual "ZS-040" breakout
    -- it needs its OWN 3.3V regulator, same as the ESP-01. Don't power
    it from the Uno's 5V pin.
      VCC  -> a 3.3V regulator (separate from or shared with the ESP-01's,
              as long as it has enough current budget for both)
      GND  -> common ground with everything else
      TXD  -> Uno D0 (RX, direct -- 3.3V into a 5V input is safe)
      RXD  <- Uno D1 (TX, THROUGH a voltage divider -- Uno is 5V, this
               module's RX wants 3.3V max)
      KEY/34 -> leave unconnected for normal use. To enter AT config
               mode once (to set the baud to 115200, see below), wire
               it to 3.3V (not 5V) *before* powering the module on,
               configure it, then disconnect KEY and power-cycle again.
      STATE  -> optional: through a resistor (~1k) to an LED to ground,
               as a connection-status light (blinks while unpaired,
               solid once the phone connects). Use this if the loose
               red 2-leaded part in your parts pile is a plain LED.
    IMPORTANT: configure this module to 115200 baud ONCE via AT mode
    (see KEY pin above) so it matches the Optiboot bootloader's rate --
    otherwise OTA sync will never succeed. Normal operation also runs
    at 115200 now (see Serial.begin below).
  - ESP-01: on SoftwareSerial pins D10 (RX, from ESP-01 TX, direct) /
            D11 (TX, to ESP-01 RX, through a divider -- also 3.3V logic).
  - Servo: D9. HC-SR04: TRIG D7, ECHO D6. Buzzer: D8. Relay: D5.
  - Auto-reset capacitor: D4 -> RESET (see above).
  - 7-segment display (single digit, see DISPLAY section below):
    segments a..g on D2, D3, D12, D13, A0, A1, A2 -- each through its
    own ~220-330 ohm current-limiting resistor. Common pin -> GND if
    it's common-cathode, or -> 5V if common-anode (try it; if the
    digit looks dim/inverted, you have the type backwards -- flip
    COMMON_CATHODE below and swap the common pin's wiring).
  - Battery voltage sense: a tap from the li-ion cell's positive lead
    into A3 directly is fine (a single cell tops out around 4.2V,
    under the Uno's 5V reference) -- or add a divider for headroom if
    you ever swap to a higher-voltage pack.
  - Power: the ESP-01 and the bare HC-05 each need their own 3.3V
    regulator (don't share the Uno's onboard 3.3V pin -- not enough
    current for WiFi/BT radio bursts). A single li-ion cell cannot
    power the Uno directly -- its 3.0-4.2V is below what VIN needs for
    the onboard 5V regulator to work, so you need a cheap 3.7V-to-5V
    boost converter module (not in your current parts pile -- a ~$1
    "MT3608" or similar boost board) feeding the Uno's 5V pin directly
    (bypassing VIN), and feed the two 3.3V regulators off that boosted
    5V rail rather than off the raw battery. Also ideally add a TP4056
    (or similar) charge-protection module between the cell and
    everything else, rather than charging it with no protection
    circuit at all.
*/

#include <Servo.h>
#include <SoftwareSerial.h>
#include <EEPROM.h>

// ---- Pin assignments ----
const int SERVO_PIN     = 9;
const int TRIG_PIN      = 7;
const int ECHO_PIN      = 6;
const int BUZZER_PIN    = 8;
const int RELAY_PIN     = 5;
const int ESP_RX_PIN    = 10; // SoftwareSerial RX <- ESP-01 TX
const int ESP_TX_PIN    = 11; // SoftwareSerial TX -> ESP-01 RX (through divider)
const int AUTORESET_PIN = 4;  // -> 0.1uF cap -> RESET

// 7-segment display: a,b,c,d,e,f,g (no decimal point)
const int SEG_PINS[7] = {2, 3, 12, 13, A0, A1, A2};
const bool COMMON_CATHODE = true; // flip to false + rewire common pin to 5V if your digit is common-anode

const int BATTERY_SENSE_PIN = A3;
// Set to true only if a li-ion cell's + is wired to A3. With a USB power
// bank (no cell wired), leave false so the app doesn't show a fake level.
const bool HAS_BATTERY_SENSE = false;
const unsigned long BATTERY_REPORT_INTERVAL_MS = 10000; // don't spam the link with battery readings
unsigned long lastBatteryReportAt = 0;

const int EEPROM_MAGIC_ADDR = 0;
const byte EEPROM_MAGIC_VAL = 0xA5; // marks "config has been saved before"
const int EEPROM_CFG_ADDR   = 1;

struct Config {
  int  alertDistanceCm = 15;
  int  sweepMin = 15;
  int  sweepMax = 165;
  int  sweepStep = 2;
  bool buzzerEnabled = true;
  bool relayEnabled = true;
};

Config cfg;
Servo radarServo;
SoftwareSerial espSerial(ESP_RX_PIN, ESP_TX_PIN);

int angle;
int step_;
String btLineBuffer = "";
String espLineBuffer = "";

void loadConfig() {
  if (EEPROM.read(EEPROM_MAGIC_ADDR) == EEPROM_MAGIC_VAL) {
    EEPROM.get(EEPROM_CFG_ADDR, cfg);
  } else {
    saveConfig(); // first boot: write the defaults
  }
}

void saveConfig() {
  EEPROM.write(EEPROM_MAGIC_ADDR, EEPROM_MAGIC_VAL);
  EEPROM.put(EEPROM_CFG_ADDR, cfg);
}

void setup() {
  Serial.begin(115200);   // to HC-05 (and the Optiboot bootloader on reset)
  espSerial.begin(9600);  // to ESP-01

  pinMode(AUTORESET_PIN, OUTPUT);
  digitalWrite(AUTORESET_PIN, HIGH);

  loadConfig();

  radarServo.attach(SERVO_PIN);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);

  for (int i = 0; i < 7; i++) pinMode(SEG_PINS[i], OUTPUT);
  pinMode(BATTERY_SENSE_PIN, INPUT);

  angle = cfg.sweepMin;
  step_ = cfg.sweepStep;
}

// Segment patterns for digits 0-9, one bit per segment a..g (bit0=a .. bit6=g)
const byte DIGIT_PATTERNS[10] = {
  0b0111111, // 0
  0b0000110, // 1
  0b1011011, // 2
  0b1001111, // 3
  0b1100110, // 4
  0b1101101, // 5
  0b1111101, // 6
  0b0000111, // 7
  0b1111111, // 8
  0b1101111, // 9
};

void showDigit(int digit) {
  if (digit < 0 || digit > 9) {
    for (int i = 0; i < 7; i++) digitalWrite(SEG_PINS[i], COMMON_CATHODE ? LOW : HIGH);
    return;
  }
  byte pattern = DIGIT_PATTERNS[digit];
  for (int i = 0; i < 7; i++) {
    bool segmentOn = bitRead(pattern, i);
    digitalWrite(SEG_PINS[i], (segmentOn == COMMON_CATHODE) ? HIGH : LOW);
  }
}

// Shows a "closer = lower number" countdown: 9 = nothing near, 0 = at the
// alert threshold. Blinks 0 when actually in ALERT so it reads differently
// from "just reached the threshold".
void updateDisplay(long distanceCm, bool alert) {
  if (alert) {
    bool blinkOn = (millis() / 300) % 2 == 0;
    showDigit(blinkOn ? 0 : -1);
    return;
  }
  if (distanceCm <= 0) {
    showDigit(9); // nothing in range = "all clear"
    return;
  }
  long farEdge = (long)cfg.alertDistanceCm * 5; // tune this multiplier to taste
  int level = map(constrain(distanceCm, cfg.alertDistanceCm, farEdge), cfg.alertDistanceCm, farEdge, 0, 9);
  showDigit(level);
}

float readBatteryVoltage() {
  int raw = analogRead(BATTERY_SENSE_PIN);
  return raw * (5.0 / 1023.0); // direct read, no divider -- see wiring notes
}

long readDistanceCM() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  long duration = pulseIn(ECHO_PIN, HIGH, 30000);
  if (duration == 0) return -1;
  long distance = duration * 0.0343 / 2;
  if (distance > 400) return -1;
  return distance;
}

void triggerBootloaderReset() {
  Serial.println("RESETTING");
  Serial.flush();
  delay(50);
  digitalWrite(AUTORESET_PIN, LOW);
  delay(5);
  digitalWrite(AUTORESET_PIN, HIGH);
  // the chip resets here; nothing after this line will run
}

void handleCommand(String line) {
  line.trim();
  if (line.length() == 0) return;

  if (line.startsWith("CFG,")) {
    // CFG,<alertCm>,<sweepMin>,<sweepMax>,<step>,<buzzerOn>,<relayOn>
    int vals[6];
    int idx = 0;
    int start = 4;
    for (int i = 0; i < 6 && idx < 6; i++) {
      int comma = line.indexOf(',', start);
      String piece = (comma == -1) ? line.substring(start) : line.substring(start, comma);
      vals[idx++] = piece.toInt();
      if (comma == -1) break;
      start = comma + 1;
    }
    if (idx == 6) {
      cfg.alertDistanceCm = vals[0];
      cfg.sweepMin        = vals[1];
      cfg.sweepMax        = vals[2];
      cfg.sweepStep       = max(1, vals[3]);
      cfg.buzzerEnabled   = vals[4] != 0;
      cfg.relayEnabled    = vals[5] != 0;
      saveConfig();
      Serial.println("CFG_OK");
    } else {
      Serial.println("CFG_ERR");
    }
    return;
  }

  if (line.startsWith("WIFI,")) {
    espSerial.println(line); // ESP-01 sketch parses the same "WIFI,ssid,pass" line
    Serial.println("WIFI_FORWARDED");
    return;
  }

  if (line == "ENTERUPDATE") {
    triggerBootloaderReset();
    return;
  }
}

void pollBluetoothCommands() {
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n') {
      handleCommand(btLineBuffer);
      btLineBuffer = "";
    } else if (c != '\r') {
      btLineBuffer += c;
      if (btLineBuffer.length() > 120) btLineBuffer = ""; // guard against junk
    }
  }
}

// Anything the ESP-01 sends back (currently just its "NETSTATUS,..." line)
// gets relayed straight to the HC-05 so the phone app sees it too.
void pollEspMessages() {
  while (espSerial.available()) {
    char c = espSerial.read();
    if (c == '\n') {
      if (espLineBuffer.startsWith("NETSTATUS,")) {
        Serial.println(espLineBuffer); // -> HC-05 -> phone app
      } else if (espLineBuffer.startsWith("CFG,")) {
        handleCommand(espLineBuffer);  // settings sent from the app over WiFi
      }
      espLineBuffer = "";
    } else if (c != '\r') {
      espLineBuffer += c;
      if (espLineBuffer.length() > 80) espLineBuffer = ""; // guard against junk
    }
  }
}

void loop() {
  pollBluetoothCommands();
  pollEspMessages();

  radarServo.write(angle);
  delay(25);

  long distance = readDistanceCM();
  bool alert = (distance > 0 && distance < cfg.alertDistanceCm);

  String line = "A," + String(angle) + ",D," + String(distance) + "," + (alert ? "ALERT" : "OK");
  Serial.println(line);     // -> HC-05 -> phone app
  espSerial.println(line);  // -> ESP-01 -> web radar page

  if (alert && cfg.buzzerEnabled) tone(BUZZER_PIN, 2000); else noTone(BUZZER_PIN);
  digitalWrite(RELAY_PIN, (alert && cfg.relayEnabled) ? HIGH : LOW);

  updateDisplay(distance, alert);

  if (HAS_BATTERY_SENSE && millis() - lastBatteryReportAt > BATTERY_REPORT_INTERVAL_MS) {
    lastBatteryReportAt = millis();
    Serial.println("BATT," + String(readBatteryVoltage(), 2));
  }

  angle += step_;
  if (angle >= cfg.sweepMax || angle <= cfg.sweepMin) step_ = -step_;
}
