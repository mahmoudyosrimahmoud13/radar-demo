# EchoSweep

<img src="radar_app/branding/logo.png" width="120" alt="EchoSweep logo">

**Your room, on radar.** A DIY Arduino radar: a servo-swept HC-SR04 ultrasonic sensor with a relay (and optional buzzer) alarm, streamed live over Bluetooth (HC-05) to the EchoSweep Android app: live radar scope, room maps, presence events, analytics, settings, wireless firmware updates, demo mode and a step-by-step assembly guide. The app can also share the live radar page with any browser on your WiFi.

- [`arduino_radar/`](arduino_radar): Arduino Uno firmware (`uno_radar`). The `esp01_radar_server` sketch is for a future WiFi add-on and isn't needed.
- [`radar_app/`](radar_app): EchoSweep Flutter Android app (see its [README](radar_app/README.md))

The APK is built by GitHub Actions on every push to `master`. Push a `v*.*.*` tag to publish it as a GitHub Release.
