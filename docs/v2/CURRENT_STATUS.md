# KS Light current status
Updated 2026-09-27. This is the resume point; ROADMAP.md and earlier test notes are historical.

## Delivery
Distribution is GitHub-only APK sideloading; Google Play and AAB work are excluded. The current candidate is `outputs/ks-light-presets-2026-09-27/ks-light-1.2.1-build5.apk`: optimized release-mode APK signed explicitly with the existing development certificate for upgrade compatibility. It is a private candidate, not a published GitHub release. Install over the existing app; do not uninstall. Earlier outputs and Stream Deck packages remain unchanged.

## Implemented
- Android 1.2.1 adds named color/brightness presets with visible save/recall, animation-first native effects, arbitrary-color phone breathing and five persistent appearance themes. Preview/preset/theme changes do not transmit lamp commands.
- Android 1.2.0 visual redesign: charcoal/lime theme, Lights/Scenes/Hub navigation, compact device and scene cards, clear power state, brightness above the color pad, persistent Apply action and visual effect tiles. Advanced fields and settings live in menus or expandable sections. Fresh installs open the real catalog; Demo is opt-in. See ANDROID_DESIGN.md.
- Android direct BLE discovery, persistent multi-device catalog/default/names/removal, visual color selection, calibration/presets and native effects.
- Android groups/rooms/scenes with per-light color/brightness editing, explicit save/cancel, backup/import and replacement-device matching.
- Compact independent power/favorite/scene widgets, highlighted Quick Settings tile, Device Controls and connection diagnostics. Widget scenes support 1..8 KS03 lights.
- Optional Android hub pairing in Keystore, individual/group/scene control, per-member results, calibration/preset editing and hub library management.
- Authenticated hub API, scoped controller credentials, bounded queues, calibration, durable last-sent snapshots, event polling, simulator, MQTT/Home Assistant and Windows/systemd service packaging.
- Stream Deck 0.5.0 keys, shared setup, action/brightness dials, continuous dimming and optional shared live last-sent status; Windows keyboard launchers.
- **Experimental:** Raspberry Pi GPIO/rotary/dimming/status LEDs; ESP32 buttons/rotary/dimming/status LEDs and bounded USB setup with NVS persistence.
- Pinned dependencies/toolchain, strict Gradle verification, deterministic source packaging and CI definitions including disposable-key release assembly.

## Latest evidence
- User accepted Android 1.2.1 usability, including the latest presets/effect/theme changes. This is not blanket hardware acceptance.
- DIY sanity check: 24 focused GPIO and ESP32 contract/setup checks passed. No Pi/ESP32 hardware was connected or flashed; both adapters are explicitly experimental.
- Stream Deck is available: user confirmed it is plugged in, the software is running, and Windows sees an Elgato USB device. KS Light is not in the installed plugin directory; physical installation/key acceptance remains pending while desktop use is deferred.
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
- [ ] Phone: complete calibration/scenes/pairing retention, new widgets, Quick Settings and Device Controls, lifecycle/offline behavior.
- [ ] Hardware: multiple lights/partial failures, Stream Deck/keyboard, Pi/ESP32 wiring and USB configuration. See DEFERRED_HARDWARE_CHECKS.md.
- [ ] Hosted CI: push the prepared `ks-light-v2-foundation` branch and open a draft PR against `main`, then follow failed jobs only. GitHub connector writes currently return HTTP 403 (Resource not accessible by integration); local Git has no authenticated login. Restore one authorized write path before retrying. Local WSL Python/source results do not cover hosted Linux Android/release assembly.
- [ ] Real deployment: persistent Windows/Linux/Pi service and trusted wireless hub acceptance when that hardware/setup is available.

Public GitHub release publication, permanent release-key ownership and signed binary reproducibility remain deferred beyond the private candidate. Google Play/AAB are excluded. iOS remains deferred. Feature implementation is complete for this candidate; acceptance is not complete.

## Constraints and known limitations
No desktop UI while the PC is in use; the phone was available for the redesign review. One BLE owner per lamp. No command replay after uncertain delivery. Power/color/live status describe requested or last successful commands, not reliable physical readback. Native breathing was physically accepted as smoother; selected hub/MQTT/Android paths and catalog/widget flows were accepted previously, not every new feature.

The pinned Flutter build succeeds but warns that reactive_ble_mobile still uses the Kotlin Gradle plugin. Revisit migration before upgrading Flutter. Verification hashes detect changed dependencies; they are not an independent upstream audit. No production hub/settings changed, public publication or physical lamp commands occurred in this release-preparation batch.

Repository preparation: documentation uses generic host/device identifiers. CI runs on pull requests and main pushes, avoiding duplicate branch-push/PR work. GitHub publication was not attempted during the redesign. Build 4 is the redesign checkpoint; build 5 adds saved colors, grouped effects and appearance choices.
