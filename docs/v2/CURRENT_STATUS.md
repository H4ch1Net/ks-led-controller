# KS Light current status
Updated 2026-09-27. This is the resume point; ROADMAP.md and earlier test notes are historical.

## Delivery
The user selected private Android APK sideloading first. The latest external output is `outputs/ks-light-private-2026-09-27/ks-light-1.1.0-build3-private.apk`: optimized release-mode APK, version 1.1.0/build 3, signed explicitly with the existing development certificate for upgrade compatibility. This is a private development distribution, not a public/store release. Do not uninstall the existing app to update. An actual upgrade/data-retention check remains pending. Earlier debug and Stream Deck outputs remain unchanged.

## Implemented
- Android direct BLE discovery, persistent multi-device catalog/default/names/removal, visual color selection, calibration/presets and native effects.
- Android groups/rooms/scenes with per-light color/brightness editing, explicit save/cancel, backup/import and replacement-device matching.
- Compact independent power/favorite/scene widgets, highlighted Quick Settings tile, Device Controls and connection diagnostics. Widget scenes support 1..8 KS03 lights.
- Optional Android hub pairing in Keystore, individual/group/scene control, per-member results, calibration/preset editing and hub library management.
- Authenticated hub API, scoped controller credentials, bounded queues, calibration, durable last-sent snapshots, event polling, simulator, MQTT/Home Assistant and Windows/systemd service packaging.
- Stream Deck 0.5.0 keys, shared setup, action/brightness dials, continuous dimming and optional shared live last-sent status; Windows keyboard launchers.
- Raspberry Pi GPIO/rotary/dimming/status LEDs; ESP32 buttons/rotary/dimming/status LEDs and bounded USB setup with NVS persistence.
- Pinned dependencies/toolchain, strict Gradle verification, deterministic source packaging and CI definitions including disposable-key release assembly.

## Latest evidence
- Android debug APK and isolated release APK assembly passed strict verification of 845 dependency components. Private APK package ID/version and signature verified; certificate matches the prior export and debuggable is absent. No phone install this batch.
- WSL Ubuntu/Python 3.12: hashed controller dependencies installed, dependency check passed, 171 Python tests passed, simulator passed. Linux source ZIP exactly matched the Windows ZIP. This is local Linux evidence, not hosted CI.
- Stream Deck 0.5.0 official validation, bundle, simulator smoke and installer packaging passed; installer bundle bytes matched the smoked bundle.
- All three ESP32 environments have compiled: dry-run and network-selector checked this batch; network-dimmer checked in the preceding implementation batch. No board flash.
- Prior focused Android/native/Node feature checks remain recorded in the development candidate/source history. Do not imply a new broad Android or Windows regression run.

## Remaining checklist
- [ ] Phone: update without uninstalling; verify saved devices/default/calibration/scenes/pairing, new widgets, Quick Settings and Device Controls, lifecycle/offline behavior and optimized-build startup.
- [ ] Hardware: multiple lights/partial failures, Stream Deck/keyboard, Pi/ESP32 wiring and USB configuration. See DEFERRED_HARDWARE_CHECKS.md.
- [ ] Hosted CI: push the prepared `ks-light-v2-foundation` branch and open a draft PR against `main`, then follow failed jobs only. GitHub connector writes currently return HTTP 403 (Resource not accessible by integration); local Git has no authenticated login. Restore one authorized write path before retrying. Local WSL Python/source results do not cover hosted Linux Android/release assembly.
- [ ] Real deployment: persistent Windows/Linux/Pi service and trusted wireless hub acceptance when that hardware/setup is available.

Public distribution, permanent release-key ownership, Play enrollment/AAB and signed binary reproducibility are deferred beyond private sideloading. iOS remains deferred. No planned feature implementation remains open; acceptance is not complete.

## Constraints and known limitations
No desktop UI while the PC is in use; phone testing remains deferred until reconnection. One BLE owner per lamp. No command replay after uncertain delivery. Power/color/live status describe requested or last successful commands, not reliable physical readback. Native breathing was physically accepted as smoother; selected hub/MQTT/Android paths and catalog/widget flows were accepted previously, not every new feature.

The pinned Flutter build succeeds but warns that reactive_ble_mobile still uses the Kotlin Gradle plugin. Revisit migration before upgrading Flutter. Verification hashes detect changed dependencies; they are not an independent upstream audit. No production hub/settings changed, public publication or physical lamp commands occurred in this release-preparation batch.

Repository preparation: documentation uses generic host/device identifiers. CI runs on pull requests and main pushes, avoiding duplicate branch-push/PR work. Public APK/store publication is not part of the draft source review. The private build 3 APK remains valid; subsequent changes are documentation and workflow configuration only.
