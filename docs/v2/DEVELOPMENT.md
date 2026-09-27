# Development handoff

## Checkout
Repository: https://github.com/H4ch1Net/ks-led-controller
Local branch: ks-light-v2-foundation
Base: 458eccb686f07ef937f1e073007f6d4c6b138258
Changes are local and uncommitted; nothing has been pushed or published.

## Reproduce the first checks
On Windows, from the repository root:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --require-hashes -r requirements.lock
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
git diff --check
```

Observed environment: Windows, Python 3.10.11, Bleak 3.0.2.
requirements.txt pins Bleak 3.0.2. Python 3.10+ is the baseline. Transitive packages and platform markers are hash-locked in requirements.lock; optional controller tools use requirements-controllers.lock. CI is configured but has not run remotely; see QUEUE_AND_SIMULATOR.md.

## Current changes
- CLI scans when --address is absent.
- Ambiguous prefix selection exits without writing, listing candidate addresses.
- Duplicate scan entries for one address do not count as multiple lights.
- Bulk operations continue after a device failure and then exit nonzero.
- Nonpositive/nonfinite scan timeouts are rejected before discovery.
- 53 tests cover CLI, packets, storage, menu, mocked BLE transport, queues and simulator; no lights are touched.

## Next work
Read PRODUCT.md, ARCHITECTURE.md and PROTOCOL_AND_TESTING.md before extending code.
F05/F06 are implemented in ks_light/. Shared fixtures are in protocol/golden_packets.json.
F07/F08 are implemented. See CLI_GUIDE.md for new commands and state limitations.
F09/F10 implemented; review QUEUE_AND_SIMULATOR.md. Android prototype scaffolded; next is physical-phone validation and mobile persistence/lifecycle hardening.
Do not introduce new device commands until their evidence is recorded.
Android prototype is implemented; see ANDROID.md. API server, hub, integrations and effect engine are not implemented.

## Outputs
The planning pack is a readable snapshot. The source archive contains the modified repository files, docs and tests without .git, environment packages, caches or APK material.
Continue development in the existing local checkout rather than editing exported copies independently.

Android continuation: user accepted calibration. M3 initial rooms/groups/scenes and persistent catalog are implemented, including per-target partial failure handling. See ROOMS_AND_SCENES.md. 40 Android tests pass. Next is M4 effect scheduling/stop/restore with measured or conservative BLE timing; physical multi-light acceptance is still open.

M4 Android foreground preview now exists; see EFFECTS.md. Hub API, MQTT/Home Assistant and hub effect hosting remain unimplemented. Next: physical effect timing/stop acceptance and M5 authenticated hub action service/API.

Current continuation (2026-09-23): Android direct control, widgets, Quick Settings and Device Controls are implemented; authenticated hub, MQTT/HA bridge, service packaging and initial Android hub client also exist. M6 now has named action CLI and Windows launchers; see CONTROLLER_ACTIONS.md. User has deferred device testing while the phone is disconnected. Historical sections above describe earlier milestones, not current missing features.

Current continuation (2026-09-26): see CURRENT_STATUS.md for the authoritative remaining work. Hub library and Android collection UI, ESP32 rotary/status LEDs and cross-language API checks are now implemented. Use `flutter --no-version-check` with the pinned SDK for local checks to avoid a background SDK tag fetch. Reproduce the cross-language simulator check from repo root with `python -m apps.android.tool.smoke_hub --dart PATH_TO_DART`. Android CI pins Flutter 3.47.5 revision 6a19cca56475dbfba1478ee68d7bd0c2ef891da1; remote CI remains unrun.
