# Roadmap and working status
Updated: 2026-09-26

## Status vocabulary
Planned: not implemented. Implemented: code exists. Automated verified: tests passed. Hardware verified: observed on recorded physical device. Deferred: out of current release scope.
Do not equate mock test success with hardware verification.

## Milestones
| ID | Deliverable | Dependencies | Exit gate |
| --- | --- | --- | --- |
| M0 | Planning pack and current-state inventory | none | scope, ownership and acceptance criteria documented |
| M1 | Python foundation | M0 | discovery/failure fixes and protocol regression tests pass |
| M2 | Android BLE vertical slice | M1, phone | scan/power/RGB/brightness/reconnect on physical phone/light |
| M3 | Rooms, groups, scenes | M2 | restart persistence and offline group member handled |
| M4 | Effects engine | M1, M3, measured BLE limits | six effects, bounded queue, stop/restore and group tests |
| M5 | Hub API and MQTT/Home Assistant | M1; effect hooks from M4 | authenticated operations, event updates, HA acceptance |
| M6 | Stream Deck, Windows and DIY clients | M5 | shared actions work and statuses propagate |
| M7 | Beta packaging | applicable hardware gates | reproducible installs, diagnostics and release notes |

## Immediate backlog
F01: Remove hardcoded CLI address; scan when omitted.
F02: Refuse ambiguous single-target discovery; require an explicit address.
F03: Return failure exit status for partially failed bulk commands.
F04: Add hardware-free regression tests for F01-F03.
F05: Extract shared profiles and validated command encoders.
F06: Unify transport cleanup/fallback with property-aware characteristic selection.
F07: Fix preset reload/schema handling and preserve color/brightness state.
F08: Add structured scan/list/RGB/brightness CLI commands.
F09: Introduce bounded per-light queues and simulator.
F10: Add CI after local checks and supported Python range are established.

## Inputs needed, without blocking documentation or mock-based work
- Original APK file/path and version, if available.
- Android model/version and light models/count.
- Whether Home Assistant already runs and where.
- Raspberry Pi/ESP32/Stream Deck/keyboard hardware available for acceptance.
- Distribution preference and branding before release packaging.
No assumption is made that any of this hardware besides the user's Android phone is available.

## Current milestone summary
Current consolidated implementation and backlog: see CURRENT_STATUS.md. The entries below record milestone history.

User accepted calibration as good enough on 2026-09-21. Android direct control, visual picker, calibration profiles and local persistence are implemented. M3 and the first M4 Android/native-effect slices are implemented; M5 hub API is the current implementation slice. M2 dedicated dimming/reconnect/background acceptance is not inferred from color acceptance.

## Current work
M0: documented.
M1: F01-F04 implemented and automated verified: 8 unittest tests passed on Windows, Python 3.10.11, Bleak 3.0.2. Added positive finite scan-timeout validation and duplicate-advertisement handling.
Validation command: .venv/Scripts/python.exe -m unittest discover -s tests -v
git diff --check passed. No physical Bluetooth writes were performed.
Hub, API, integrations and effects remain planned. Android prototype progress is recorded below.
F05/F06: implemented and automated verified. Both entry points use one JSON profile registry, validated encoders and a shared sequence transport. Transport selects only the configured service/characteristic and advertised write modes, with operation and cleanup deadlines. Blind alternate-characteristic probing was removed.
Validation: 25 tests pass, including 11 language-neutral golden packet cases, invalid inputs, write-mode fallback, timeout, cancellation, partial connect cleanup and menu integration. No hardware writes performed.
F07/F08 implemented and automated verified: validated presets, atomic JSON writes, custom-preset refresh, remembered per-device RGB/brightness after successful sends, and scan/list/rgb/brightness CLI actions. State is explicitly unconfirmed. Floor-profile dimming preserves remembered RGB; a color must be set first. Unsupported independent ceiling brightness remains rejected.
Validation: 40 tests pass. New cases cover corrupt-file preservation, atomic write failure, restart state, failed-send state preservation, menu reload, discovery JSON and CLI RGB/dimming. No hardware commands were issued.
F09 implemented and automated verified: bounded per-target queues, a global connection cap, pending absolute-value coalescing, generation-based invalidation, cancellation cleanup ordering and a hardware-free simulator. The legacy CLI/menu still use direct sequence writes; queue integration belongs to upcoming hub/effect callers.
Validation: 53 tests pass. Simulator reports 100 superseded settings, two delivered targets and one isolated offline failure. No physical BLE operations.
F10 implemented: Bleak 3.0.2 pinned; Python 3.10+ baseline; CI configured for Windows/Ubuntu with Python 3.10/3.12. Only Windows/Python 3.10.11 was locally tested. Remote CI has not run. Transitive dependency locking and wider compatibility remain unverified.
M2 prototype implemented in apps/android: demo mode, BLE discovery, runtime permissions, single-light power/RGB/brightness controls, configured characteristic selection, per-command disconnect and session-only remembered settings.
Validation: Flutter analysis passes; 15 mobile tests pass, including shared packet fixtures and demo UI/error recovery. Python suite still passes all 53 tests. Debug APK built successfully and signature verified; no connected phone in adb inventory. Physical acceptance remains open, so M2 is not complete.
Next: complete physical response, color and dimming acceptance on the connected Android phone. Persistent mobile settings and connection/lifecycle diagnostics can proceed independently.
Current state-file persistence assumes one writer. Cross-process writes are not coordinated; hub single-writer ownership and transactional persistence are still planned.

