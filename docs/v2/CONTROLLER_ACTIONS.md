# Controller actions: keyboard and Stream Deck launchers

## Implemented
`python -m ks_light.controller` runs a named action through the existing authenticated hub API. Actions cover explicit power, static RGB/brightness, KS03 native effects, groups and saved hub scenes. It submits once, polls for actual operation completion, and returns a nonzero exit code for failed delivery. No new Bluetooth commands or direct BLE connections are introduced.

The shared CLI supports Windows launchers, the native Stream Deck plugin and Raspberry Pi GPIO controllers. See STREAM_DECK.md for keys, shared setup and preview/press dials. No global hotkeys are registered automatically. Physical controller testing is deferred until hardware is available.

## Configure
1. Start a configured hub using SERVICE_DEPLOYMENT.md; simulation is suitable for setup. Match the light IDs to its catalog.
2. Copy `examples/controller.example.json` into a private directory, such as `.hub-local/controller.json`.
3. Point `token_file` at the hub operator token file. Relative paths resolve beside the configuration file. Tokens are not passed as command arguments or embedded in launchers. Restrict access to this file with OS permissions; OS credential-vault integration is still planned.
4. Use loopback HTTP for a hub on this PC. Remote hubs require HTTPS with a trusted certificate. An optional `ca_file` selects a private CA. Redirects are rejected, certificate validation stays enabled, and proxy environment variables are not used.
5. Choose a `timeout_seconds` value from 1 to 120 (default 20). Action names and light IDs use letters, digits, underscore or hyphen, up to 64 characters.

From the checkout:
```powershell
.venv/Scripts/python.exe -m ks_light.controller --config .hub-local/controller.json
.venv/Scripts/python.exe -m ks_light.controller --config .hub-local/controller.json reading
```
The first command lists action names without contacting the hub. The second executes one action. Example names are `desk-on`, `desk-off`, `reading`, and `purple-breathing`. Replace example RGB/brightness with your preferences; these examples do not import Android calibration; the hub applies its own configured per-light RGB gains.

Exit codes: 0 = successful operation (or listing), 1 = hub delivery failed/cancelled, 2 = invalid setup, rejected request, timeout or connection/response error. A timeout does not prove the lamp was unchanged. No automatic replay occurs. `confirmation: simulated` identifies simulator results; `unconfirmed` means transport completion without physical readback.

## Windows launchers
```powershell
./deploy/create-controller-shortcuts.ps1 -Config .hub-local/controller.json -OutputDirectory .hub-local/shortcuts
```
The generator validates configuration and creates one `.lnk` per named action, with the checkout as working directory. It does not execute actions or overwrite existing links. The Python virtual environment must already exist. Recreate launchers if the checkout/configuration moves. Existing keyboard bindings and desktop files are untouched.

In a keyboard's macro utility, assign a launcher as a program/file action where supported. In Stream Deck, use **System > Open** with the desired launcher file. Elgato documents this action as opening an application or file: [System actions](https://help.elgato.com/hc/en-us/articles/360028234471-Elgato-Stream-Deck-System-Actions-Hotkey-Open-Website-Multimedia). Vendor support varies; actual Stream Deck/keyboard launch acceptance is pending. These basic launchers do not display delivery feedback on the key. Run the CLI in a terminal to see the JSON result or error.

## Validation and deferred acceptance
Seven focused tests pass: successful simulated delivery, native effects, failed write without retry, auth/invalid payload rejection, deadline without resubmission, config/remote HTTP rules, and real CLI subprocess exit codes/listing/credential omission. The broader Python suite passed 95 tests before the final subprocess test was added; the focused seven then passed. Windows generated all four example links with valid targets/working directories and no secret argument. No physical lamp commands or phone actions occurred.

Later hardware checks: run each assigned button against the real hub, confirm physical lamp response and offline feedback, and check repeated presses. Continuous relative dimming and scoped credentials remain planned; the native plugin, preview/press rotary controls, group/scene actions and GPIO/ESP32 adapters are implemented. Do not use read-then-toggle as an atomic toggle across multiple controllers.

Follow-up (2026-09-23): a native Stream Deck key-action plugin now wraps this client with settings and delivery feedback; see STREAM_DECK.md. The basic launchers remain usable for keyboards.

Raspberry Pi follow-up (2026-09-26): a GPIO momentary-button adapter now shares this action client; see RASPBERRY_PI_BUTTONS.md. Button inputs are debounced, held startup is inert, and busy/uncertain commands are never queued or replayed. ESP32 buttons and rotary action selection are also implemented; see ESP32_CONTROLLER.md.

Brightness override (2026-09-26): append `--brightness 55` when executing a named color/native-effect action. Values must be integer 1..100. State actions must already contain power=true and RGB; power-only actions are rejected instead of guessing a color. The override copies the payload for this execution and does not change the configuration file. Stream Deck brightness dials use this path.

Group/scene actions: see HUB_LIBRARY.md and examples/controller-library.example.json. Choose exactly one `light`, `group` or `scene` target. Groups accept state/native bodies; scenes require type `apply` and body `{}`. The CLI prints per-member delivery results and exits 1 if any member fails or is cancelled. Group color/effect actions accept brightness overrides; saved scenes reject them to preserve their per-light settings.
