# Protocol evidence and validation
## Baseline
The original repository contains two Python scripts and no automated suite. It has 15 CLI prefix mappings but only five interactive-menu profiles. Existing packet encoders are evidence of prior implementation, not fresh physical verification.

Menu profiles inherited from baseline:
| Prefix | Service | Write | Color format |
| --- | --- | --- | --- |
| KS03~ | AFD0 | AFD1 | extended RGB + brightness |
| KS03- | FFF0 | FFF3 | standard RGB |
| KS04- | FFF0 | FFF3 | standard RGB |
| KS01- | AE00 | AE01 | standard RGB |
| KS02- | AE00 | AE01 | standard RGB |

The remaining CLI mappings remain experimental power-command candidates. Do not promote them to RGB support without evidence.
Baseline uses power packets 5BF001B5 / 5B0F01B5 across all profiles; universality is unverified.
Extended RGB example red/full: 5A0001FF000000FF00A5.
Standard RGB example red: 7E070503FF000000EF.
White-mode brightness full from the encoder: 5A000200000000FF00A5.
These are regression fixtures; physical effects remain to be verified.

## Evidence levels
Unknown -> inherited implementation -> APK observed -> hardware tested.
Track evidence per capability, device variant, firmware if known, Android/host platform, date and test result.
An APK-derived command is not hardware-tested. Never guess segment, timer or effect IDs based only on neighboring values.

## APK research intake
User may provide a local APK or attach it. Record hash, package name, version and source supplied by user. Keep binary/decompiled material in ignored research storage, not public deliverables.
Inspect UUID mappings, command builders, initialization, notification parsers, effect IDs, timer encoding and write pacing. Document only the interoperability findings needed for an original implementation; do not copy artwork or UI assets.
Hardware trials use narrowly selected understood commands. No firmware-update or arbitrary raw-packet probing in normal controls.

## Automated tests
- Golden packet fixtures including 0/255 boundaries and invalid types/ranges.
- CLI discovery without address, explicit-address bypass, ambiguous matches and nonzero partial-failure exit.
- Transport fallback, timeout, cancellation, disconnect on write failure.
- Queue ordering, stale-frame cancellation, effect stop/restore, bounded load.
- Group partial failures and no head-of-line blocking across independent targets.
- API auth/scopes, schema validation, idempotency and event resync.
- MQTT reconnect, discovery removal, retained-command rejection and deduplication.
- Scene import migrations and no credential leakage.
- Cross-language fixtures once Android encoders exist.
A mock transport verifies logic only, not BLE compatibility.

## Hardware acceptance checklist
Record phone model, Android version, light name/prefix, count, host/adapter and firmware where available.
Test permissions denied then granted; Bluetooth off/on; first scan; connect; power; primary colors; dimming; repeated slider use; out-of-range recovery; light power cycle; app restart; phone screen off; hub restart.
For groups: test one unavailable target, measured command latency, practical concurrent connection limit and timing spread. Define effect update rate from measurements.
For integrations: Android changes reflected on Stream Deck/HA; physical button reflected in app; no competing ownership; broker unavailable; lost Wi-Fi; stop always takes precedence.
Do not initiate physical lighting changes without a clear testing session with the user.

## Release gates
Unit tests and simulated integration tests pass; Android real-device basic controls pass; every advertised model/capability has a documented verification status.
iOS, music capture, background schedules and device-native effects remain deferred or experimental until separately tested.
