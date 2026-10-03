# Hub groups and scenes

A hub library defines groups (one command applied to several lights) and scenes (different settings per light). HTTP clients, Android hub mode, keyboard actions, Stream Deck and Raspberry Pi controllers use the same operations. The Android direct-Bluetooth library ([ROOMS_AND_SCENES.md](ROOMS_AND_SCENES.md)) is separate and not synchronized.

## Try it in simulation

```sh
python -m ks_light.hub --config examples/hub-multi-light.example.json --library examples/hub-library.example.json
```

This defines `desk` and `sofa`, a `room` group, an `evening` scene and an `all-off` scene. For a service, set `library_file` in its configuration (relative to that file) and run `--check` before restarting. The library loads at startup; no scene is recalled at startup.

## File format

```json
{
  "version": 1,
  "groups": [{"id": "room", "name": "Room", "members": ["desk", "sofa"]}],
  "scenes": [{"id": "evening", "name": "Evening", "actions": [
    {"light": "desk", "type": "state",  "body": {"power": true, "rgb": [255, 190, 120], "brightness": 35}},
    {"light": "sofa", "type": "native", "body": {"effect": 137, "speed": 35, "brightness": 25}}
  ]}]
}
```

- `version`, `groups` and `scenes` are all required; unknown fields are rejected.
- IDs: 1 to 64 letters, digits, `_` or `-`. Names: 1 to 80 characters, not blank.
- A group has 1 to 64 unique configured lights.
- A scene has 1 to 64 actions, one per light. `type` is `state` or `native` with the same body as a [single-light command](HUB_API.md#commands). Scene brightness requires an explicit `rgb`, so a scene never depends on remembered color. Off and power-on-only actions are allowed.
- Limits: 256 KiB file, 32 groups, 32 scenes.

Missing lights, duplicate members and commands a light cannot perform fail validation at startup.

## API

| Request | Body |
| --- | --- |
| `GET /groups`, `GET /scenes` | none |
| `PATCH /groups/{id}/state` | State body, for example `{"power": false}` |
| `POST /groups/{id}/effects/native` | `{"effect": 137, "speed": 35, "brightness": 50}` |
| `POST /scenes/{id}/apply` | `{}` |

Each call returns 202 with one operation ID. Idempotency keys work as for single lights.

Before anything is scheduled, every member is validated (422 on any invalid member) and queue capacity is checked for all of them (429 with no work admitted). After admission each member uses its own light queue.

**Delivery is not atomic or simultaneous.** One light can succeed while another fails. There is no rollback and no retry.

The operation stays `queued` until every member finishes. Its `members` array holds each light's `status`, `confirmation` and `error`. Final status:

| Status | When |
| --- | --- |
| `succeeded` | Every member succeeded |
| `cancelled` | Every member was cancelled |
| `failed` | Anything else; `error` is `partial_failure` if at least one member succeeded, otherwise `members_failed` |

## Editing through the API

`GET /library` returns the full document with an `ETag`. `PUT /library` with `If-Match: <etag>` replaces it after full validation; edit the lists to create, rename, change or delete entries. Both require the operator token. PUT requires a configured library file and is bounded by the 16 KiB request limit; maintain larger libraries as files.

| Response | Cause |
| --- | --- |
| 412 | Stale ETag |
| 409 | Commands in progress, another edit running, or the file changed on disk (restart required) |
| 422 | Invalid document |
| 503 | Storage failure |

The file is replaced atomically and the new definitions take effect immediately. Editing sends no lamp commands. One process should own the library and catalog files; avoid editing them by hand while the hub runs.

Android hub mode provides an editor for the same document (**Edit rooms & scenes** on the Hub tab).

## Named controller actions

Controller configurations ([CONTROLLER_ACTIONS.md](CONTROLLER_ACTIONS.md)) can target groups and scenes. See `examples/controller-library.example.json`:

```json
"room-off": {"group": "room", "type": "state", "body": {"power": false}},
"evening":  {"scene": "evening", "type": "apply", "body": {}}
```

Exactly one of `light`, `group` or `scene` per action. The CLI prints member results and exits 1 if any member failed or was cancelled. Group color and effect actions accept `--brightness`; scene actions reject it. Large groups can exceed the default 20-second controller timeout; raise `timeout_seconds` (up to 120) if needed. A timeout never triggers resubmission.
