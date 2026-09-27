# Raspberry Pi and ESP32: experimental status

Sanity review: 2026-09-27. Both adapters are **Experimental**. This label applies to the DIY controller adapters, not to every use of a Raspberry Pi as a hub host.

## What was checked

- Raspberry Pi configuration validation rejects duplicate/conflicting pins and unknown actions. Check/simulation modes avoid GPIO/network writes; dry-run can exercise real inputs without sending light commands.
- The GPIO runner debounces presses, ignores startup-held buttons, discards busy input and closes resources. Rotary dimming keeps a bounded latest value and pauses after uncertain delivery.
- ESP32 defaults to dry-run with placeholder credentials. The target is classic `esp32dev`, not Uno, ESP8266, C3 or S3. Pin assignments are checked before outputs are configured.
- Network mode uses a CA-verified HTTPS connection and does not enable insecure TLS. Offline/busy inputs are discarded; uncertain delivery is not replayed. USB setup validates bounded input and keeps credentials out of normal output.
- Shared design retains one Bluetooth owner: the hub. These adapters submit authenticated hub actions rather than opening competing BLE connections.

## Fresh evidence

The existing focused checks were run once, without adding a broad test campaign:

```sh
python -m unittest tests.test_gpio_controller tests.test_gpio_status tests.test_gpio_encoder tests.test_gpio_dimming tests.test_esp32_contract tests.test_esp32_setup
```

**24 checks passed.** They cover mocked GPIO behavior/cleanup, rotary/status logic, firmware action payload compatibility with the hub, and bounded USB setup/error handling. These are host-side checks, not physical board results.

All three ESP32 variants had previously compiled in the release-preparation work. Firmware source was unchanged in this documentation review, so no firmware rebuild or board flash was needed. A fresh portable C++ host build was not obtained because `g++` is unavailable in the current WSL environment; the earlier build evidence and hosted ESP32 workflow remain separate from today's 24 checks.

## Known limits

No Pi GPIO board or ESP32 was connected/flashed for this review. Pin backend availability, electrical wiring, resistor choices, switch/encoder bounce under load, real Wi-Fi/TLS/NTP behavior, USB/NVS reboot persistence and physical lamp output remain unverified. Timed network operations are bounded at the application level but are not a hard real-time deadline. Status LEDs report command processing, not measured light state.

No issue requiring a code patch was found in this bounded review. This is not a security audit or hardware certification. Use the documented dry-run path first and validate the exact board/wiring before enabling light commands.

- [Raspberry Pi guide](RASPBERRY_PI_BUTTONS.md)
- [ESP32 build/wiring guide](../../apps/esp32/README.md)
- [Full deferred hardware checklist](DEFERRED_HARDWARE_CHECKS.md)
