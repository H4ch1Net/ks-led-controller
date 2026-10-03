# Hub API

The KS Light hub (`ks_light.hub`, or `ks_light.service` for unattended use) owns the Bluetooth connection to its configured lights and exposes an authenticated local HTTP API. Android hub mode, Stream Deck, keyboard actions, Raspberry Pi and ESP32 controllers and the [MQTT bridge](HOME_ASSISTANT.md) all go through it, so only one process writes to each lamp.

Base URL: `http://127.0.0.1:8765/api/v1`. JSON throughout. Built on aiohttp.

## Run in the foreground

From the repository root, after `pip install --require-hashes -r requirements.lock`:

```sh
python -m ks_light.hub                                   # simulation with demo lights
export KS_LIGHT_TOKEN="$(python -c 'import secrets; print(secrets.token_urlsafe(32))')"
python -m ks_light.hub --ble --config lights.json        # real lights
```

PowerShell: `$env:KS_LIGHT_TOKEN = (python -c "import secrets; print(secrets.token_urlsafe(32))")`.

Without `--config`, the simulation has three demo lights (`desk`, `shelf`, `ceiling`) and a demo library with a `living` group and `evening`, `focus` and `off` scenes. If `KS_LIGHT_TOKEN` is unset in simulation, the hub generates a temporary token and prints it at startup. `--ble` always requires `KS_LIGHT_TOKEN`.

| Option | Meaning |
| --- | --- |
| `--ble` | Send real Bluetooth writes. Requires `--config`. Without it the hub runs a labelled simulation. |
| `--config FILE` | Light catalog (see below). Also enables calibration editing through the API. |
| `--library FILE` | Group and scene library; see [HUB_LIBRARY.md](HUB_LIBRARY.md). Enables library editing. |
| `--credentials FILE` | Scoped controller credentials (see below). |
| `--port` | Default 8765. |
| `--mqtt-*` | MQTT bridge; see [HOME_ASSISTANT.md](HOME_ASSISTANT.md). |

The foreground hub always binds `127.0.0.1`. For a service, a non-loopback HTTPS listener, persisted state and secret files, use [SERVICE_DEPLOYMENT.md](SERVICE_DEPLOYMENT.md).

### Light catalog

```json
{"lights": [{"id": "desk", "name": "Desk light", "prefix": "KS03~", "address": "AA:BB:CC:DD:EE:FF"}]}
```

1 to 64 lights. `id` is 1 to 64 letters, digits, `_` or `-`; it is the client-facing name. Addresses are never returned by the API. IDs and addresses must be unique. `prefix` must be a known profile (see [PROTOCOL_AND_TESTING.md](PROTOCOL_AND_TESTING.md)). Optional `calibration` is described below. Examples: `examples/hub-lights.example.json`, `examples/hub-multi-light.example.json`, `examples/hub-calibrated-lights.example.json`.

## Dashboard

The hub serves a browser dashboard at `/` (for example `http://127.0.0.1:8765/`). It is plain HTML, CSS and JavaScript in `ks_light/web/`, with no build step and no external requests.

- Sign in with the operator token or a scoped credential. The token stays in the tab's session storage, or in local storage when **Remember on this device** is checked. Static files need no token; every API call does.
- Lights show power, brightness, color presets, a custom color picker and, for KS03~, built-in effects. Scenes and groups can be applied from the side panel.
- The activity list shows operations from every client, fed by the event poll described below, so changes from Home Assistant or Stream Deck appear live.
- The page is served with a strict Content Security Policy. Browser API requests are accepted only when `Origin` equals the hub's own origin, and only on a loopback host unless the listener uses TLS.
- Disable it with `python -m ks_light.hub --no-dashboard` or `"dashboard": false` in the service configuration.

![Hub dashboard](images/hub-dashboard.png)

## Authentication

Every request, including `/health`, needs `Authorization: Bearer <token>`.

- **Operator token**: `KS_LIGHT_TOKEN` (foreground) or `token_file` (service). At least 32 non-whitespace ASCII characters. Full access. Changing it and restarting revokes the old one. A configured token is never printed or logged.
- **Scoped controller credentials**: optional per-controller tokens with `read` or `control` scope, limited to a list of light IDs. `control` includes read.

