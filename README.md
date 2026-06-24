<div align="center">

# KS Smart LED Controller

**Open-source Bluetooth controller for KS LED lights**

[![Python](https://img.shields.io/badge/Python-3.7+-blue.svg)](https://www.python.org/downloads/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)](https://github.com/hbldh/bleak)

A cross-platform alternative to the discontinued KeepSmile and unreliable KS Smart Light apps.

</div>

---

## About

The KeepSmile app was removed from the Google Play Store, and the KS Smart Light app has too many bugs and privacy concerns to be reliable. This project gives you a stable, offline alternative for controlling KS LED devices over Bluetooth Low Energy.

All commands were reverse-engineered from the official Android APK.

**Why not just use the official app?**

- KeepSmile: Removed from Play Store, unavailable to new users
- KS Smart Light: Known security issues, frequent crashes, poor UX
- This tool: No internet required, no data collection, works fully offline

---

## Features

**Interactive menu (`led_menu.py`)**
- Color presets with terminal color previews
- Custom RGB color picker (16.7M colors)
- Brightness control for supported models
- Save and manage your own presets
- Assign nicknames to devices for easy identification
- Auto-scans and lists all nearby KS devices on startup

**Command line (`led_control.py`)**
- Simple on/off control via CLI
- Specify device by address or let it auto-scan
- Control all KS03 devices at once with `--all-ks03`
- Verbose mode for debugging BLE connections
- Cron job and shell script friendly

---

## Installation

**Requirements**
- Python 3.7+
- Bluetooth adapter with BLE support
- Linux, macOS, or Windows 10/11

```bash
git clone https://github.com/h4ch1net/ks-led-controller.git
cd ks-led-controller
pip install -r requirements.txt
```

---

## Usage

### Interactive menu

```bash
python3 led_menu.py
```

Scans for nearby KS devices, lets you pick one, then presents a full control menu.

### Command line

```bash
# Turn on (with known address, skips scanning)
python3 led_control.py on KS03~ --address BE:60:4D:00:58:37

# Turn off (auto-scan)
python3 led_control.py off KS03~

# Control all KS03 devices found in range
python3 led_control.py on --all-ks03

# Verbose mode (shows BLE service and characteristic details)
python3 led_control.py on KS03~ -v
```

---

## Supported Devices

| Model | Service UUID | Write UUID | Brightness |
|-------|-------------|------------|------------|
| KS03~ | `AFD0` | `AFD1` | Yes |
| KS15~ | `AFD0` | `AFD3` | No |
| KS03- | `FFF0` | `FFF3` | No |
| KS04- | `FFF0` | `FFF3` | No |
| KS01- | `AE00` | `AE01` | No |
| KS02- | `AE00` | `AE01` | No |
| KS05- | `AE00` | `AE02` | No |
| KS04~ | `AE00` | `AE10` | No |
| KS07- through KS13- | `AE00` | `AE10` | No |

> **Note:** KS03~ (tilde) and KS03- (hyphen) are different models with different BLE protocols. Using the wrong prefix will result in no response. Check the label on your device carefully.

The interactive menu supports KS01-, KS02-, KS03-, KS03~, and KS04-. All models in the table above work with the CLI.

---

## Protocol Reference

<details>
<summary>ON/OFF commands</summary>

```
ON:  5BF001B5
OFF: 5B0F01B5
```
</details>

<details>
<summary>RGB color (floor lamps, KS03~)</summary>

Format: `5A0001RRGGBB00BB00A5`

- `5A00` - start marker
- `01` - RGB mode (`02` = white mode)
- `RRGGBB` - color in hex
- `00` - cold white placeholder
- `BB` - brightness (`00` to `FF`)
- `00A5` - end marker

Examples:
```
Red, full brightness:  5A0001FF000000FF00A5
Blue, 50% brightness:  5A00010000FF007F00A5
Green, full:           5A000100FF0000FF00A5
```
</details>

<details>
<summary>RGB color (ceiling lights, KS03-, KS04-, etc.)</summary>

Format: `7E070503RRGGBB00EF`

Examples:
```
Red:    7E070503FF000000EF
Green:  7E07050300FF0000EF
Blue:   7E0705030000FF00EF
```
</details>

<details>
<summary>Brightness control (KS03~ only)</summary>

Format: `5A000200000000BB00A5`

- `5A00` - start marker
- `02` - white mode
- `000000` - RGB placeholder
- `BB` - brightness (`00` to `FF`)
- `00A5` - end marker

Examples:
```
25%:   5A0002000000004000A5
50%:   5A0002000000008000A5
100%:  5A000200000000FF00A5
```
</details>

---

## Automation

**Cron job:**

```bash
# Turn on at 7 AM
0 7 * * * python3 /path/to/led_control.py on KS03~ --address XX:XX:XX:XX:XX:XX

# Turn off at 11 PM
0 23 * * * python3 /path/to/led_control.py off KS03~ --address XX:XX:XX:XX:XX:XX
```

**Shell wrapper:**

```bash
#!/bin/bash
DEVICE="KS03~"
ADDRESS="BE:60:4D:00:58:37"

case "$1" in
  on)  python3 /path/to/led_control.py on  "$DEVICE" --address "$ADDRESS" ;;
  off) python3 /path/to/led_control.py off "$DEVICE" --address "$ADDRESS" ;;
  *)   echo "Usage: $0 {on|off}"; exit 1 ;;
esac
```

**Home Assistant:**

```yaml
shell_command:
  living_room_on:  "python3 /path/to/led_control.py on  KS03~ --address XX:XX:XX:XX:XX:XX"
  living_room_off: "python3 /path/to/led_control.py off KS03~ --address XX:XX:XX:XX:XX:XX"
```

---

## Troubleshooting

**Device not responding**

- Double-check the model prefix (KS03~ vs KS03- are different protocols)
- Make sure Bluetooth is enabled and the light is powered on
- Move closer, BLE range is roughly 10 meters
- Disconnect from any other app that might be holding the connection

**Connection errors on Linux**

```bash
sudo systemctl restart bluetooth
```

**Permission denied on Linux**

```bash
sudo usermod -a -G bluetooth $USER
# Log out and back in for this to take effect
```

**Finding your device address**

Run `led_menu.py`. It scans for all nearby KS devices and lists them with addresses. Copy the address from there for use with the CLI.

---

## Contributing

Bug reports, feature requests, and pull requests are welcome. If you have a device model that is not listed or behaves differently than expected, open an issue with the model name and any BLE details you can capture (service UUID, characteristic UUID, raw command bytes).

---

## Disclaimer

This project is not affiliated with KeepSmile or any official manufacturer. The BLE protocol was reverse-engineered from the publicly available Android APK for personal and educational use. Provided as-is, without warranty.

---

## License

MIT. See [LICENSE](LICENSE) for details.
