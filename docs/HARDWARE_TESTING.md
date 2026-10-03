# Hardware coverage and testing

Automated tests and the simulator check logic, not Bluetooth compatibility or physical output. This page lists what has been observed on real hardware, what is experimental, and a checklist for anyone testing new hardware.

## Observed on hardware

All observations are on a single KS03~ lamp with one Samsung Android 16 phone and one Windows PC Bluetooth adapter.

| Path | Observed |
| --- | --- |
| Android direct | Power, color, brightness, built-in Purple breathing, saved devices and default, widgets, Quick Settings, Device Controls |
| Hub over BLE (Windows) | Static color and Purple breathing |
| Home Assistant via MQTT | Static color end to end |
| Android hub mode (USB forwarding) | Static color |
| Stream Deck (15-key) | Power, Set Color, Effect, repeat delivery speed |

Not covered: other profiles (KS03-, KS04-, KS01-, KS02- and the power-only prefixes), more than one lamp at a time, built-in effects other than Purple breathing, Stream Deck+ dials, keyboard launchers, Linux or Raspberry Pi as hub host, wireless HTTPS to the hub, and long-duration reliability. Color accuracy is subjective; there is no measured colorimetry.

## Experimental DIY controllers

The [Raspberry Pi GPIO controller](RASPBERRY_PI_BUTTONS.md) and [ESP32 firmware](../apps/esp32/README.md) are experimental. They have host-side tests (mocked GPIO, portable C++ logic, firmware payloads against the simulated hub, USB setup parsing) and the ESP32 firmware compiles in CI. No board has been wired or flashed by the project. Unverified:

- GPIO pin backends, electrical wiring, resistor choices
- switch and encoder bounce, turn rate, timing under load
- ESP32 Wi-Fi, TLS, NTP, reconnects, USB setup and NVS persistence across reboot
- physical lamp output through either controller

Use the dry-run modes first and validate your exact board and wiring before enabling commands. These designs are not a security audit or a hardware certification.

## Test checklist

Record phone or host model, OS version, Bluetooth adapter, light name prefix, number of lights and firmware if known. Keep one Bluetooth owner per lamp during tests: pause the vendor app, other Home Assistant integrations and any other KS Light client.

### Android

- Permissions denied then granted; Bluetooth off and on; first scan; add, rescan and deduplicate lights.
- Power, primary colors, brightness, repeated slider use, light power cycle, app restart, screen off.
- Default light change, clear and restart; remove a light used by a room and a widget.
- Color balance applied once; preview and Cancel send nothing.
- Built-in effects other than Purple breathing; phone effects with restore.
- Rooms and scenes with one member offline; Stop after current light; backup export, import and device matching.
- Widgets: power, favorite and scene types; reconfigure or delete while a scene is sending.
- Quick Settings and Device Controls status after app restart; Connection help report contents.

### Multiple lights and hub

- Two or more real lights: group and scene partial failures, per-light results, mixed profiles.
- Service startup, restart and shutdown on Windows, Linux and Raspberry Pi; persisted state after a forced stop.
- Wireless Android connection over trusted HTTPS; scoped credentials and revocation.
- No replay after reconnect or restart.

### Stream Deck and keyboards

- Brightness and Scene keys; Run light action keys with group and scene targets.
- Fresh shared setup, connection changes, offline hub, repeated presses.
- Dials: preview and press, continuous dimming, failure pause and recovery, touch strip layout.
- Live status with changes made by another client.
- Keyboard launchers assigned in vendor macro software.

### Raspberry Pi and ESP32

- Dry-run wiring check, startup-held buttons, one action per press, busy and offline handling.
- Status LEDs with correct resistors and polarity.
- Encoder direction, detents, fast turns, motion while busy, dimmer pause and recovery.
- Pi shutdown and SIGTERM cleanup.
- ESP32 trusted HTTPS, Wi-Fi loss and recovery, USB setup, reboot persistence, `--forget`, oversized or partial serial input.

Do not change lamp state outside an agreed test session with the lamp's owner.
