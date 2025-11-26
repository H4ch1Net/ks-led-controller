<div align="center">

# 💡 KS Smart LED Controller

**Open-source Bluetooth controller for KS LED lights**

[![Python](https://img.shields.io/badge/Python-3.7+-blue.svg)](https://www.python.org/downloads/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)](https://github.com/hbldh/bleak)

*A cross-platform alternative to the discontinued KeepSmile and problematic KS Smart Light apps*

[Features](#-features) • [Installation](#-installation) • [Usage](#-usage) • [Supported Devices](#-supported-devices) • [Documentation](#-documentation)

</div>

---

## 📖 About

This project was born out of necessity. The **KeepSmile app was removed from the Google Play Store**, and the **KS Smart Light app has numerous bugs and security concerns**. Rather than dealing with unreliable or unavailable software, this open-source controller provides a stable, privacy-respecting alternative for controlling KS LED devices via Bluetooth Low Energy (BLE).

**All commands were reverse-engineered** from the official Android APK to ensure complete compatibility with KS devices.

### Why This Exists

- 🚫 **KeepSmile app**: Removed from Play Store, unavailable for new users
- ⚠️ **KS Smart Light app**: Known security issues, frequent crashes, poor UX
- 🔓 **Privacy**: No data collection, no internet connection required
- 🎯 **Reliability**: Works offline, no cloud dependency
- 🛠️ **Control**: Full access to all device features

---

## ✨ Features

<table>
<tr>
<td width="50%">

### 🎨 Interactive Menu
- Beautiful terminal UI with color previews
- 10+ built-in color presets
- Custom RGB color picker (16.7M colors)
- Real-time color preview in terminal
- Intuitive keyboard navigation

</td>
<td width="50%">

### ⚡ Smart Controls
- One-touch ON/OFF control
- Brightness adjustment (0-100%)
- Save unlimited custom presets
- Device nickname management
- Multi-device support

</td>
</tr>
<tr>
<td width="50%">

### 🔍 Auto-Discovery
- Automatic BLE device scanning
- Smart device filtering (KS only)
- Connection status feedback
- Quick device switching

</td>
<td width="50%">

### 🤖 Automation Ready
- Command-line interface for scripts
- Cron job compatible
- Shell integration friendly
- Perfect for home automation

</td>
</tr>
</table>

---

## 🚀 Installation

### Requirements

- **Python 3.7+**
- **Bluetooth adapter** with BLE support
- **Operating System**: Linux, macOS, or Windows 10/11

### Quick Install

```bash
# Clone the repository
git clone https://github.com/yourusername/ks-led-controller.git
cd ks-led-controller

# Install dependencies
pip install -r requirements.txt

# Run the interactive menu
python3 led_menu.py
```

### Manual Install

```bash
pip install bleak>=0.21.0
```

---

## 🎯 Usage

### Interactive Menu (Recommended)

```bash
python3 led_menu.py
```

**Features:**
- 🎨 Color presets (Warm White, Cool White, RGB colors)
- 🌈 Custom RGB color creator
- 💡 Brightness control (25%, 50%, 75%, 100%, custom)
- 💾 Preset management (add, delete, reset)
- 🏷️ Device nicknames
- 🔄 Easy device switching

### Command Line Interface

Perfect for automation and scripting:

```bash
# Turn on
python3 led_control.py on KS03~ --address BE:60:4D:00:58:37

# Turn off
python3 led_control.py off KS03~ --address BE:60:4D:00:58:37

# Auto-scan and control
python3 led_control.py on KS03~

# Control all KS03 devices
python3 led_control.py on --all-ks03

# Verbose mode (show BLE details)
python3 led_control.py on KS03~ -v
```

---

## 📱 Supported Devices

| Model | Service UUID | Write UUID | RGB Support | Notes |
|-------|-------------|------------|-------------|-------|
| **KS03~** | `AFD0` | `AFD1` | ✅ Full RGB + Brightness | Floor lamp variant* |
| **KS03-** | `FFF0` | `FFF3` | ✅ Full RGB | Ceiling light variant* |
| **KS04-** | `FFF0` | `FFF3` | ✅ Full RGB | Ceiling light* |
| **KS01-** | `AE00` | `AE01` | ✅ Full RGB | Ceiling light* |
| **KS02-** | `AE00` | `AE01` | ✅ Full RGB | Ceiling light* |

<sub>* Device type labels (floor/ceiling) were derived from the decompiled APK code and may not accurately reflect all product variants. Your specific device model may differ. The important distinction is the command format used, which is automatically detected by the prefix (KS03~ uses extended format with brightness, others use standard format).</sub>

### Important: Model Prefix Matters!

⚠️ **KS03~ (tilde) and KS03- (hyphen) are DIFFERENT models** with different protocols:

- **KS03~**: Extended format with brightness control (`5A0001RRGGBB00BB00A5`)
- **KS03-**: Standard format (`7E070503RRGGBB00EF`)

Make sure to use the correct prefix for your device!

---

## 📚 Documentation

### Command Formats

<details>
<summary><b>ON/OFF Commands</b></summary>

```
ON:  5BF001B5
OFF: 5B0F01B5
```
</details>

<details>
<summary><b>RGB Color Commands - Floor Lamps (KS03~)</b></summary>

**Format:** `5A0001RRGGBB00BB00A5`

- `5A00` - Start marker
- `01` - RGB mode (02 = white mode)
- `RRGGBB` - RGB color values (hex)
- `00` - Cold white placeholder
- `BB` - Brightness (00-FF)
- `00A5` - End marker

**Examples:**
```
Red (full brightness):    5A0001FF000000FF00A5
Blue (50% brightness):    5A00010000FF007F00A5
Green (full brightness):  5A000100FF0000FF00A5
```
</details>

<details>
<summary><b>RGB Color Commands - Ceiling Lights (KS03-, KS04-, etc.)</b></summary>

**Format:** `7E070503RRGGBB00EF`

**Examples:**
```
Red:    7E070503FF000000EF
Blue:   7E0705030000FF00EF
Green:  7E07050300FF0000EF
```
</details>

<details>
<summary><b>Brightness Control (Floor Lamps Only)</b></summary>

**Format:** `5A000200000000BB00A5`

- `5A00` - Start marker
- `02` - White mode
- `000000` - RGB placeholder
- `BB` - Brightness (00-FF)
- `00A5` - End marker

**Examples:**
```
25% brightness:   5A0002000000004000A5
50% brightness:   5A0002000000008000A5
100% brightness:  5A00020000000FF00A5
```
</details>

### Automation Examples

<details>
<summary><b>Cron Jobs (Scheduled Control)</b></summary>

```bash
# Add to crontab (crontab -e)

# Turn on at 7:00 AM
0 7 * * * python3 /path/to/led_control.py on KS03~ --address XX:XX:XX:XX:XX:XX

# Turn off at 11:00 PM
0 23 * * * python3 /path/to/led_control.py off KS03~ --address XX:XX:XX:XX:XX:XX

# Set warm white at sunset (6 PM)
0 18 * * * python3 /path/to/led_control.py on KS03~ --address XX:XX:XX:XX:XX:XX
```
</details>

<details>
<summary><b>Shell Script Wrapper</b></summary>

```bash
#!/bin/bash
# led.sh - Simple wrapper script

DEVICE="KS03~"
ADDRESS="BE:60:4D:00:58:37"

case "$1" in
  on)
    python3 led_control.py on "$DEVICE" --address "$ADDRESS"
    ;;
  off)
    python3 led_control.py off "$DEVICE" --address "$ADDRESS"
    ;;
  *)
    echo "Usage: $0 {on|off}"
    exit 1
    ;;
esac
```

Usage: `./led.sh on` or `./led.sh off`
</details>

<details>
<summary><b>Home Automation Integration</b></summary>

**Home Assistant:**
```yaml
# configuration.yaml
shell_command:
  living_room_light_on: "python3 /path/to/led_control.py on KS03~ --address XX:XX:XX:XX:XX:XX"
  living_room_light_off: "python3 /path/to/led_control.py off KS03~ --address XX:XX:XX:XX:XX:XX"
```

**Node-RED:**
Use the `exec` node to call `led_control.py` with parameters.
</details>

---

## 🛠️ Troubleshooting

### LEDs Don't Respond

- ✅ Verify correct model prefix (KS03~ vs KS03-)
- ✅ Check Bluetooth is enabled
- ✅ Ensure device is powered on
- ✅ Move closer to the device (BLE range ~10m)
- ✅ Disconnect from other apps first

### Connection Errors

```bash
# Linux: Restart Bluetooth service
sudo systemctl restart bluetooth

# All platforms: Try verbose mode
python3 led_control.py on KS03~ -v
```

### Permission Denied (Linux)

```bash
# Add user to bluetooth group
sudo usermod -a -G bluetooth $USER

# Log out and back in for changes to take effect
```

### Multiple Devices

The interactive menu auto-detects all KS devices. Select the one you want to control from the list.

---

## 🤝 Contributing

Contributions are welcome! Whether it's:

- 🐛 Bug reports
- 💡 Feature suggestions
- 📝 Documentation improvements
- 🔧 Code contributions
- 🆕 Support for new device models

Please open an issue or pull request on GitHub.

---

## ⚠️ Disclaimer

This project is:
- **Not affiliated** with KeepSmile, KS Smart Light, or any official manufacturer
- **Reverse-engineered** from publicly available Android APK
- **For educational and personal use**
- **Provided as-is** without warranty

Use at your own risk. Always ensure you have the legal right to control devices you're connecting to.

---

## 📄 License

This project is released under the MIT License. See [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- **Bleak** - Excellent cross-platform BLE library
- **KS Light Users** - For documenting issues with official apps
- **Open Source Community** - For making projects like this possible

---

<div align="center">

**Made with ❤️ for frustrated KS LED owners everywhere**

If this project helped you, consider giving it a ⭐ on GitHub!

</div>
