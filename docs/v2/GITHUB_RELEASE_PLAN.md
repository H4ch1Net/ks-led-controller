# GitHub release plan

Completed 2026-09-27 for [v1.2.1-rc.1](https://github.com/H4ch1Net/ks-led-controller/releases/tag/v1.2.1-rc.1). Distribution is GitHub Releases only. Google Play, AAB, iOS and Stream Deck Marketplace are excluded.

## Release identity

- Android: 1.2.1/build 6, `KS-Light-1.2.1.apk`, package `dev.kslight.ks_light`.
- Reviewed APK/source archive commit: `aff972cca61bc4190ea8ce1d8c1c942106ee9c60`.
- Stream Deck: existing accepted 0.6.1 installer, unchanged; its own source commit is in the receipts.
- Prerelease status is retained while optional hardware coverage remains deferred.

## Completed gates

- [x] Source merged into main through PR #1; repository history preserved.
- [x] All five hosted workflows passed on merged application revision `693cb6506035f0e7dd74a6b9c5e5f9fd03826ab5`. Later publication changes are documentation only; accepted broad suites were not repeated.
- [x] Android usability and Stream Deck 0.6.1 physical power/color/effect, repeat speed and color compensation accepted.
- [x] Permanent RSA signing identity created and stored privately under the owner's control, outside the repository. Credentials never uploaded to GitHub or CI; temporary build signing configuration removed.
- [x] Public certificate, backup responsibilities and development-build migration documented in the [Android guide](../../apps/android/README.md).
- [x] Public APK assembled from the reviewed main commit with permanent signing. Package, version/code, signature and non-debuggable status verified.
- [x] Android 16 emulator fresh installation/startup and same-key code-6 to local-only code-7 update passed, retaining an appearance preference. Existing phone installations were not changed.
- [x] Compiled Dart local path removed using a logical generated-package URI and private symbols. APK and all release asset archives scanned for credentials, signing files and personal machine paths.
- [x] Existing source and Stream Deck bytes and original handoff records preserved. Added the public APK, complete checksums and public build receipt; downloaded hashes verified.
- [x] Release notes explain compatibility, migration limits, historical receipt status and optional hardware coverage. Public prerelease published using the exact reviewed source tag.

## Signing ownership and recovery

The permanent certificate SHA-256 is `37:E0:15:4E:39:EB:91:9D:6A:66:C6:E1:57:CF:C1:91:F4:D3:37:AD:53:41:78:06:29:23:CE:02:F2:F6:52:62`. Future public updates must use this key. The owner must retain two protected offline copies of the keystore and save the password separately. Machine-bound password protection is not a portable recovery backup. No online key escrow or disposable CI signing is used for public assets.

Existing development-signed installs cannot update directly to this identity. The rooms/scenes export is only a partial backup; device calibration, saved colors, credentials and other preferences require separate preservation. Migration is an optional manual phone action after preserving configuration. Never uninstall or clear an existing phone app silently.

## Evidence and remaining scope

`public-build-receipt.json` and `SHA256SUMS-public.txt` are the completed public release records. The original `release-receipt.json` and `SHA256SUMS.txt` are preserved historical source/Stream Deck records. The unchanged source ZIP contains its original pre-publication documentation; current main and the public receipt supersede those notices.

Emulator checks establish software installation/update behavior, not physical BLE acceptance. Multi-light synchronization, keyboard/dials, Pi/ESP32 boards and persistent service deployments remain optional deferred hardware coverage. Signed APK byte reproducibility is not claimed. The user must make protected offline signing backups and decide when to migrate their private phone install.
