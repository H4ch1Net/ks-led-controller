# Local hub API

## Status and scope
Implemented: authenticated loopback HTTP server, explicitly labelled simulator, configured BLE adapter, light discovery through a static catalog, power/RGB/brightness/native-effect commands, per-target queueing, operation polling, idempotency keys, and bounded polling events. Configured groups/scenes, optional durable last-sent state and the MQTT/Home Assistant bridge are also implemented.

Android offers direct Bluetooth control and an initial separate hub screen. Android calibration and saved presets are not imported into the hub. No physical BLE writes were made during this API milestone. Use a single Bluetooth controller at a time; cross-process ownership negotiation remains planned.

## Start on Windows
From the repository root:

```powershell
.venv/Scripts/python.exe -m pip install --require-hashes -r requirements.lock
$env:KS_LIGHT_TOKEN = (.venv/Scripts/python.exe -c "import secrets; print(secrets.token_urlsafe(32))")
.venv/Scripts/python.exe -m ks_light.hub
```
Default address: http://127.0.0.1:8765/api/v1. Default mode: simulation, with one virtual `desk` light. The token is not logged or written by the server. Use the same token in clients; changing it and restarting revokes the old token. There is one full-access operator token; per-client tokens, read-only scopes, pairing and target restrictions are future work. The server binds loopback only, does not enable CORS, and rejects browser Origin headers. Do not expose it publicly. Service deployment and trusted TLS setup are documented in SERVICE_DEPLOYMENT.md; these commands do not alter firewall settings.

For BLE mode, edit a copy of `examples/hub-lights.example.json` with real light details, then run:

```powershell
.venv/Scripts/python.exe -m ks_light.hub --ble --config path/to/lights.json
```
Each light ID and physical address must be unique. IDs are client-facing names; addresses are not returned by the API. Profiles inherit the project's evidence levels. KS03~ native Purple breathing has Android hardware acceptance; selected Python hub BLE and Home Assistant host MQTT paths were physically accepted in earlier sessions; other profiles and multiple physical lights remain unverified.

## Requests
Every request, including health, needs `Authorization: Bearer <token>`. JSON bodies require `Content-Type: application/json` and are limited to 16 KiB.

| Method | Path under /api/v1 | Purpose |
| --- | --- | --- |
| GET | /health | Health and simulation/BLE mode |
| GET | /capabilities | Implemented subset and limits |
| GET | /lights | Catalog, last-sent states and event cursor |
| GET | /lights/{id} | One light and its capabilities |
| PATCH | /lights/{id}/state | Queue power/color/brightness |
| POST | /lights/{id}/effects/native | Start a KS03~ native effect |
| GET | /groups and /scenes | Configured library definitions |
| PATCH | /groups/{id}/state | Apply state to every member |
| POST | /groups/{id}/effects/native | Apply a native effect to every member |
| POST | /scenes/{id}/apply | Recall a scene, with JSON `{}` |
| GET | /operations/{id} | Poll command completion |
| GET | /events?after={cursor}&instance={instance} | Poll events newer than cursor |

State example: `{"power":true,"rgb":[239,66,255],"brightness":35}`.
Off example: `{"power":false}`. Off preserves remembered color.
Native example: `{"effect":137,"speed":35,"brightness":50}`. This operation explicitly starts the light's built-in effect. Effect IDs 130..138 are gradual modes; 137 is Purple breathing. This mode continues independently after disconnect. Send Off to end the output, or send an explicit static color to replace it.

API brightness is 0..100. KS03~ encodes that percent directly; inherited ceiling profiles permit only full brightness. A color/brightness patch MUST include `power:true`, because supported color commands cannot guarantee preserving an Off state. Brightness-only changes need a remembered RGB color or native effect from a successful command or an optional restored last-sent snapshot. Native brightness updates preserve effect and speed and require 1..100; send Off to stop. Partial updates resolve against the state at delivery time. Unknown fields, booleans masquerading as integers, invalid ranges and unsupported transitions are rejected before queueing. Only `transition_ms:0` is accepted. Native effects do not apply custom RGB calibration.

Success at submission returns HTTP 202 with an operation ID. Poll it until `succeeded`, `failed`, or `cancelled`. `confirmation` is `simulated` or `unconfirmed`: transport success is not physical state readback. Failed delivery invalidates remembered state because writes may have partially reached the light. There is no automatic retry of physical writes.

## Retry and resource limits
Use a unique `Idempotency-Key` for each user action. Identical retries return the same operation; a changed target/action/body with that key returns 409. Keys are 1..128 characters from letters, digits, underscore, dot, colon and hyphen.
Operations and retry keys remain for 10 minutes after completion; they are memory-only and disappear on restart. There are at most 256 retained operations. Capacity exhaustion returns 429 without evicting unexpired retry keys. Per-light queues allow eight pending commands, with two global transport slots and bounded write deadlines. PATCH commands are serialized rather than coalesced, preserving partial-update semantics.

Events are JSON polling, not the draft WebSocket endpoint. The latest 512 events are retained. Events identify changed operations/lights; fetch those resources for current values. An expired cursor or a cursor ahead of a restarted server returns 409 `resync_required`. Fetch GET /lights for a fresh snapshot, its cursor and process instance ID, then include both in subsequent polls. Supplying the old instance after any restart returns resync_required even if the numeric cursor happens to be valid. No infinite delivery guarantee is implied.

## Still planned
Scoped/revocable client credentials, WebSockets, calibration preset import/editing, richer Android hub mode, live library editing and ownership handoff. Configured groups/scenes are available now; see HUB_LIBRARY.md. See API.md for the wider target contract.

