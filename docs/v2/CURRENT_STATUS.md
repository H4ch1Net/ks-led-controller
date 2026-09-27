# KS Light current status
Updated 2026-09-27. This is the resume point; ROADMAP.md and earlier test notes are historical.

## Delivery
The [first public prerelease `v1.2.1-rc.1`](https://github.com/H4ch1Net/ks-led-controller/releases/tag/v1.2.1-rc.1) distributes `KS-Light-1.2.1.apk`, Android 1.2.1/build 6, through GitHub Releases only. Google Play/AAB are excluded. The APK uses the maintainer-owned permanent signing identity; the key, password and symbols remain private outside the repository. See the [Android guide](../../apps/android/README.md) for the certificate and migration instructions.

APK and preserved source archive commit: `aff972cca61bc4190ea8ce1d8c1c942106ee9c60`. All five hosted workflows passed on merged application commit `693cb6506035f0e7dd74a6b9c5e5f9fd03826ab5`; later changes only update documentation. The release preserves the existing source/Stream Deck assets and handoff records, and adds the signed APK, `public-build-receipt.json` and `SHA256SUMS-public.txt`. The original receipt's pre-signing Android status is historical.

Release-specific checks: APK signature and package metadata verified; version 1.2.1/code 6; not debuggable. Android 16 emulator fresh install/startup and a separate same-key code-7 update passed with appearance preference retention. Code 7 is local validation only. Asset privacy scans and downloaded SHA-256 verification passed. No physical phone install was changed and no broad accepted usability/lamp tests were repeated.

## Implemented
- Build 6 replaces the Flutter template launcher with the KS Light bulb: five legacy densities, adaptive layers and Android themed-icon support. App behavior is unchanged from user-accepted build 5.
- Android 1.2.1 adds named color/brightness presets with visible save/recall, animation-first native effects, arbitrary-color phone breathing and five persistent appearance themes. Preview/preset/theme changes do not transmit lamp commands.
- Android 1.2.0 visual redesign: charcoal/lime theme, Lights/Scenes/Hub navigation, compact device and scene cards, clear power state, brightness above the color pad, persistent Apply action and visual effect tiles. Advanced fields and settings live in menus or expandable sections. Fresh installs open the real catalog; Demo is opt-in. See ANDROID_DESIGN.md.
- Android direct BLE discovery, persistent multi-device catalog/default/names/removal, visual color selection, calibration/presets and native effects.
- Android groups/rooms/scenes with per-light color/brightness editing, explicit save/cancel, backup/import and replacement-device matching.
- Compact independent power/favorite/scene widgets, highlighted Quick Settings tile, Device Controls and connection diagnostics. Widget scenes support 1..8 KS03 lights.
- Optional Android hub pairing in Keystore, individual/group/scene control, per-member results, calibration/preset editing and hub library management.
- Authenticated hub API, scoped controller credentials, bounded queues, calibration, durable last-sent snapshots, event polling, simulator, MQTT/Home Assistant and Windows/systemd service packaging.
- Stream Deck 0.6.1 separate Power/Set Color/Effect/Brightness/Scene actions with automatic shared-connection reuse, color picker and saved controls; legacy named keys/dials and Windows keyboard launchers remain supported.
- **Experimental:** Raspberry Pi GPIO/rotary/dimming/status LEDs; ESP32 buttons/rotary/dimming/status LEDs and bounded USB setup with NVS persistence.
- Pinned dependencies/toolchain, strict Gradle verification, deterministic source packaging and CI definitions including disposable-key release assembly.

## Latest evidence
- Earlier private build 6: release assembly and APK signature verification passed. Version 1.2.1/code 6 is non-debuggable; its certificate matches build 5. Compiled resources include all five PNG densities, adaptive v26 and monochrome v33 variants. README icon and all six screenshots were visually reviewed; README has no em dashes or decorative emoji.
- Hosted Linux Android analysis, Flutter tests, hub contract, debug assembly, native shortcut tests and disposable-key release assembly passed. Hosted Stream Deck, ESP32, source-package comparison and Python Windows/Linux jobs have passed. Initial clean-run issues were corrected: canonical Windows TEMP paths, transient Kotlin inventory files and four missing metadata checksum entries verified from Maven Central. A timing-sensitive controller test now initializes TLS outside its deadline. See the PR checks for final commit status.
- User accepted Android 1.2.1 usability, including the latest presets/effect/theme changes. This is not blanket hardware acceptance.
- DIY sanity check: 24 focused GPIO and ESP32 contract/setup checks passed. No Pi/ESP32 hardware was connected or flashed; both adapters are explicitly experimental.
- Stream Deck 0.6.1 installed with a dedicated profile and persisted shared setup. Color controls, no-send-on-edit, status labels and power highlighting inspected. User accepted the preceding real Reading/Off/Purple delivery, but Reading still looked white. User confirmed new Power/Color/Effect controls work but reported delay, occasional failures and washed colors. Hub now reuses up to two BLE sessions for 30 idle seconds with Android-equivalent packet pacing; user confirmed speed is great. First operation measured 1.879 s, next ten 0.113–0.232 s, all successful at the hub. Selectable Balanced/Stronger saturation/Raw RGB response curves now address washed intermediate shades; the user confirmed the compensated color works great and accepted the completed Stream Deck setup. 15 Node + 5 Python focused checks and SDK simulator smoke passed; build and manifest validation passed.
- 1.2.1/build 5 installed over the existing phone app. Saved-colors entry and naming dialog, appearance selection/restart persistence and grouped effects inspected without lamp commands. Original Lime theme restored after the check.
- 1.2.1: focused preferences, native effects, main-screen and phone-effect tests pass; analyzer is clean. Persistence, failed saves, corrupt-data protection, animation/color packet mapping and compact large-text layout are covered.
- Redesign: 42 focused UI tests passed across targeted runs, including large-text layout, fresh startup, preview/cancel, calibrated commands, device/default persistence, library editing and effect controls. Flutter analysis is clean. Optimized APK assembly passed strict dependency verification.
- The 1.2.0/build 4 optimized APK was installed over the existing app. Saved light/default and effect choices survived. Lights, light controls, Scenes, Hub and Effects were visually inspected on the phone. No physical lamp commands were sent during this review; complete calibration/library/pairing retention and shortcut behavior remain acceptance work.
- WSL Ubuntu/Python 3.12: hashed controller dependencies installed, dependency check passed, 171 Python tests passed, simulator passed. Linux source ZIP exactly matched the Windows ZIP. This is local Linux evidence, not hosted CI.
- Stream Deck 0.5.0 official validation, bundle, simulator smoke and installer packaging passed; installer bundle bytes matched the smoked bundle.
- All three ESP32 environments have compiled: dry-run and network-selector checked this batch; network-dimmer checked in the preceding implementation batch. No board flash.
- Prior focused Android/native/Node feature checks remain recorded in the development candidate/source history. Do not imply a new broad Android or Windows regression run.

## Remaining checklist
- [x] User usability acceptance for Android 1.2.1.
- [x] Raspberry Pi/ESP32 host sanity review and experimental labeling; physical acceptance intentionally deferred.
- [x] Phone: optimized APK upgrade/startup, saved light/default retention and redesigned screen inspection.
- [x] User confirmed app testing is all good and authorized GitHub delivery. Detailed optional coverage is not a request to repeat accepted tests.
- [x] Standard Stream Deck power/color/effect, repeat delivery speed and compensated color accepted by the user.
- [ ] Optional hardware: multiple lights/partial failures, keyboard/dials, Pi/ESP32 wiring and USB configuration. See DEFERRED_HARDWARE_CHECKS.md.
- [x] GitHub: merged PR #1 after all five hosted workflows passed.
- Hosted CI: [PR #1 checks](https://github.com/H4ch1Net/ks-led-controller/pull/1/checks) are the authoritative final-commit results. App tests are not a request for another manual phone pass.
- [ ] Real deployment: persistent Windows/Linux/Pi service and trusted wireless hub acceptance when that hardware/setup is available.

The public prerelease includes the permanent-key APK. Existing development-signed phone installs remain untouched and require the documented manual migration if the user chooses to switch. Offline signing-key/password backups remain the owner's responsibility. Signed binary reproducibility is not claimed. Google Play/AAB are excluded; iOS and optional hardware coverage remain deferred.

## Constraints and known limitations
No desktop UI while the PC is in use; the phone was available for the redesign review. One BLE owner per lamp. No command replay after uncertain delivery. Power/color/live status describe requested or last successful commands, not reliable physical readback. Native breathing was physically accepted as smoother; selected hub/MQTT/Android paths and catalog/widget flows were accepted previously, not every new feature.

The pinned Flutter build succeeds but warns that reactive_ble_mobile still uses the Kotlin Gradle plugin. Revisit migration before upgrading Flutter. Verification hashes detect changed dependencies; they are not an independent upstream audit. This delivery batch did not change the running hub or send physical lamp commands.

Repository preparation: documentation uses generic host/device identifiers. CI runs on pull requests and main pushes, avoiding duplicate branch-push/PR work. The source PR is merged and the permanent-key APK is delivered through the public prerelease. Build 4 is the redesign checkpoint; build 5 adds saved colors, grouped effects and appearance choices.
