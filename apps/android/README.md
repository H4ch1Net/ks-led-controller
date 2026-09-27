# KS Light for Android

Current private APK: **1.2.1 / build 5**, Android 7.0+. Distribution is GitHub-only APK sideloading; there is no Google Play/AAB work.

The app starts with the real light catalog. Demo mode is available in Settings. Direct Bluetooth does not require a hub. Saved colors, animation-first effects, rooms/scenes, calibration, widgets, Quick Settings, Device Controls and five appearance themes are implemented.

- [Main guide and screenshots](../../README.md)
- [Current acceptance status](../../docs/v2/CURRENT_STATUS.md)
- [Visual design and preset behavior](../../docs/v2/ANDROID_DESIGN.md)
- [Pinned toolchain](../../docs/v2/ANDROID.md)
- [Release/signing plan](../../docs/v2/GITHUB_RELEASE_PLAN.md)

From this directory, with the pinned Flutter SDK and Android toolchain configured:

```sh
flutter --no-version-check pub get --enforce-lockfile
flutter --no-version-check analyze --no-pub
flutter --no-version-check test --no-pub
flutter --no-version-check build apk --debug --no-pub
```

Tests reference shared repository fixtures; keep the checkout layout intact. Release APKs require explicit local signing configuration as described in the release checklist. Never commit keys, passwords or `android/key.properties`. The current private APK uses the existing development certificate to preserve upgrade compatibility; production signing is not configured by default.

Documentation screenshots can be recreated using `tool/capture_screenshots.dart`; see [capture instructions](../../docs/images/README.md).
