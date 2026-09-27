# Controller commands

Run from the repository with its virtual environment active.

```text
python led_control.py list --json
python led_control.py scan --json
python led_control.py on KS03~ --address YOUR_DEVICE_ADDRESS
python led_control.py rgb KS03~ --address YOUR_DEVICE_ADDRESS --rgb 255 120 30 --brightness 128
python led_control.py brightness KS03~ --address YOUR_DEVICE_ADDRESS --brightness 64
```

list prints inherited protocol profiles without accessing Bluetooth.
scan discovers known KS prefixes and supports JSON output.
rgb and brightness turn the light on, matching the menu's explicit color action.
--brightness is currently a byte from 0 to 255 (the future hub API uses percent).
--json supports scan/list/rgb/brightness, not legacy on/off.
--all-ks03 remains on/off only.

## Remembered settings
The CLI and menu share ~/.ks_led_state.json. Override it in the CLI with --state-file PATH.
Settings are saved only after a successful transport write, with confirmation set to unconfirmed.
The inherited KS03~ profile preserves the remembered RGB when dimming; choosing another RGB retains the remembered brightness unless overridden.
There is no device readback. Changes from another app or power-cycle behavior may differ from this saved state.
Set an RGB color first when no state is available. Standard RGB profiles do not support independent brightness in the inherited packet, so non-full brightness is rejected.
The brightness menu now dims remembered RGB instead of implicitly switching to white. The inherited white packet encoder remains available to future explicit white-mode controls.

## Presets and errors
The existing preset format is retained: a JSON object mapping names to r/g/b objects, each channel an integer from 0 to 255.
Custom presets refresh immediately in the menu.
Malformed preset/state files are reported and never automatically overwritten. Repair or rename a malformed file before saving new settings.
Successful BLE delivery with failed persistence is reported as such, not as a saved setting.
Files use atomic replacement to avoid partial JSON. This does not provide cross-process locking; run one state-writing controller at a time until hub ownership is implemented.

## Validation
40 automated tests pass on the existing Windows/Python 3.10.11/Bleak 3.0.2 environment.
No light was physically controlled during this work. Commands above are examples for an explicit hardware test session.