Cross-origin browser requests (an `Origin` header that is not the hub's own origin, see [Dashboard](#dashboard)) are rejected with 403; CORS is not enabled. JSON bodies need `Content-Type: application/json` and are limited to 16 KiB.

### Scoped credentials

Create a credential (the token is written to a new file and never printed; existing files are never overwritten):

```sh
python -m ks_light.credentials --file hub-private/credentials.json --catalog hub-private/lights.json \
  --id streamdeck --scope control --lights desk --token-out hub-private/streamdeck-token
```

Revoke it:

```sh
python -m ks_light.credentials --file hub-private/credentials.json --catalog hub-private/lights.json --id streamdeck --revoke
```

Enable the registry with `--credentials FILE` or the service field `credentials_file`, then restart once. After that the file is re-read on every scoped request, so creation and revocation take effect without a restart. Revocation blocks new requests; it does not cancel work already accepted.

The registry stores SHA-256 hashes of random 256-bit tokens. Limits: 64 credentials, 1 to 64 lights each, 64 KiB file. Keep the registry and token files private and use one writer at a time.

What a scoped token sees:

- Lights it is allowed, and groups or scenes whose members are all allowed.
- Operations and events only for allowed lights. Event cursors are global, so gaps in sequence numbers are normal.
- `/health` and `/capabilities`.
- No library or calibration editing.

A `read` token cannot submit any mutation. If the registry file becomes invalid, scoped tokens fail with 503 until it is fixed; the operator token keeps working. MQTT access is controlled by the broker, not by this registry.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/health` | Status, mode, instance ID, persistence and MQTT state |
| GET | `/capabilities` | Feature flags and limits |
| GET | `/lights` | Allowed lights, last-sent state, event cursor and instance ID |
| GET | `/lights/{id}` | One light |
| PATCH | `/lights/{id}/state` | Power, color, brightness |
| POST | `/lights/{id}/effects/native` | Start a KS03~ built-in effect |
| GET | `/lights/{id}/calibration` | RGB gains, presets and ETag |
| PUT | `/lights/{id}/calibration` | Replace calibration (operator, `If-Match`) |
| GET | `/groups`, `/scenes` | Library definitions |
| PATCH | `/groups/{id}/state` | State for every member |
| POST | `/groups/{id}/effects/native` | Native effect for every member |
| POST | `/scenes/{id}/apply` | Recall a scene; body `{}` |
| GET | `/library` | Full library document and ETag (operator) |
| PUT | `/library` | Replace the library (operator, `If-Match`) |
| GET | `/operations/{id}` | Operation status |
| GET | `/events?after=N&instance=I&wait=S` | Events after cursor N |

Group, scene and library behavior is described in [HUB_LIBRARY.md](HUB_LIBRARY.md).

### Light response

```json
{"id": "desk", "name": "Desk light", "prefix": "KS03~",
 "calibration": {"rgb_gains": [1, 1, 1]},
 "last_sent": {"power": true, "rgb": [239, 66, 255], "brightness": 35},
 "restored": false, "confirmation": "unconfirmed",
 "capabilities": {"rgb": true, "brightness": true, "native_effects": true}}
```

`last_sent` is `null` when unknown. With a native effect it holds `native_effect`, `speed` and `brightness`. `restored: true` means the value was loaded from disk at startup (see persistence in [SERVICE_DEPLOYMENT.md](SERVICE_DEPLOYMENT.md)).

## Commands

### State

```json
{"power": true, "rgb": [239, 66, 255], "brightness": 35}
{"power": false}
{"power": true, "brightness": 60}
```

| Field | Rule |
| --- | --- |
| `power` | Boolean. Off keeps the remembered color. |
| `rgb` | Three integers 0 to 255. |
| `brightness` | Integer 0 to 100 (percent). Only KS03~ supports values other than 100. |
| `transition_ms` | Only `0` is accepted. |

- Any request with `rgb` or `brightness` must include `"power": true`, because the color packet can turn the lamp on.
- Brightness without `rgb` needs a remembered color or native effect for that light. For a native effect it changes brightness and keeps the effect and speed (must be 1 to 100; send Off to stop).
- Partial updates resolve against the last-sent state when the command reaches the front of the light's queue.
- Unknown fields, booleans in place of integers, and out-of-range values are rejected with 422 before queueing.

### Native effect (KS03~)

```json
{"effect": 137, "speed": 35, "brightness": 50}
```

`effect` is 130 to 138 (0x82 to 0x8A; see [EFFECTS.md](EFFECTS.md)), `speed` 0 to 100, `brightness` 1 to 100. The hub sends power-on plus one effect packet. The lamp keeps animating after the hub disconnects or stops. Send Off, or a static color, to end it. Calibration does not apply to native effects.

### Operations

A valid command returns `202 {"operation_id": "op_...", "status": "queued"}`. Poll `GET /operations/{id}` until `status` is `succeeded`, `failed` or `cancelled`. Group and scene operations also have a `members` array.

`confirmation` is `simulated` or `unconfirmed`. `succeeded` means the transport accepted every write; it is not physical readback. A failed delivery clears that light's last-sent state, because part of the command may have reached the lamp. The hub never retries a physical write.

### Idempotency

Send a unique `Idempotency-Key` header (1 to 128 characters: letters, digits, `_ . : -`) with each user action. Repeating the same key with the same target and body returns the original operation. The same key with a different intent returns 409 `idempotency_conflict`.

### Limits

| Limit | Value |
| --- | --- |
| Retained operations | 256; kept 10 minutes after completion; 429 `operation_capacity` when full |
| Pending commands per light | 8; 429 `queue_full` when full |
| Simultaneous Bluetooth sessions | 2 |
| Idle BLE session reuse | 30 seconds, 100 ms packet spacing |
| Events retained | 512 |

Commands for one light run in order; different lights can run concurrently. State commands are serialized, not coalesced. Operations and idempotency keys are in memory and disappear on restart. Nothing is replayed after a restart.

### Errors

Errors return `{"error": "<code>"}`.

| Status | Typical codes |
| --- | --- |
| 400 | `invalid_json`, `invalid_idempotency_key`, `invalid_cursor` |
| 401 | `unauthorized` |
| 403 | `read_only_credential`, `target_not_allowed`, `operator_required`, `browser_origin_not_allowed` |
| 404 | `light_not_found`, `collection_not_found`, `operation_not_found` |
| 409 | `idempotency_conflict`, `resync_required`, `commands_in_progress`, `configuration_changing`, `*_file_changed_restart_required` |
| 412 | `library_version_changed`, `calibration_version_changed` |
| 415 | `json_required` |
| 422 | `color_requires_explicit_power_on`, `remembered_color_required`, `unsupported_capability`, `unsupported_brightness`, `invalid_native_effect`, `unknown_fields` and other validation codes |
| 429 | `operation_capacity`, `queue_full` |
| 503 | `credentials_unavailable`, `library_save_failed`, `calibration_save_failed` |

## Events

Events are JSON long polling; there is no WebSocket.

1. `GET /lights` and keep its `cursor` and `instance`.
2. `GET /events?after=<cursor>&instance=<instance>&wait=25`. The hub answers immediately if newer events exist, otherwise waits up to `wait` seconds (0 to 25, default 0).
3. Use the returned `cursor` for the next call.

Each event has `version`, `sequence`, `type` (`operation.updated` or `light.updated`), `target_id`, `operation_id` and `timestamp`. Events say what changed; fetch the light or operation for current values.

409 `resync_required` means the cursor expired, is ahead of the server, or the instance changed (the hub restarted). Fetch `/lights` again and continue from its cursor. An event timeout is not a reason to resubmit a command.

## Health and capabilities

`/health` returns HTTP 200 while the API runs. `status` is `ok`, or `degraded` when a configured MQTT bridge is not `online` or persistence has a storage error. `mqtt.state` is one of `disabled`, `starting`, `connecting`, `online`, `retrying`, `failed`, `stopped`, with an attempt count, a sanitized error category and the configured retry delay. Credentials and raw exception text are never returned.

`/capabilities` reports `api_version`, `authentication` (`single_operator_bearer` or `scoped_bearer`), `groups`, `scenes`, `events: "polling"`, `event_wait_seconds`, `device_readback: false`, `websocket: false`, `library_edit`, `calibration_edit`, `calibration_model: "static_rgb_gains"`, `durable_last_sent`, `native_effects` (ID and name list), and operation limits.

## Calibration

A catalog entry may include per-light RGB gains:

```json
{"id": "desk", "name": "Desk", "prefix": "KS03~", "address": "...", "calibration": {"rgb_gains": [1, 0.3, 0.75]}}
```

Gains are three numbers from 0 to 1 (omitted means neutral). They are applied once when a static color packet is built, with the same rounding as Android, for every path: HTTP, MQTT, groups and scenes. `last_sent.rgb` stays the requested color, so brightness-only updates do not compound the gains. Power and native effects are unaffected. Phone calibration is not imported; to copy it, divide the Android channel percentages by 100.

With a catalog file configured, operator clients can edit calibration:

- `GET /lights/{id}/calibration` returns `{"calibration": {"rgb_gains": [...], "presets": {...}}, "built_in_presets": {...}}` and an `ETag`.
- `PUT` the same path with `If-Match: <etag>` and a body such as `{"rgb_gains": [1, 0.3, 0.75], "presets": {"Purple": [1, 0.3, 0.75]}}`. Up to 20 presets with 1 to 40 character names.

The catalog file is replaced atomically. Edits are refused while commands are active (409), on a stale tag (412), or if the file changed on disk since startup (409, restart required). Changing gains clears the light's last-sent state; the next color command uses the new gains. No command is sent by editing. The catalog is limited to 256 KiB.
