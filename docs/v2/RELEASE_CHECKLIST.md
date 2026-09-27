# Release preparation

For the current GitHub-only release sequence, signing decision, assets and publication gates, use [GITHUB_RELEASE_PLAN.md](GITHUB_RELEASE_PLAN.md). Earlier dated results below are historical; current candidate and user acceptance are in [CURRENT_STATUS.md](CURRENT_STATUS.md).

The permanent-key Android 1.2.1/build 6 APK is distributed in [v1.2.1-rc.1](https://github.com/H4ch1Net/ks-led-controller/releases/tag/v1.2.1-rc.1). All five hosted workflows passed on the merged application code. Release-specific install/update checks passed on an Android 16 emulator. See the current release plan and public build receipt for final evidence; older dated notes below describe earlier candidates. Signed binary reproducibility is not claimed. Google Play/AAB are excluded.

## Android

Use the Flutter revision pinned in `.github/workflows/android.yml`, JDK 21 and the SDK/NDK versions listed there. Run `flutter --no-version-check pub get --enforce-lockfile`, `analyze --no-pub`, `test --no-pub`, the Dart/Python contract smoke, and native Gradle tests before building.

Debug builds use the development key. Release builds require private `apps/android/android/key.properties`; copy `key.properties.example` and fill in your own signing-key details. Passwords and keystores must stay outside exported source packages. Release requests fail clearly if signing is not configured; there is no debug-signing fallback.

After signing is configured, build with `flutter --no-version-check build apk --release --no-pub`. Verify the certificate, version code and package ID before distributing. An APK signed with a different key cannot update the current debug installation; export rooms/scenes first and plan migration before uninstalling. This backup does not include device calibration or credentials.

For future releases, preserve the existing permanent identity and verify signing/install/update behavior. Review `DEFERRED_HARDWARE_CHECKS.md` without treating intentionally deferred optional hardware as a prerelease blocker. The [Android guide](../../apps/android/README.md) records the public build command and private-build migration limits. Google Play is excluded.

## Controllers

Stream Deck: `npm ci`, `npm test`, `npm run build`, `npm run validate`, production simulator smoke, then `npm run pack`. Real device installation and dial behavior still need acceptance.

Python: install `python -m pip install --require-hashes -r requirements.lock` for the hub, or `requirements-controllers.lock` for GPIO/USB setup tools. Both locks include transitive/platform-specific pins and distribution hashes. Run the relevant checks and `python -m pip check`; run the full suite for a release candidate. Windows/Linux CI now consumes these locks. WSL Linux installed the controller lock and passed dependency checks, all 171 Python tests and the simulator; hosted execution remains pending. Platform resolution does not establish hardware compatibility.

ESP32: compile all three PlatformIO environments and the native protocol/rotary checks. Firmware with real Wi-Fi credentials must never enter public bundles. A build is not evidence that board wiring or lamp delivery works.

## Evidence and distribution gate

- Keep test logs, artifact hashes and a manifest for each candidate.
- Run the remote CI workflows after an authorized push; local success does not establish remote success.
- Complete physical acceptance separately from simulator results.
- Publishing, release-key creation/ownership, and permanent key ownership remain explicit release decisions.

## Updating dependency locks

Direct dependencies remain in `requirements.txt`, `requirements-gpio.txt` and `requirements-controllers.txt`. The locks were generated with uv 0.11.28 for Python 3.10+:

```sh
uv pip compile requirements.txt --universal --python-version 3.10 --generate-hashes --output-file requirements.lock
uv pip compile requirements-controllers.txt --universal --python-version 3.10 --generate-hashes --output-file requirements-controllers.lock
```

Review changes before installing. The core lock's Windows dry-run matched the current environment without changes; the controller lock additionally resolves pyserial and a newer setuptools. No development environment was changed by this check. Linux execution has since passed in WSL; macOS markers are resolved but not locally executed. Flutter pub and npm lockfiles and toolchain pins already exist. Gradle/plugin checksum verification is enabled and passed Windows debug and optimized release APK assembly. Release artifacts and remote CI still need validation; dependency pins do not prove signed APK reproducibility.

## Android bootstrap and dependency verification (2026-09-27)

The Gradle launchers and wrapper JAR are included in source. Gradle 9.3.1's distribution checksum is pinned in `gradle-wrapper.properties`; the JAR was checked against the official Gradle checksum. `release/android-toolchain.json` records those pins and the official URLs/hashes of Windows/Linux Android resource compilers and the Linux protobuf compiler. Run `python -m ks_light.build_toolchain` before Gradle; Android CI does this automatically.

`apps/android/android/gradle/verification-metadata.xml` enables strict checksum verification of artifacts and dependency metadata, including the Flutter included build. The baseline records 845 components. Windows debug APK assembly and earlier debug/unit-test Kotlin compilation passed with verification enabled. APK assembly added 18 lint/annotation artifacts whose local bytes matched fresh downloads from the official Google/Maven repositories; their source URLs are recorded with their checksums. Linux-specific executables are recorded, but Linux CI execution remains pending. Signing and release-only execution paths may reveal additional artifacts that need explicit review.

To update intentionally after changing dependencies, use `bash gradlew help --write-verification-metadata sha256` from the Android directory, then exercise the affected build tasks. Inspect missing task-time/platform artifacts and their official repository hashes before adding them. Preserve the reviewed Linux entries and run the bootstrap checker. Do not disable verification or automatically accept new hashes in CI. This baseline detects changes to the recorded artifacts; generating it is not an independent audit of every upstream library.

Reference: [Gradle dependency verification](https://docs.gradle.org/current/userguide/dependency_verification.html).

## Repeatable source packages

See `release/README.md`. The standard-library packager uses an explicit reviewed file inventory, rejects private/generated paths and symlinks, normalizes source line endings and ZIP metadata, and includes per-file hashes plus a source-content identity. It never bundles an APK or Stream Deck installer as if they were built from the current source. Existing artifacts are never overwritten.

The source-package workflow builds on Windows and Linux and compares the resulting ZIP bytes. That remote comparison has not run yet; the same archive bytes were compared successfully between Windows and WSL Ubuntu. The new source candidate is separate from older APK/plugin exports; their existing manifests and hashes retain their original meaning.

## Development candidate, 2026-09-27

The external `outputs/ks-light-dev-2026-09-27/` folder contains Android 1.1.0 (build 2), Stream Deck 0.5.0, matching source, checksums and `build-receipt.json`. APK signature verification and package metadata inspection passed; the development certificate matches the earlier export. Stream Deck validation and the production SDK/controller/simulated-hub smoke passed. This refresh used focused packaging checks, not a new full-suite baseline. Clean install, upgrade/data retention, physical controls, Linux CI and signed release builds remain open. The existing Flutter BLE plugin emits a future Kotlin-plugin compatibility warning, so retain the pinned toolchain until that migration is verified.

## Private sideload candidate, 2026-09-27

`outputs/ks-light-private-2026-09-27/` contains the optimized 1.1.0/build 3 APK, matching source, checksums, build receipt and install notes. Signing is explicitly configured in an isolated build checkout to use the existing development key; there is still no release-to-debug signing fallback in project code. The package is not debuggable, its signature verifies, and its certificate matches the earlier APK. The signing key stays local and is never exported. This preserves upgrade eligibility; phone update/data retention is not yet observed.

An initial isolated release build also passed with a disposable validation key. Android CI now generates its own short-lived validation key, assembles/verifies a release APK and removes the signing configuration on exit. No validation-key APK is published. The workflow shell passed syntax validation; actual hosted execution remains open.

Local Linux checks and source comparison passed. All three ESP32 variants have compiled across the latest two batches. Do not rerun passed broad suites after documentation/version-only changes; run checks for changed behavior, and keep physical acceptance separate. APK byte reproducibility and permanent public signing are future public-release work, not claims made for this private build.
