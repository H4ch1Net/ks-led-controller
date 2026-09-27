# Architecture and decisions
## Runtime layout
Android (provisionally Flutter/Dart) -> direct BLE OR KS Hub.
Stream Deck / Windows shortcuts / DIY clients -> KS Hub API or MQTT.
Home Assistant -> MQTT broker -> KS Hub.
KS Hub -> Python controller library -> BLE lights.
Raspberry Pi GPIO adapter -> same hub action service.

## Repository target
- ks_light/: Python protocol profiles, command builders and transport.
- hub/: action service, persistence, effects, API and MQTT adapter.
- apps/android/: Flutter application with native Android integration where necessary.
- integrations/streamdeck/: TypeScript plugin.
- integrations/windows/: tray companion and shortcuts.
- examples/diy/: versioned board-specific sketches and wiring guides.
- protocol/: language-neutral profiles, schemas and golden packet fixtures.
- tests/: unit, simulated transport and integration checks.
- docs/v2/: authoritative planning and status.
This is a target structure, not a claim those components already exist.

## Decisions
D01: Keep Python for the hub/CLI and Dart for mobile provisionally. Share protocol data and golden fixtures; do not embed the Python runtime in Android.
D02: Validate Flutter BLE lifecycle and permissions on the user's Android phone before full UI work. Select the BLE dependency after license, maintenance and real-device checks.
D03: MQTT-backed Home Assistant integration ships first. A native HA integration is deferred.
D04: KS Hub exposes one internal action service behind REST, WebSocket, MQTT and GPIO.
D05: A light has one assigned transport owner. Hub clients do not open competing BLE connections. Ownership is an application convention; it cannot prevent the original vendor app connecting.
D06: Run the hub on a supported Linux/Pi installation first. Document an optional Windows host after Bluetooth behavior is tested. Do not promise all container Bluetooth configurations.
D07: Preserve legacy entry points while migrating their implementation into the library.

## Data and persistence
Use stable internal IDs independent of device addresses. Device records contain transport identity, profile, user name, room, owner, evidence and capabilities.
A scene contains per-light desired states. An effect definition contains type, palette, timing, brightness envelope and ordered targets. An effect run contains its ID, owner, start time, saved prior state and status.
Persist configuration and migrations in SQLite on the hub; use transactional mobile storage. Keep tokens in OS-appropriate protected storage. Shared scene files use a versioned JSON schema and logical target names requiring remapping on import.

## Command execution
Serialize commands per light; cap global connections according to tested adapter capacity. Resolve GATT characteristics and supported write properties instead of blindly probing unrelated characteristics.
Coalesce superseded slider/effect values. Preserve ordering for on-plus-color sequences. Time-limit operations and bound retries; cancel stale queued work after disconnect.
Use a monotonic clock for effects. Drop missed frames instead of replaying a backlog. Group commands are best-effort with per-light results, never advertised as atomic or precisely simultaneous.
Stopping increments a run generation so late frames cannot overwrite restoration. Manual commands supersede affected queued frames.
Readback, when verified, updates confirmed state. Otherwise preserve requested state with an explicit unconfirmed status.

## Host and controller ownership
Pair clients to a selected hub; associate each light with direct-phone or hub ownership. Handoff stops effects, drains/cancels pending work and disconnects before the other side connects.
When a hub is offline, show the failure; direct takeover requires an explicit choice. A changed owner must not silently reconnect in the old controller.
Restore on effect stop uses the snapshot taken at start, only where no newer manual command has superseded it. Hub restart leaves effects stopped and devices unconfirmed.

## Scheduling and networking
Hub schedules use an explicit timezone and defined daylight-saving behavior. Default: skip missed runs while offline; never burst replay. Use a documented duplicate-run guard across restarts.
Bind locally by default; LAN exposure is an explicit setup choice. Pair with short-lived setup credentials and issue revocable scoped tokens. Remote access is deferred; no automatic port forwarding.
MQTT uses broker credentials and topic ACL guidance; retained state is allowed, retained command replay is rejected.
