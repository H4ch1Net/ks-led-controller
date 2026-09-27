# KS Light for Android

Public prerelease APK: **1.2.1 / build 6**, Android 7.0+. Download `KS-Light-1.2.1.apk` from [v1.2.1-rc.1](https://github.com/H4ch1Net/ks-led-controller/releases/tag/v1.2.1-rc.1). Distribution is GitHub-only APK sideloading; there is no Google Play/AAB work.

Build 6 adds the KS Light bulb launcher icon, adaptive masks and Android themed-icon support. App behavior matches the user-accepted build 5.

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

Tests reference shared repository fixtures; keep the checkout layout intact. Release APKs require explicit private signing configuration; there is no debug-key fallback. Never commit keys, passwords, signing symbols or `android/key.properties`. The permanent production key is owned and stored privately by the maintainer, outside the repository. A fresh checkout deliberately has no signing credentials.

Documentation screenshots can be recreated using `tool/capture_screenshots.dart`; see [capture instructions](../../docs/images/README.md).

## Public signing and release builds

Package ID: `dev.kslight.ks_light`. Permanent signing certificate SHA-256:

```text
37:E0:15:4E:39:EB:91:9D:6A:66:C6:E1:57:CF:C1:91:F4:D3:37:AD:53:41:78:06:29:23:CE:02:F2:F6:52:62
```

Use the existing permanent identity for all public updates. Keep at least two protected offline key backups and preserve its password separately, preferably in a password manager. The machine-bound encrypted password alone is not a portable recovery backup. The private key is never uploaded to GitHub or CI. See [Android signing guidance](https://developer.android.com/studio/publish/app-signing).

In an isolated checkout of the reviewed commit, create ignored `android/key.properties` using `android/key.properties.example`, pointing to the privately stored keystore. Restrict that temporary file to the build user. Use the pinned toolchain and locked dependencies:

```sh
flutter --no-version-check clean
flutter --no-version-check pub get --enforce-lockfile
```

Before compilation, add this entry to the generated `.dart_tool/package_config.json` packages array. It maps Flutter's generated plugin registrant to a logical package URI, preventing a personal machine path from entering the APK. Do not commit this generated file; it changes no dependency or application source.

```json
{"name":"ks_light_build","rootUri":"flutter_build/","packageUri":"","languageVersion":"3.13"}
```

Then build without another pub resolution:

```sh
flutter --no-version-check build apk --release --no-pub --build-number=6 --obfuscate --split-debug-info="$PRIVATE_SYMBOLS_DIR" --extra-gen-snapshot-options=--strip
```

`PRIVATE_SYMBOLS_DIR` must be a private directory outside the checkout. Preserve those matching symbols for crash diagnosis, as described in [Flutter's symbol guidance](https://docs.flutter.dev/deployment/obfuscate). Remove temporary `android/key.properties` after building. Inspect the signed APK for package/version, non-debuggable status, certificate, accidental local paths and credentials; verify downloaded asset hashes. Do not publish disposable CI-signed APKs.

The public APK was built from `aff972cca61bc4190ea8ce1d8c1c942106ee9c60`. Installation/startup and a separate same-key code-6 to code-7 update passed on an Android 16 emulator, retaining the selected appearance theme. Code 7 was used only for this local validation and is not distributed. Existing phone installations were untouched. Existing accepted usability/hardware results remain in the current status; no additional lamp compatibility is claimed.

## Private build migration

Older private builds use a development certificate, so Android cannot install the public APK over them. Migration is optional; keep the old app until ready.

1. Use **Library backup → Export backup file** to save rooms/scenes outside private app storage. This includes only lights referenced by those rooms/scenes and excludes the default-light selection.
2. Separately record light names/default, calibration/color balance, saved colors, effect choices, appearance and widget/shortcut setup. Preserve hub pairing information securely. The export is not a full-app backup and does not preserve credentials or all settings.
3. Only after preserving what you need and explicitly choosing to migrate, uninstall the development-signed app and install the public APK. Uninstalling clears its private data.
4. Rescan lights, restore names/default, match devices and import rooms/scenes, restore the other settings and re-pair the hub as needed. Recreate widgets/shortcuts.

Public-to-public updates use the permanent key and do not require this signing migration.
