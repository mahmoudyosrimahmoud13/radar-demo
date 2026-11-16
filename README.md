# Radar Demo

A DIY Arduino "radar" project: a servo-swept HC-SR04 ultrasonic sensor with a buzzer/relay alarm, streamed live over Bluetooth (HC-05) and WiFi (ESP-01), plus a Flutter companion app for Android.

- [`arduino_radar/`](arduino_radar) — Arduino Uno + ESP-01 firmware
- [`radar_app/`](radar_app) — Flutter Android app (see its own [README](radar_app/README.md) for setup, OTA flashing, and build details)

The Android APK is built automatically by GitHub Actions on every push to `main`/`master`. Push a `v*.*.*` tag, or run the workflow manually with "create_release" checked, to publish it as a GitHub Release.
