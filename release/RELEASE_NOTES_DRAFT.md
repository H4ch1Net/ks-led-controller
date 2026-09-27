# KS Light 1.2.1 release candidate

Draft text for the first GitHub prerelease. Do not publish until the signing, hosted checks and asset verification in `docs/v2/GITHUB_RELEASE_PLAN.md` are complete.

## Android

- Manage multiple lights, names and a default device.
- Save and recall named colors with brightness; calibrate each light separately.
- Choose an effect animation and color separately. Built-in breathing supports the firmware's fixed colors; custom phone breathing supports arbitrary shades.
- Organize rooms/scenes and use widgets, Quick Settings and Device Controls.
- Choose among five appearance themes.
- Recognize the app by its KS Light bulb icon, including adaptive and themed launcher support.

## Integrations

Optional hub/API and Home Assistant MQTT support, plus Stream Deck 0.6.1 keys/dials and keyboard launchers. Raspberry Pi GPIO and classic ESP32 examples are **Experimental**: host-side checks pass, but physical boards/wiring have not been verified.

## Installation and limits

Android 7.0+; compatible BLE light required. Download the APK from this release and follow the README. No Google Play account or cloud lighting account is required.

Before publishing, replace this paragraph with the final public certificate fingerprint and verified upgrade/migration instructions. The private development-signed build is not automatically upgrade-compatible with a new public signing key. Do not advise users to uninstall without preserving their configuration.

KS03~ has physical evidence on one lamp. Other inherited profiles are not a promise of compatibility. Status is generally last-sent state. Custom phone effects need the app in the foreground and may be less smooth than built-in effects. iOS is deferred.

## Assets to attach

Signed APK; Stream Deck 0.6.1 installer; reviewed source ZIP; SHA-256 checksums; build receipt containing exact source commit, versions and signing fingerprint. Do not upload configured ESP32 images, tokens or keys. Fill in actual asset names and checksums after building; do not leave placeholders in a published release.
