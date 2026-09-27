# KS Light 1.2.1 release candidate

First public Android APK, distributed through GitHub Releases. Android 7.0+ and a compatible Bluetooth light are required. No Google Play release or cloud lighting account is required.

Download **KS-Light-1.2.1.apk** (version 1.2.1, build 6). It uses the project's permanent signing identity and is not debuggable.

## Android and integrations

Manage multiple lights, names and a default device; save named colors and brightness; calibrate each light; select animation and color separately; organize rooms/scenes; and use widgets, Quick Settings and Device Controls. Five appearance themes and the KS Light adaptive/themed launcher icon are included.

The optional hub connects Home Assistant and external controllers. Stream Deck 0.6.1 includes Power, Color, Effect, Brightness and Scene actions, shared setup, faster repeat delivery and adjustable color response. Android usability and the physical Stream Deck setup have been accepted.

Raspberry Pi GPIO and ESP32 examples are **experimental**. Host checks and all three ESP32 compile configurations pass; physical boards/wiring remain unverified. KS03~ has physical evidence on one lamp. Other inherited profiles, multi-light synchronization and Stream Deck+ dials are not hardware-certified. Status usually means last-sent state. Phone effects require the app in the foreground. iOS is deferred.

## Signing and updates

Package: `dev.kslight.ks_light`. Public certificate SHA-256:

```text
37:E0:15:4E:39:EB:91:9D:6A:66:C6:E1:57:CF:C1:91:F4:D3:37:AD:53:41:78:06:29:23:CE:02:F2:F6:52:62
```

Future public updates must retain this signing identity. Installation/startup and a separate same-key build-6 to build-7 upgrade were verified on an Android 16 emulator, including appearance preference retention. The test-only build 7 is not distributed. This focused release check does not repeat or expand the accepted physical lamp testing.

**Existing private development-signed installs cannot update directly to this public APK.** Keep the existing install until ready to migrate. Export rooms/scenes using **Library backup → Export backup file** and keep the file outside app storage. That export is not a full backup: separately record device names/default, color balance/calibration, saved colors, effect choices, appearance and widget/shortcut setup; preserve hub pairing information securely. It includes only lights referenced by exported rooms/scenes. Only after preserving the needed configuration and choosing to migrate, uninstall the old private build, install the public APK, rescan/match lights, import rooms/scenes and restore other settings or re-pair the hub. Uninstalling clears private app data. No existing phone install was changed for this release.

## Assets and verification

- `KS-Light-1.2.1.apk`: permanent-key Android release APK.
- `dev.kslight.controller.streamDeckPlugin`: existing Stream Deck 0.6.1 installer, unchanged.
- `ks-light-source-final.zip`: existing reviewed source archive, unchanged.
- `public-build-receipt.json`: completed Android verification, source identities and public asset hashes.
- `SHA256SUMS-public.txt`: complete checksums for the downloadable assets (excluding this checksum file itself).
- `release-receipt.json` and `SHA256SUMS.txt`: preserved original source/Stream Deck handoff records; their pre-signing Android status is historical and superseded by the public receipt.

APK and source archive commit: `aff972cca61bc4190ea8ce1d8c1c942106ee9c60`. Stream Deck's own source commit is recorded in the receipts. All five hosted workflows passed on the merged application revision; subsequent publication documentation changes no application/build code. Dart symbols are retained privately; signed APK byte-for-byte reproducibility is not claimed. The release assets have been downloaded again and their SHA-256 hashes verified.