## Dependencies
Built with pinned aiohttp 3.14.3. Implementation reference: https://docs.aiohttp.org/en/stable/web_reference.html . Server parsing, body limits, routing and lifecycle use the framework rather than a custom HTTP parser.

## Validation
77 Python tests pass, including 12 hub tests and 12 MQTT tests for authenticated HTTP, strict requests, native/color packets, duplicate retries, expired event recovery, bounded retention, failure isolation and shutdown cleanup. A separate-process command-line smoke test returned simulation health and completed an HTTP native-effect request as simulated. pip check passes. A real KS03 native-effect command subsequently completed over Home Assistant host MQTT and PC BLE; transport delivery passed and visual confirmation is pending.

## MQTT / Home Assistant
The optional MQTT 5 bridge is implemented. See [HOME_ASSISTANT.md](HOME_ASSISTANT.md) for setup, supported commands, state semantics and validation. HTTP and MQTT use the same per-light queues.


## MQTT connection health
`GET /api/v1/health` remains authenticated and returns HTTP 200 for a running API, with `status: degraded` whenever a configured MQTT bridge is not online. Inspect `mqtt.state`: disabled, starting, connecting, online, retrying, failed, or stopped. The MQTT object reports attempt count, a sanitized error category, and the configured retry delay in seconds (not a live countdown). It never returns credentials or raw exception text. HTTP commands remain available during a broker outage.

Reconnect delay grows from 2 to 60 seconds across failures, including brief successful connections that immediately drop. A connection lasting at least 30 seconds resets that delay. Unexpected bridge failures are logged and surfaced as failed instead of leaving health looking normal. These changes do not retry physical light commands.

Optional persistence (2026-09-26): service persist_state=true enables durable last-sent metadata. Capabilities expose durable_last_sent; health exposes persistence.enabled/status and becomes degraded on storage errors. Light responses include restored=true for startup-loaded metadata, always preserving simulated/unconfirmed confirmation. Startup sends nothing and operations/idempotency records are not restored. See SERVICE_DEPLOYMENT.md for failure behavior and limitations.

## Per-light RGB calibration
A light catalog entry may include `"calibration":{"rgb_gains":[1,0.3,0.75]}`. This illustrates red/green/blue multipliers, not a recommendation for any particular lamp. Gains must be finite numbers from 0 to 1; omitted calibration is neutral. Copy accepted Android channel percentages divided by 100 when manually matching a light. There is no automatic phone-settings import. See examples/hub-calibrated-lights.example.json for a neutral template.

Static color packets apply each light's gains once using Android-compatible half-up rounding. This shared delivery path includes HTTP, MQTT, groups and scenes. Brightness remains separate. Last-sent RGB is the requested logical RGB, so brightness-only updates do not repeatedly multiply an already calibrated color. Native effects and power-only commands are unchanged; the lamp generates native colors internally.

`GET /lights` and `/lights/{id}` expose `calibration.rgb_gains`; capabilities advertise `calibration:true` and `calibration_model:static_rgb_gains`. Android displays the selected hub light's balance. Changing the file requires restarting the hub; nothing is sent on startup. Optional persisted state now matches gains as well as device/profile identity: a mismatch restores Unknown instead of a color associated with another balance. Older snapshots without gains are treated as neutral. This is manual color balance, not measured colorimetry or physical state confirmation.

## Controller credentials and event waits

See SCOPED_CREDENTIALS.md for optional per-controller read/control tokens restricted to named lights and revocation without restarting. Operator-only library management is documented in HUB_LIBRARY.md.

`GET /api/v1/events?after=<cursor>&wait=25` waits up to 25 seconds when already caught up, returning sooner when an event occurs. Omit wait for legacy immediate polling. The advertised `event_wait_seconds` capability is 25. Keep the existing instance/cursor resynchronization handling; clients must not treat an event timeout as a reason to resubmit a command. Scoped clients receive filtered events with the global cursor, so sequence gaps are normal. This adds bounded long polling, not WebSockets or physical readback.

## Calibration management

With a configured light catalog (`--config` or service `lights_file`), operator clients can edit color balance without changing lamp output. Capabilities advertise `calibration_edit`; scoped credentials do not receive management capabilities. `GET /api/v1/lights/{id}/calibration` returns `calibration` (rgb_gains and custom presets), built_in_presets and an ETag. `PUT` to the same path requires that tag in If-Match and a body such as `{"rgb_gains":[1,0.3,0.75],"presets":{"Purple":[1,0.3,0.75]}}`. This same object can be imported into the Android editor. Gains must be three finite values from 0 to 1; up to 20 named presets with 1–40 character names are supported. Channel-order remapping is not supported by this hub format.

Stale versions, active commands and externally changed configuration files block edits. Saving atomically updates the existing catalog while preserving other lights. Changed gains invalidate the light’s last-sent snapshot; the next explicit color command uses the new gains once. Saving presets without changing gains preserves the snapshot. No BLE command is sent by calibration editing. A failed snapshot cleanup degrades persistence health; the already-saved catalog remains authoritative. The complete catalog is bounded to 256 KiB.

Android Hub control exposes Edit hub color balance and Manage hub rooms & scenes when authorized and configured. Both use detached drafts and explicit Save. Calibration supports gain sliders, built-in/custom presets and JSON import. Hub scenes preserve existing actions unless recaptured; new entries capture the latest hub RGB/native effect, or power-only when no compatible setting is known. Definition editing sends no lamp commands. Saving an uncertain or rejected request requires reloading before further edits, and backend versions prevent stale overwrites.
