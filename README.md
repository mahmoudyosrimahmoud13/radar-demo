# EchoSweep

<img src="radar_app/branding/logo.png" width="120" alt="EchoSweep logo">

**Your room, on radar.** A DIY Arduino radar: a servo-swept HC-SR04 ultrasonic sensor with buzzer/relay alarm, streamed live over Bluetooth (HC-05) and WiFi (ESP-01), plus the EchoSweep Android app with a live radar scope, step-by-step assembly guide, presence events, analytics and wireless firmware updates.

- [`arduino_radar/`](arduino_radar): Arduino Uno + ESP-01 firmware
- [`radar_app/`](radar_app): EchoSweep Flutter Android app (see its [README](radar_app/README.md))

The APK is built by GitHub Actions on every push to `master`. Push a `v*.*.*` tag to publish it as a GitHub Release.
