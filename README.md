# EchoSweep

<img src="radar_app/branding/logo.png" width="120" alt="EchoSweep logo">

**Your room, on radar.** A DIY Arduino radar: a servo-swept HC-SR04 ultrasonic sensor with a relay (and optional buzzer) alarm, streamed live over Bluetooth (HC-05) to the EchoSweep Android app: live radar scope, room maps, presence events, analytics, settings, wireless firmware updates, demo mode and a step-by-step assembly guide. The app can also share the live radar page with any browser on your WiFi.

- [`arduino_radar/`](arduino_radar): Arduino Uno firmware (`uno_radar`). The `esp01_radar_server` sketch is for a future WiFi add-on and isn't needed.
- [`radar_app/`](radar_app): EchoSweep Flutter Android app (see its [README](radar_app/README.md))

The APK is built by GitHub Actions on every push to `master`. Push a `v*.*.*` tag to publish it as a GitHub Release.

## Linux desktop version (USB, no Bluetooth)

Every release also has `echosweep_<version>_amd64.deb`. It is the same app and UI, but it talks to the Uno over its USB cable instead of the HC-05.

1. Install: `sudo apt install ./echosweep_<version>_amd64.deb`
2. One time only, allow your user to open USB serial ports: `sudo usermod -aG dialout $USER`, then log out and back in.
3. Unplug the HC-05 TX/RX wires from pins 0 and 1 (they share the line with USB).
4. Plug in the Uno, open EchoSweep from the app menu, and tap `/dev/ttyACM0`.

Firmware updates also work over the cable on this version.
