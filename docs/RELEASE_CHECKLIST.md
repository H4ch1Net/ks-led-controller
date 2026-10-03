# Release checklist

Releases are published on GitHub only. A release normally contains the signed Android APK, the Stream Deck installer, a source archive, and a checksum file.

## Before tagging

- [ ] All CI workflows pass on the release commit ([DEVELOPMENT.md](DEVELOPMENT.md#continuous-integration)).
- [ ] Version bumped where it changed: `apps/android/pubspec.yaml` (version and build number), `apps/streamdeck/package.json` and the plugin `manifest.json`.
- [ ] `release/source-files.json` lists every new tracked file (`python -m ks_light.source_package --check-inventory`).
- [ ] Any new hardware claim is backed by an observation recorded in [HARDWARE_TESTING.md](HARDWARE_TESTING.md). Simulator and CI results are not hardware evidence.

## Android APK

Follow [apps/android/README.md](../apps/android/README.md#release-signing): clean checkout, pinned toolchain, `python -m ks_light.build_toolchain`, private `key.properties`, obfuscated release build with private symbols.

- [ ] Signed with the permanent key; certificate SHA-256 matches the published value.
- [ ] Package ID `dev.kslight.ks_light`, expected version code, not debuggable.
- [ ] No local paths, credentials or signing files in the APK.
- [ ] Fresh install and an update over the previous public release both start and keep settings.
- [ ] `android/key.properties` removed after the build; symbols stored privately.

Never publish APKs signed with the CI throwaway key or a debug key.

## Stream Deck plugin

From `apps/streamdeck`: `npm ci`, `npm test`, `npm run build`, `npm run validate`, then `python -m apps.streamdeck.test.smoke` from the repository root, then `npm run pack -- --force`. Attach `dev.kslight.controller.streamDeckPlugin`.

## ESP32

`pio run` in `apps/esp32` and the host tests must pass. Never publish binaries built with real Wi-Fi or hub credentials; users build their own configured firmware.

## Source archive

```sh
python -m ks_light.source_package --output dist/ks-light-source-VERSION.zip
python -m ks_light.source_package --verify dist/ks-light-source-VERSION.zip
```

See [release/README.md](../release/README.md).

## Publish

- [ ] Compute SHA-256 for every asset into a checksum file and attach it.
- [ ] Release notes state supported hardware honestly (see [HARDWARE_TESTING.md](HARDWARE_TESTING.md)), mark Raspberry Pi and ESP32 as experimental, and mention any signing or migration change.
- [ ] Download the published assets and verify their hashes.

## Dependency verification

Android Gradle dependencies are verified against `apps/android/android/gradle/verification-metadata.xml`; the Gradle wrapper and platform tools against `release/android-toolchain.json`. After an intentional dependency change, from `apps/android/android`:

```sh
bash gradlew help --write-verification-metadata sha256
```

Then run the affected build tasks, and check any newly required artifacts against their official repository hashes before committing. Keep the reviewed Linux-specific entries. Never disable verification or accept new hashes automatically in CI. Verification metadata detects changes; it is not an audit of upstream libraries.

Python locks: see [DEVELOPMENT.md](DEVELOPMENT.md#updating-locks). npm and Flutter use their committed lockfiles.
