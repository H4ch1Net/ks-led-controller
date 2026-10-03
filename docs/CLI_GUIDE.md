# Direct Bluetooth CLI and menu

`led_control.py` and `led_menu.py` control a light directly over Bluetooth from a computer, without the hub. Use them for quick tests. For anything shared with other controllers, use the [hub](HUB_API.md) so there is one Bluetooth owner per lamp.

## Install

Python 3.10 or newer. From the repository root:

```sh
python -m venv .venv
.venv/bin/python -m pip install --require-hashes -r requirements.lock   # .venv\Scripts\python.exe on Windows
```

## Commands

```sh
python led_control.py list [--json]
python led_control.py scan [--json] [--timeout 8]
python led_control.py on  KS03~ [--address ADDRESS]
python led_control.py off KS03~ [--address ADDRESS]
python led_control.py rgb KS03~ --address ADDRESS --rgb 255 120 30 [--brightness 128]
python led_control.py rgb KS03~ --hex ff8800
python led_control.py brightness KS03~ --address ADDRESS --brightness 64
python led_control.py effect KS03~ --name purple-breathing [--speed 35] [--brightness 128]
python led_control.py on KS03~ --all-ks03
```

| Option | Meaning |
| --- | --- |
| `model_prefix` | Profile prefix, default `KS03~`. `list` shows all known prefixes. |
| `--address` | Bluetooth address. When omitted, the CLI scans for the prefix. If more than one light matches, it lists the addresses and exits without writing. |
| `--rgb R G B` / `--hex RRGGBB` | Color, channels 0 to 255. Only with `rgb`. |
| `--name` | Built-in effect for `effect` (KS03~ only): `seven-color-fade`, `rgb-fade`, `red-breathing`, `green-breathing`, `blue-breathing`, `yellow-breathing`, `cyan-breathing`, `purple-breathing`, `white-breathing`. |
| `--speed` | Effect speed 0 to 100, default 35. |
| `--brightness` | Byte 0 to 255 (the hub API uses percent). Only KS03~ supports independent brightness; other RGB profiles accept only 255. For `effect` it is scaled to percent (default full). |
| `--all-ks03` | Send `on`/`off` to every KS03- and KS03~ light found. Exits 1 if any write failed. |
| `--json` | JSON output for `scan`, `list`, `rgb`, `brightness` and `effect`. |
| `--timeout` | Scan time in seconds (positive). |
| `--state-file` | Remembered state file, default `~/.ks_led_state.json`. |
| `-v` | Print target and payload. |

`list` reads the profile registry without touching Bluetooth. `rgb` and `brightness` send power-on followed by the color packet. `brightness` reuses the remembered color, so set a color first. `effect` sends power-on plus the effect packet; the lamp keeps animating after the CLI exits. Effects are not stored in the state file.

## Interactive menu

```sh
python led_menu.py
```

The menu scans, lets you pick a light, and offers power, preset and custom colors, and brightness for KS03~. It stores nicknames in `~/.ks_led_devices.json` and custom presets in `~/.ks_led_presets.json` (a JSON object of name to `{"r","g","b"}`, each 0 to 255).

## Remembered state

The CLI and menu share `~/.ks_led_state.json`. A light's RGB and brightness are saved only after a successful write. There is no device readback, so the file can disagree with the lamp after another controller or a power cycle changes it.

Files are written atomically. Malformed state or preset files are reported and never overwritten; fix or rename them first. There is no cross-process locking, so run one writer at a time. If a write succeeds but saving fails, the CLI reports that separately.