Physical Android session: installed and launched on Samsung SM-S938U1 / Android 16. Demo flows pass; real KS03~ discovery and On transaction succeed at transport level. Fixed post-permission status race and bottom navigation overlap; 18 Android tests pass. User confirmation of physical response and real color/dimming remain pending. See PHONE_TEST.md.

User confirms physical On/Off and color changes on the KS03~ light; shade matching remains open. Added saved local names, manual per-device RGB balance, primary-color presets and last-sent power selection. No readback is claimed. 22 Android tests pass; follow-up APK installed. See PHONE_TEST.md.

Calibration profiles: added per-light named presets (up to 20), preset selection/removal, and five editable starting points: Neutral, Less blue, Less red, Less green, Purple trial (100/30/75). Existing non-neutral settings migrate to Previous balance without changing active gains. Color balance > name > Add preset > Save persists the collection; Cancel discards edits. Selecting a preset does not send a command; use Apply color after Save. 26 tests pass, analysis clean, debug APK built and installed.

Color selection UX update: replaced default RGB sliders with a saturation/value square, rainbow hue slider, validated hex entry and named color chips (including Pink=#EF42FF). RGB sliders remain under Fine adjustments. After selection, discovery controls collapse behind Change light. A persistent bottom preview/Apply bar distinguishes pending selection from successful delivery. Active RGB balance is visible. Last successfully sent target RGB/brightness now persist per device; failed sends do not overwrite them, and local-save failure after successful delivery is reported separately. Restoring a color never auto-sends it. 31 Android tests pass; analysis clean.

M3 initial Android rooms/groups/scenes implemented: persistent known-light catalogs, named collections, sequential group power, per-light scene snapshots and activation, per-target failure reporting, and stop-after-current cancellation. 40 Android tests pass, including simulated offline-member and restart cases. One physical light is available; multi-light hardware acceptance remains open. Definition editing, import/export and richer home organization remain future polish. Next milestone is M4 effects after establishing conservative BLE timing and stop/restore behavior. See ROOMS_AND_SCENES.md.

M4 initial Android foreground effects preview implemented: six effects, preset palettes, cycle/intensity controls, individual/group launch, monotonic no-backlog scheduling, per-target failure isolation, stop/optional known-state restore and lifecycle stop. 52 Android tests pass and analysis is clean. Phone demo start/stop/restore and background-return checks pass. Effects now retain connections for 1-4 targets, send power-on once, skip duplicate colors and target 150 ms frames; larger groups retain slower sequential connections. On the real KS03 light, Android logs confirm one discovery/connection across a 27-second effect run and a clean disconnect on Stop. Perceived smoothness and real multi-light timing remain unverified. See EFFECTS.md.

M4 priority revision after hardware feedback: investigate device-native effects, independent brightness and state readback before further streaming-rate tuning. Original installed APK provides command/parser evidence, not hardware validation. See NATIVE_EFFECT_RESEARCH.md.

M4 native-effects follow-up implemented: KS03~ defaults to on-light effects, with speed/brightness and explicit continuing-after-disconnect behavior. Purple breathing physically confirmed smoother by user. Brightness scale corrected and software breathing separates RGB from dimming. Optional state-read probe does not yet produce usable state on tested firmware. 58 Android tests pass across suite and focused reruns; analysis clean. Other native modes and multi-light synchronization remain acceptance-open.

M4 native control usability follow-up: per-light last applied settings and up to 20 named presets, one update on slider release after Apply, pinned Apply/Off controls, and background connection cleanup without stopping native animation. Reopening restores choices without sending commands. Separate native preference storage preserves calibration and rooms/scenes. 63 Android tests pass across the full suite and the corrected focused preset test; analysis clean. Phone persistence and restart checks recorded in PHONE_TEST.md.

M5 first hub API slice implemented: authenticated loopback server, default simulator and explicit BLE adapter, bounded per-light queues, power/RGB/brightness/KS03~ native-effect requests, operation polling, ten-minute idempotency retention and cursor-based polling events. Single operator token only; no scopes, pairing, durable state, WebSockets yet. HA/MQTT was added in the follow-up below. Physical hub BLE acceptance remains open. See HUB_API.md.

M5 validation: 65 Python tests pass; local dependency check passes; separate-process simulator smoke test completed a native-effect HTTP operation. Event snapshots include a process instance ID for reliable restart recovery. Android APK unchanged in this milestone.

M5 MQTT follow-up: optional MQTT 5 bridge, Home Assistant JSON light discovery for KS03~, power/RGB/brightness and Purple breathing, shared hub queues, retained-command rejection, optional request IDs, reconnect/birth discovery refresh, owned stale discovery cleanup, last-sent attributes and offline will/shutdown. 76 Python tests pass. Live Home Assistant host broker test passed simulated native delivery, retained-command rejection, hub validation rejection, state publication and offline shutdown. Temporary test discovery was removed. Home Assistant UI discovery, power, native effect and color preset acceptance passed in simulation; physical hub control remains acceptance-open; Android unchanged. See HOME_ASSISTANT.md.

M5 physical bridge test (2026-09-22): Home Assistant host MQTT -> hub queue -> PC Bluetooth -> KS03 native Purple breathing delivered successfully (speed 35, brightness 50). Original HA integration was paused only for the test, then re-enabled; Android was reopened and temporary hardware discovery removed. Visual acceptance is pending user feedback. Native brightness-only updates now preserve the active effect/speed, with strict zero rejection and retry coverage. 77 Python tests pass. Next: choose persistent BLE ownership and add Android hub mode/service packaging before relying on unattended operation; M6 controller integrations remain planned.

Hardware acceptance follow-up: user reported no visible change during the first MQTT effect test. A controlled direct hub BLE test subsequently produced user-confirmed steady red at 40%, followed by user-confirmed smooth Purple breathing at 50%. Home Assistant host MQTT timed out during the repeat attempt but later recovered; no broker settings changed. Original HA integration and Android restored, temporary discovery removed. Repeat MQTT-to-lamp visual acceptance remains open.

M5 connection diagnostics: authenticated health now distinguishes disabled/connecting/online/retrying/failed MQTT and marks a configured offline bridge degraded. Sanitized errors and retry delays expose outages without disclosing credentials. Short-lived connections preserve exponential backoff. Full suite of 80 tests passed, followed by an additional focused reconnect regression test. A fresh green command through Home Assistant host MQTT completed real BLE delivery; the user confirmed steady green at moderate brightness. End-to-end MQTT physical color acceptance passed. Original HA integration and Android restored afterward.

M5/M7 service packaging (2026-09-22): configured foreground service runner, secret files, read-only preflight, OS-held runtime lock and rotating logs implemented. Windows logon-task installer and systemd template provided but not activated. 87 Python tests pass; separate-process simulator verified startup, authenticated delivery, duplicate rejection, crash/restart recovery and unknown state after restart. Scheduler execution and Linux deployment remain untested. Next: Android hub transport and secure LAN access. See SERVICE_DEPLOYMENT.md.

Android hub first slice (2026-09-22): separate authenticated hub screen, catalog selection, power/RGB/brightness/Purple breathing, operation polling, session-only credentials, HTTPS validation and USB loopback development access. On-phone simulator commands and lost-server feedback verified; physical Android-to-hub control remains open. Calibration/scenes and saved pairing are not integrated. See ANDROID_HUB.md.

Android hub validation: all 67 Android tests pass; analysis clean; final debug APK built and installed on the Samsung phone. USB simulator flow covered On, Blue, Purple breathing and server-loss feedback. Final pinned-status layout inspected on device. Simulator and ADB forwarding stopped after testing; no real light changes.

Android hub physical acceptance (2026-09-22): user confirmed steady Blue at 50% sent from Android Hub control through USB and PC BLE. All temporary access cleaned up and original HA integration restored. Configured hub now supports explicit TLS-only remote listening, with loopback defaults retained. 89 Python tests pass plus real certificate/hostname/authentication handshake smoke checks. Wireless deployment awaits a trusted certificate/name and network setup; no listener/firewall/trust changes applied.

Android direct-control priority (2026-09-22): hub remains optional. Added one-target KS03 power widget and Quick Settings tile, in-app configuration/pinning, short connected-device foreground service, bounded BLE lifecycle and shared ownership lock with Flutter sessions. No hub required. Per-widget targets, scenes and Device Controls remain planned. Build passes, analysis clean, 67 existing Flutter tests pass. Real widget placement and completed Off status verified on Samsung; visual power and tile acceptance pending. See ANDROID_SHORTCUTS.md.

Shortcut phone follow-up: widget exists on Samsung home screen, persisted target and Last sent: Off recorded, and no shortcut service remained after completion. Tile added to Quick Settings and final preview-layout fix installed. Phone locked before tile activation could be validated; user unlock and physical On/Off confirmation pending. No existing HA settings changed during this slice. Final APK exported.

Widget refinement (2026-09-22): compact rounded 2x1 default with clear On/Off controls, shorter labels and accessible full details. Built, installed and visually verified on Samsung; existing 4x2 placement resized to 2x1. No new physical command acceptance claimed.

Quick Settings feedback (2026-09-22): user-requested On highlight and inactive Off implemented using last successful write, with pending/error subtitles. On-phone tile activation now verified for both On and Off with successful BLE writes and matching Android checked state. Physical state confirmation remains separate. Build/install passed.

Android Device Controls first slice (2026-09-22): Android 11+ provider, system add-control request, last-command toggle and live status updates implemented using existing direct BLE service. Address-bound favorites reject changed targets; bounded latest-state publishing releases listeners. Debug APK built/installed, provider discovery verified, analysis clean, 67 Flutter tests passed. Native system favorite-add/toggle and physical response remain acceptance-open because phone locked.

Device Controls setup follow-up (2026-09-22): Samsung displayed the system Add to Device control panel confirmation and accepted KS Light. Enabled the Device control panel entry in Quick Settings (Samsung labels it SmartThings in the add-controls picker). The panel app selector lists KS Light. Final provider toggle/write acceptance remains open; Google Home became foreground during navigation. No lamp commands were sent in this follow-up.

Device Controls on-phone acceptance (2026-09-22): selected KS Light in Samsung Device control panel, tapped its power icon for On and Off, and observed live Last sent: On then Last sent: Off updates after successful BLE writes. ShortcutPowerService was no longer running after completion. Left KS Light selected in the system panel, last command Off. Physical lamp appearance is not inferred from software delivery. Samsung opens app details when tapping the card body; the small power icon controls power. No application code changed in this verification.

M6 controller-action first slice (2026-09-23): named hub action CLI and Windows shortcut generator implemented for power, RGB/brightness and native effects. Bounded completion polling, separate credential files, trusted HTTPS for remote hosts and no uncertain-command retries. 95-test Python suite passed, then focused seven including added real CLI subprocess coverage passed. Four Windows links generated and inspected. Native Stream Deck plugin/live key feedback and physical keyboard/Stream Deck acceptance remain planned. Phone testing deferred at user request. See CONTROLLER_ACTIONS.md.

M6 native Stream Deck first slice (2026-09-23): packaged Windows key-action plugin with per-key settings, shared Python controller execution, pending/success/simulated/failure feedback, duplicate-press suppression and stale completion protection. Eight Node tests, official manifest validation/package and full SDK-to-Python-to-simulator smoke passed. Real Stream Deck/phone tests deferred by user; dials and continuous state display remain planned. See STREAM_DECK.md and DEFERRED_HARDWARE_CHECKS.md.

Android saved devices/default (2026-09-26): persistent catalog now loads in main UI, Add devices merges discoveries without dropping offline saved lights, and stars select/clear a default. Real default opens on startup without sending. Legacy libraries accepted; save failures preserve UI state. Existing 67 tests and three new focused tests passed; debug build succeeded. No desktop/phone interaction; hardware acceptance deferred. See DEVICE_MANAGEMENT.md.

Phone acceptance (2026-09-26): latest APK installed on Samsung via ADB without desktop interaction. Real saved light loaded without scanning, default selection survived force-stop/relaunch into real mode, Add devices rescanned without duplicating/removing the saved light or dropping its default, and clearing default survived restart. Restored the test KS03 lamp as real default and left control screen open. Screenshot checked for layout/labels. No power/color writes sent. Adding a second physical light remains untested; merge behavior across multiple devices has automated coverage.

Safe device removal (2026-09-26): saved-device rows now include Remove with a confirmation describing consequences. Successful persistence removes the light from the catalog, clears its default and membership in collections/scenes, and removes empty collections/scenes. Other members remain intact; calibration/name settings are retained for rediscovery. Native real-library saves clear the shared quick-control target when that saved light is removed; old Device Controls favorites become unavailable. Removal does not turn a lamp off or cancel already-issued commands. Cancellation/save failure preserve visible devices. All 72 Flutter tests pass, analysis clean, debug APK built/installed. Phone confirmation and Cancel checked using demo entry; no real/demo devices deleted and no lamp writes. Native quick-control cleanup after real removal still needs hardware acceptance.

## Independent widget targets completed (2026-09-26)
Implemented separate saved targets, chooser/reconfiguration, upgrade migration, stale-action rejection, removed-light cleanup and deleted-widget cleanup. Flutter analysis clean; 72 Flutter tests and six native routing tests pass. APK built/installed. Samsung phone verified migration, chooser Cancel/save, in-app second-widget pinning, successful Off write, matching status on both widgets, service shutdown and temporary-widget removal/cleared settings. Original widget preserved, last command Off. Desktop untouched. Physical multi-light behavior and launcher-gallery setup remain open; no readback or physical lamp observation claimed.

## Raspberry Pi buttons (2026-09-26)
Implemented configurable BCM pin-to-action mappings, stable-edge debounce, held-startup protection, no-backlog single-operation dispatch, graceful input cleanup, check/dry-run and hardware-free simulation modes. Seven focused tests pass, including a mocked button-to-authenticated-hub operation and CLI subprocesses. No Pi or physical light acceptance claimed. See RASPBERRY_PI_BUTTONS.md. Encoders and ESP32 firmware remain open.

## ESP32/Arduino button controller (2026-09-26)
Implemented classic ESP32 DevKit firmware for four actions through authenticated HTTPS, with bounded response parsing, explicit TLS trust, dry-run, debounce, worker separation, busy/offline discard and no command replay. Portable C++ logic checks and actual-payload simulator contract test pass. Physical board/TLS/wiring acceptance remains open. See ESP32_CONTROLLER.md and apps/esp32/README.md.

## Raspberry Pi status LEDs (2026-09-26)
Optional sending/completed/error GPIO outputs now reflect command lifecycle, not physical lamp state. Includes collision validation, outputs-off startup/shutdown, partial setup cleanup and isolation of indicator faults from delivery. Original button configs remain valid; check/simulate never open GPIO. Twelve focused GPIO tests pass. Physical LED wiring and backend acceptance remain open.

## Stream Deck shared setup (2026-09-26)
Plugin 0.2.0 adds explicit shared-connection opt-in, per-key action selection, retained legacy setup, no fallback on invalid shared settings and stale-result suppression after changes. Fourteen Node tests and bundled SDK/client/hub simulator smoke pass. Real Stream Deck UI/hardware acceptance remains deferred.

## Stream Deck dial controls (2026-09-26)
Plugin 0.3.0 adds named-action browsing and brightness selection with press-to-apply, no writes during rotation, bounded levels and stale-feedback protection. CLI supports explicit brightness overrides of known color/native-effect presets without changing saved config. Twenty-one Node tests, simulator SDK integration and package checks pass; hardware acceptance remains open.

## Pi rotary action selection (2026-09-26)
Implemented up to four encoder selectors with separate push switches, distinct pin validation, GPIO Zero quadrature decoding, no-write previews and discarded busy motion. Sixteen GPIO tests pass including resource cleanup and selected-action dispatch. Physical turn rate, bounce and wiring remain acceptance-open.

## Optional durable hub state (2026-09-26)
Configured service supports persist_state=true with atomic per-device/mode snapshots, restored provenance, pending-state invalidation before transport, storage health and no command replay. Full 127-test suite, including a real subprocess restart test, passes. Default remains memory-only; no live deployment changed. Power-cut and persistent physical-service acceptance remain open.

## ESP32 rotary and status feedback (2026-09-26)
Optional full-cycle mechanical encoder previews four actions and sends only on press. Optional Sending/Completed/Error LEDs report command outcome. Distinct pin validation, startup/hold handling, busy-boundary discard and portable checks are implemented. Both firmware environments compile; wiring and real encoder turn rate remain pending.

## Hub collections across controllers (2026-09-26)
Configured groups/scenes now share authenticated API admission, per-light queueing, aggregate/member results and idempotency. Invalid/full-capacity batches schedule nothing; runtime member failures are independent and never retried. Library/service validation, named controller actions and examples are included. 141 Python tests pass; production Stream Deck backend and Android Dart client pass simulator API contract checks. Android group power/scene recall and per-member results are implemented; 77 Flutter tests and clean analysis pass, APK built/signed/installed. Phone locked, so new on-phone UI acceptance remains pending. No physical lamp commands or desktop interaction.

## Android CI (2026-09-26)
Added a workflow pinned to the locally verified Flutter revision, enforcing pubspec.lock, running analysis/Flutter tests, the real Dart-to-Python API smoke, APK build and native shortcut tests. Existing Python, Stream Deck and ESP32 workflows remain. Local validation passed; the new workflow has not run on GitHub and no release artifact is published by it.

## Hub RGB calibration (2026-09-26)
Optional per-light gains match Android's 0..1 range and half-up rounding, apply once at static RGB packet generation, and preserve requested RGB for later brightness changes. Native effects and power remain unchanged. MQTT/groups/scenes inherit the same delivery path. Snapshot restoration isolates gain changes; legacy neutral snapshots work. Android validates/displays advertised balance. Full suites: 148 Python and 78 Flutter tests pass, analysis clean; real Dart/Python simulator checks include calibrated wire color. Existing live settings were not changed and physical shade acceptance remains pending.

## Android library editing (2026-09-26)
Rooms/groups can be renamed, retyped and have membership edited. Scenes can be renamed and have membership/On-Off edited; saved snapshots stay intact unless latest applied colors are explicitly recaptured. No commands are sent by edits. Cancel, duplicate names, empty membership and persistence failure are tested, including same-named scene/collection isolation and retained default device. 82 Flutter tests pass; analysis clean. Physical UI acceptance remains pending while phone is locked.

## Android rooms/scenes backup (2026-09-26)
Added clipboard JSON export and reviewed merge import. Existing definitions are retained, conflicting names get numbered copies, default/names/calibration stay local and imports require matching saved lights/profiles. Demo/live separation, capability validation, bounded input and size limits apply before saving. No transport is used by import/export. Full Flutter suite: 90 tests pass with clean analysis, including narrow-screen import and storage-failure recovery. Phone disconnected before latest install; current exported APK needs installation and physical UI checks later.
