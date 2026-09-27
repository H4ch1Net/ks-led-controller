# Hub groups and scenes

The hub can apply one state/effect to a configured group or recall a scene containing different settings for each light. HTTP clients, Android Hub control, keyboard launchers, Stream Deck keys/action dials and Raspberry Pi buttons share these operations. Android currently offers group power and scene recall. The Android direct-Bluetooth library is separate; automatic import/remapping is not implemented.

## Configure and try in simulation

Use `examples/hub-multi-light.example.json` with `examples/hub-library.example.json`. These define desk/sofa lights, a room group, an evening scene and an all-off scene. With your existing private `KS_LIGHT_TOKEN` environment variable set:

```powershell
.venv/Scripts/python.exe -m ks_light.hub --config examples/hub-multi-light.example.json --library examples/hub-library.example.json
```

The default remains simulation. For an installed service, add `"library_file":"library.json"` to its private config and place the library beside it. Relative paths resolve from that config. Run the service's `--check` before restarting. The library is loaded at startup; startup never recalls a scene. No live service configuration was changed during development.

Version 1 requires `version`, `groups` and `scenes`. Each group has `id`, `name`, and unique `members` referencing configured light IDs. Each scene has `id`, `name`, and `actions`: one `{light,type,body}` per target. Types are `state` or `native` with the same bodies as individual-light commands. Scene brightness requires explicit RGB; it cannot depend on remembered color. Off and power-on-only scene actions are allowed. Native effects require a supported profile.

Limits: 256 KiB per library file, 32 groups, 32 scenes, and 1–64 unique light targets per entry. Names are 1–80 nonblank characters; IDs use 1–64 letters, digits, underscores or hyphens. Unknown fields, missing lights, duplicate members and unsupported scene commands fail startup validation. Definitions are copied before use. Operator-only library editing is available when a library file is configured; see below.

## API

All endpoints require the existing bearer token. Under `/api/v1`:

| Request | Body / result |
| --- | --- |
| `GET /groups` | Configured groups; no physical addresses |
| `GET /scenes` | Configured scene definitions |
| `PATCH /groups/room/state` | For example `{"power":false}` |
| `POST /groups/room/effects/native` | For example `{"effect":137,"speed":35,"brightness":50}` |
| `POST /scenes/evening/apply` | Empty JSON object `{}` |
| `GET /operations/{id}` | Aggregate status plus per-light `members` |

Mutation requests return 202 with one operation ID. Use a unique `Idempotency-Key` for each deliberate action. Repeating the same key and intent returns that original operation, including after partial failure. Reusing it for a changed intent returns 409.

Every member is validated and queue capacity is checked before any member is scheduled. Invalid members return 422; unavailable admission capacity returns 429 with no new work. Once accepted, normal per-light serialization and the two-connection global limit apply. **Delivery is not atomic or simultaneous**: a healthy light can complete while another fails or times out. There is no rollback or automatic retry.

The aggregate stays `queued` while any member is unfinished. Member statuses update independently. It finishes `succeeded` only if every member succeeds, `cancelled` if all are cancelled, or `failed` otherwise. Mixed success/failure uses `error:partial_failure`; the `members` array identifies each outcome. Confirmation remains `simulated` or `unconfirmed`, never physical readback. Standard operation retention, event cursors and optional per-light last-sent persistence apply. Operations disappear on restart and are never replayed.

## Named controllers

Copy `examples/controller-library.example.json` into your private configuration directory and point its token file at the hub token. A group action uses `group` instead of `light`; a saved scene uses `scene`, type `apply`, and an empty body. Specify exactly one target kind.

```powershell
.venv/Scripts/python.exe -m ks_light.controller --config path/to/controller.json room-off
.venv/Scripts/python.exe -m ks_light.controller --config path/to/controller.json evening
```

The CLI prints member results and exits 1 for partial failure. Existing Stream Deck and Pi named-action settings can select these names without another transport. Stream Deck reports failure if any member fails; detailed member results are available through the API/CLI. Brightness overrides support explicit group color/native actions; scene overrides are rejected. Large groups can exceed a controller's default 20-second wait; configure its bounded timeout appropriately. A timeout must never cause an automatic resubmission.

## Evidence

Automated checks cover admission without partial scheduling, mixed profile rejection, independent member completion/failure, shutdown cancellation, idempotency, authenticated catalog access, strict library validation, controller subprocess results and service preflight. The packaged Stream Deck backend was exercised against a simulated host and real local API for group success and partial scene failure. These checks use simulator/fake senders, not physical lights. Multiple-lamp acceptance remains pending.

## Android group controls

Open Color & effects on a hub group to preview a shared color, brightness or Purple breathing effect. Apply explicitly turns every member on; Cancel and Back send nothing. Controls appear only when every member advertises support. Brightness alone preserves each member’s last hub color or native effect; missing compatible state rejects admission before any new command is scheduled. Mixed RGB profiles without shared dimming apply color at full brightness. Hub calibration remains per light and is applied once by the server. Per-member results remain visible after partial failure, with no automatic retry.

Narrow-screen widget tests cover preview/cancel, duplicate callbacks, native routing, invalid color input and capability intersection. The production Dart/Python contract smoke checks group state/effect writes and distinct calibrated packet values. Phone and physical multi-light acceptance remain pending.

## Editing through the API

With `--library` or service `library_file` configured, the operator token can `GET /api/v1/library` to retrieve the complete versioned document and its `ETag` header. `PUT /api/v1/library` replaces it with a validated document; supply that exact tag in `If-Match`. This supports creating, renaming, changing members/actions and deleting groups or scenes by editing the lists. The JSON request is bounded by the API's 16 KiB body limit; larger libraries must still be maintained in files.

Scoped controller credentials cannot edit or read the complete management document. Version mismatch returns 412. Commands in progress, another edit or an unexpected external file change return 409. External changes require restarting/reloading configuration before API edits resume. Invalid definitions return 422 and storage failure returns 503. File replacement and in-memory publication happen together; edits send no lamp commands. Editing definitions from Android's hub screen remains future work; its existing controls use the updated catalog after Refresh.

A single process must own these configuration files. Avoid external writes while API editing is active. Tests cover persistence, stale editors, invalid members, busy delivery, filesystem failure and detection of external changes.
