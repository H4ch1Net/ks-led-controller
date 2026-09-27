# Android prototype

Historical implementation notes. For current public signing, version, installation and migration instructions, use [the Android guide](../../apps/android/README.md) and [current status](CURRENT_STATUS.md). Statements below about pending features/signing refer to earlier development checkpoints.

## Implemented
Flutter app at apps/android. Starts in clearly labelled demo mode, with no real
Bluetooth operations until demo mode is disabled and a scan is requested.
Real mode requests runtime Nearby Devices permissions on Android 12+ and location
permission on older Android versions. Scans last eight seconds and filter the
inherited profile prefixes.

Select a light, send On/Off, or adjust RGB and use Apply color & turn on.
The floor profile exposes brightness; standard RGB profiles do not expose an
unsupported independent brightness control. Sliders edit local settings and do
not write until Apply is pressed. One operation runs at a time.

Every real command connects, discovers the configured service/characteristic,
uses an advertised write mode and disconnects in a finally block.
Connection, discovery and write waits are time-limited. This prototype does not
implement the Python transport's write-mode retry policy.
The screen reports sent state as unconfirmed. Last RGB/brightness is remembered
per device only during this app session, and only after a successful send.

## Dependencies and build environment
- Flutter 3.47.5 / Dart 3.13.4, downloaded from the official stable branch.
- Java 21 already installed on host.
- Compile SDK 36; NDK 28.2.13676358; SDK platform 35 needed by permission plugin.
- flutter_reactive_ble 5.5.0 (BSD-3-Clause).
- permission_handler 12.0.1, chosen because version 13.0.2 requires a newer SDK.
- device_info_plus 13.2.0.
- pubspec.lock is included; local SDK paths are not.

The project root Gradle script overrides the pinned BLE plugin compile SDK from 33 to 36 to match current AndroidX dependencies; no package cache edits are needed.
The BLE dependency reports a future Flutter Kotlin migration warning. Keep this
toolchain baseline until a compatible plugin migration is tested.
The provisional package ID is dev.kslight.ks_light. Release signing, branding
and store distribution are not configured.

## Validation
Run from apps/android:

```text
flutter analyze
flutter test
flutter build apk --debug
```

Tests use the repository's shared 11 golden packet cases, validate invalid inputs,
check that mobile profiles match Python, and exercise demo selection/power/error
recovery. Widget tests do not validate Android permissions or real Bluetooth.
A Samsung SM-S938U1 running Android 16 has now been tested; see PHONE_TEST.md.
Debug APK build succeeded. APK signature verification passed. Output: ks-light-android-debug.apk.

## Phone acceptance
Enable Android Developer options and USB debugging, connect USB and approve the
computer's debugging prompt. Check adb devices before selecting the target.
Install the debug build on that explicitly selected device.
First run demo mode. Then test real mode with one known light: permissions,
discovery, power, primary colors, brightness, disconnect/reconnect and a light
power cycle. Record phone model, Android version, light prefix and outcomes.
Do not declare a profile supported until this passes on recorded hardware.

## Still pending
Hardware testing, runtime diagnostics, persistent mobile settings, foreground/
background lifecycle testing, rooms/groups, scenes/effects, and hub API mode.
18 Android tests now pass after physical-device fixes. No emulator session has been run. The prototype is not a finished mobile release.

## Sources checked
https://pub.dev/packages/flutter_reactive_ble/versions
https://pub.dev/documentation/flutter_reactive_ble/latest/
https://docs.flutter.dev/platform-integration/android/setup

## Names, power indication and shade adjustment
Select a light and choose Rename to save a phone-local label. Clear the field to restore the advertised name.
On/Off highlights the last successfully sent command in this app session. Unknown means no successful command has been observed in this session or the last transaction failed. It cannot track changes made using another controller.
If shades look wrong, open Color balance. Start with White and reduce the channel that looks too strong, save, then Apply color. Compare another mixed color and adjust as needed. Reset balance restores neutral multipliers. Names and balance survive restarts; no automatic tuning or exact screen-to-light match is claimed.

Calibration profiles: added per-light named presets (up to 20), preset selection/removal, and five editable starting points: Neutral, Less blue, Less red, Less green, Purple trial (100/30/75). Existing non-neutral settings migrate to Previous balance without changing active gains. Color balance > name > Add preset > Save persists the collection; Cancel discards edits. Selecting a preset does not send a command; use Apply color after Save. 26 tests pass, analysis clean, debug APK built and installed.

Color selection UX update: replaced default RGB sliders with a saturation/value square, rainbow hue slider, validated hex entry and named color chips (including Pink=#EF42FF). RGB sliders remain under Fine adjustments. After selection, discovery controls collapse behind Change light. A persistent bottom preview/Apply bar distinguishes pending selection from successful delivery. Active RGB balance is visible. Last successfully sent target RGB/brightness now persist per device; failed sends do not overwrite them, and local-save failure after successful delivery is reported separately. Restoring a color never auto-sends it. 31 Android tests pass; analysis clean.

## Rooms and scenes
Use the top-right Rooms & scenes icon. Scan to populate the persistent light catalog; create rooms/groups and recall per-light scenes. See ROOMS_AND_SCENES.md for snapshot, partial-failure and cancellation semantics.

## Effects preview
Use Effects on the light screen or a room/group card. Six effects with speed/intensity and supported palettes are implemented. Keep the screen open; backgrounding stops new updates. Read EFFECTS.md for stop/restore behavior and physical validation limits.
