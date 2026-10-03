# Named controller actions

`python -m ks_light.controller` runs a named action against the [hub API](HUB_API.md): submit once, poll until the operation finishes, print the result. Keyboard launchers, the Stream Deck plugin and the Raspberry Pi GPIO controller all use it, so none of them open their own Bluetooth connection.

## Configuration

Copy `examples/controller.example.json` (or `examples/controller-library.example.json` for groups and scenes) into a private directory:

```json
{
  "hub_url": "http://127.0.0.1:8765/api/v1",
  "token_file": "controller-token.txt",
  "timeout_seconds": 20,
  "actions": {
    "desk-on":  {"light": "desk", "type": "state", "body": {"power": true}},
    "reading":  {"light": "desk", "type": "state", "body": {"power": true, "rgb": [255, 190, 120], "brightness": 50}},
    "purple-breathing": {"light": "desk", "type": "native", "body": {"effect": 137, "speed": 35, "brightness": 50}}
  }
}
```

| Field | Rule |
| --- | --- |
| `hub_url` | Must end in `/api/v1`. Plain HTTP only for loopback; anything else must be HTTPS. |
| `token_file` | File containing the operator token or a [scoped credential](HUB_API.md#scoped-credentials). Relative to the configuration file. Restrict its permissions. |
| `ca_file` | Optional private CA for HTTPS. |
| `timeout_seconds` | 1 to 120, default 20. |
| `actions` | Names of 1 to 64 letters, digits, `_` or `-`. Each action has exactly one of `light`, `group` or `scene`, a `type` and a `body`. |

`type` is `state` or `native` for lights and groups, with the same bodies as the [HTTP API](HUB_API.md#commands). Scenes use `"type": "apply"` and `"body": {}`. Light, group and scene IDs must match the hub. Static colors get the hub's per-light calibration; phone calibration is not used.

Certificate validation is always on, redirects are refused and proxy environment variables are ignored.

## Run

```sh
python -m ks_light.controller --config controller.json                       # list action names (no hub contact)
python -m ks_light.controller --config controller.json reading               # run one action
python -m ks_light.controller --config controller.json reading --brightness 55
```

`--brightness` (1 to 100) overrides the level for this run only. It works on color actions that have `power: true` and `rgb`, and on native-effect actions, including group actions. Power-only and scene actions reject it.

The result is printed as JSON (`operation_id`, `status`, `confirmation`, `error`, and `members` for groups and scenes).

| Exit code | Meaning |
| --- | --- |
| 0 | Operation succeeded, or actions listed |
| 1 | Hub reported failure or cancellation (any member, for groups and scenes) |
| 2 | Invalid setup, rejected request, timeout, or connection error |

A timeout or lost connection does not prove the lamp was unchanged. Nothing is retried automatically. `confirmation: simulated` marks simulator results; `unconfirmed` means the write completed without readback.

Do not build toggles as read-then-write across several controllers; use explicit On and Off actions.

## Windows launchers

```powershell
./deploy/create-controller-shortcuts.ps1 -Config C:\path\to\controller.json -OutputDirectory C:\path\to\shortcuts
```

Creates one `.lnk` per action, with the checkout as working directory. It validates the configuration first, never runs actions, and does not overwrite existing links. The repository `.venv` must exist. Recreate the launchers if the checkout or configuration moves.

Assign a launcher in keyboard or macro-pad software as a "run program" or "open file" action, or in Stream Deck with **System > Open**. Launchers give no feedback on success or failure; run the CLI in a terminal to see the result. For Stream Deck, the native [plugin](STREAM_DECK.md) is the better option. No global hotkeys are registered by this project.
