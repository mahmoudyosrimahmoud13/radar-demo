# Arduino Radar companion app (Flutter, Android)

Companion app for the Bluetooth/WiFi Arduino radar project: live sweep
view, entry/exit presence log with notifications, analytics, WiFi
provisioning for the ESP-01, and experimental wireless firmware updates.

## One-time project setup

This repo only has the `lib/` source and `pubspec.yaml` -- it's not a full
Flutter project scaffold (no `android/`, `ios/`, etc.), since those are
large generated folders you don't want to sync by hand. Create them with:

```
flutter create --platforms=android --org com.yourname.radar .
flutter pub get
```

That generates the `android/` folder around the existing `lib/` and
`pubspec.yaml` without touching them.

## Required AndroidManifest.xml additions

Open `android/app/src/main/AndroidManifest.xml` and add these inside the
`<manifest>` tag (above `<application>`):

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

(`ACCESS_FINE_LOCATION` is required by Android for classic Bluetooth
device discovery on older OS versions -- the app never actually reads
your GPS location.)

## Running it

1. Pair the HC-05 in Android's Bluetooth settings first (default pairing
   PIN is usually `1234` or `0000`).
2. Run the app (`flutter run`), pick the HC-05 from the list.
3. Use the bottom nav: Radar (live view), Events (entry/exit log),
   Analytics (busiest hours / time occupied), Settings (sweep/alert
   config), WiFi (provision the ESP-01), Firmware (OTA flashing).

## Firmware update (OTA) -- please read

The "Firmware" tab can flash a new `.hex` onto the Uno over the same
Bluetooth link used for everything else. This only works if you've wired
the HC-05 to the hardware serial pins (0/1) and added the auto-reset
capacitor, as described at the top of `uno_radar.ino`. It is more fragile
than a USB upload -- always test new firmware over USB first, and keep a
USB cable within reach when using this screen. A failed update leaves the
board needing a USB reflash, not permanently damaged.

## Building via GitHub Actions

`.github/workflows/build_apk.yml` builds the release APK automatically:

- **Every push/PR to `main`**: builds and attaches the APK as a run
  artifact (Actions tab -> the run -> Artifacts section) -- good for CI
  sanity checks, expires after a while, not a shareable link.
- **Pushing a version tag** (`git tag v1.0.0 && git push origin v1.0.0`):
  also publishes a GitHub Release with the APK attached as a permanent,
  shareable download link.
- **Manual run** (Actions tab -> "Build Android APK" -> "Run workflow"):
  check "Also publish a GitHub Release with this build" to get a Release
  without tagging anything -- it'll be named after the run number instead
  of a version.

No signing key or Play Store account needed -- Android will prompt
whoever installs the APK to allow "install from unknown sources" once,
same as any APK from outside the Play Store.

## Known limitation: presence detection

Entry/exit detection comes from a single rotating ultrasonic sensor
watching the doorway angle range for a sudden close-range echo. It's a
reasonable hobby-project heuristic, not verified multi-person tracking --
two people walking through close together, or someone standing still
right at the edge of the sweep, can confuse it. See the comment at the
top of `lib/services/presence_detector.dart` for the exact logic and the
tunable thresholds.
