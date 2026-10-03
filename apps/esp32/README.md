# ESP32 button controller (experimental)

> **Experimental.** Covered by portable host tests, a firmware/API contract test and compile checks only. Wiring, Wi-Fi, TLS, USB setup and live lamp behavior have not been verified on a board. See [HARDWARE_TESTING.md](../../docs/HARDWARE_TESTING.md).

Arduino-framework firmware for a **classic ESP32 DevKit** (`esp32dev`). Four buttons request On, Off, a reading color and Purple breathing for one light through the KS Light [hub](../../docs/HUB_API.md) over HTTPS. The hub owns Bluetooth. Not for Arduino Uno, ESP8266, ESP32-C3 or ESP32-S3.

Optional: a rotary encoder (action selector or dimmer) and three status LEDs.

## Build environments

Install PlatformIO Core 6.1.18 (`python -m pip install platformio==6.1.18`). Platform and library versions are pinned in `platformio.ini`. From this folder, `pio run` builds all environments:

| Environment | Purpose |
| --- | --- |
| `esp32dev` | Default firmware. Dry-run with Wi-Fi disabled unless your local config enables network mode. |
| `esp32-network-check` | Compile check of network mode, LEDs and rotary selector with placeholder credentials. Do not upload. |
| `esp32-dimmer-check` | Same, with the rotary dimmer. Do not upload. |

## Wiring and first test

1. With power disconnected, wire normally open buttons from GPIO **18, 19, 21, 22** to GND (On, Off, reading, Purple breathing). Internal pull-ups are enabled. These are GPIO numbers, not header positions; check your board.
2. Upload to an explicitly chosen port: `pio run -e esp32dev -t upload --upload-port YOUR_PORT`. This replaces the board's firmware.
3. `pio device monitor --port YOUR_PORT --baud 115200`. Each press should print one dry-run action. A button held at boot should do nothing until released and pressed again.

Never connect inputs to 5 V or mains.

## Enable hub control

Copy `include/config.example.h` to `include/ks_config.h` (ignored by Git) and set:

| Setting | Value |
| --- | --- |
| `WIFI_SSID`, `WIFI_PASSWORD` | Wi-Fi network |
| `HUB_ORIGIN` | `https://host[:port]` with no path; the firmware adds `/api/v1`. Must match the hub certificate. |
| `HUB_TOKEN` | A [scoped control credential](../../docs/HUB_API.md#scoped-credentials) for this light (at least 32 characters) |
| `HUB_CA` | PEM of the CA that signed the hub certificate |
| `LIGHT_ID` | Hub light ID |
| `NTP_HOST` | Time server (TLS needs a correct clock) |
| `KS_DRY_RUN` | Keep `1` until wiring is verified, then `0` |

The hub must be reachable over HTTPS: the [service TLS listener](../../docs/SERVICE_DEPLOYMENT.md#https-listener) or a trusted reverse proxy that preserves `Content-Length`. Plain remote HTTP and disabled certificate checks are not supported. Redirects are refused. Responses must have a `Content-Length` of 1 to 2048 bytes; chunked responses are rejected.

Default action bodies are in `src/main.cpp`; change the reading color or effect there and rebuild.

Credentials compiled into firmware can be read from the flash. Keep `ks_config.h`, build directories and configured binaries private. Serial output never prints the token or response bodies.

## Behavior

- Inputs are polled every 1 ms with a 50 ms stable debounce on press and release. Held buttons do not repeat.
- The controller waits for Wi-Fi and a valid clock before accepting actions.
- A separate worker performs HTTP so input sampling continues. One action at a time; busy and offline presses are discarded, not queued.
- Each action is submitted once with a random idempotency key, then the operation is polled. Polling budget: 20 seconds, with 3-second connect, TLS and read timeouts. These are not a hard deadline; DNS and an in-flight request can take longer.
- A timeout or lost response reports delivery unknown and is never retried. Wi-Fi reconnects automatically, but commands are never replayed.
- Serial labels distinguish dry-run, simulated, unconfirmed success, failure and unknown delivery. None of them is lamp readback.

## Rotary encoder (optional)

Set `KS_ROTARY_A`, `KS_ROTARY_B` and `KS_ROTARY_PRESS` to unused GPIOs (suggested 32, 33, 27), all three or none. Wire the encoder common and switch return to GND. Use a full-cycle mechanical encoder with A and B both high at each detent; half-step encoders are not supported. Swap A and B to reverse direction.

- **Selector** (default): turning previews one of the four actions on serial; pressing runs it. Turning alone sends nothing. Motion during a request is discarded. Fast turns can lose steps because input is polled.
- **Dimmer**: set `KS_ROTARY_DIMMER 1` and `KS_ROTARY_DIM_ACTION` to `2` (reading color) or `3` (Purple breathing). The level starts at 50%, moves in 5% steps within 1 to 100%, and only the latest level is sent after a 200 ms window. After a failure or offline send, dimming pauses until the encoder is pressed. A regular button cancels pending dimming so an old turn cannot undo Off.

## Status LEDs (optional)

Set `KS_LED_SENDING`, `KS_LED_COMPLETED` and `KS_LED_ERROR` (default `-1`, disabled; suggested 23, 25, 26). Wire each through its own current-limiting resistor to the LED anode, cathode to GND, sized for 3.3 V GPIO. Active-low and addressable LEDs are not supported.

| LED | Meaning |
| --- | --- |
| Sending | On while a command is in flight |
| Completed | Two seconds after simulated or unconfirmed success, or a dry-run press |
| Error | Two seconds after failure, unknown delivery or an offline press |

Allowed pins for buttons, LEDs and encoder: 18, 19, 21, 22, 23, 25, 26, 27, 32, 33, with no duplicates. This avoids flash, serial, strapping and input-only pins ([Espressif GPIO reference](https://docs.espressif.com/projects/esp-idf/en/v4.4.2/esp32/api-reference/peripherals/gpio.html)). Invalid assignments disable all controls before any output is configured.

## USB runtime configuration

Connection settings can be changed over USB without recompiling, once firmware is flashed:

1. Copy `connection.example.json` to `connection.private.json` (ignored) and fill in all seven fields (`wifi_ssid`, `wifi_password`, `hub_origin`, `hub_token`, `light_id`, `hub_ca`, `ntp_host`).
2. Close the serial monitor. From the repository root, with `requirements-controllers.lock` installed:

```sh
python -m ks_light.esp32_setup --port YOUR_PORT --config apps/esp32/connection.private.json
python -m ks_light.esp32_setup --port YOUR_PORT --status
python -m ks_light.esp32_setup --port YOUR_PORT --forget
```

The helper never picks a port or flashes firmware, and never echoes credentials. The board validates one bounded JSON request, stores it in NVS and reboots. Setup is refused while a command is running. "Saved" only means the settings were stored, not that Wi-Fi, TLS or the hub work. Pins and modes remain compile-time choices; a dry-run build stays dry-run.

`--forget` disables the stored connection without falling back to compiled credentials. It does not revoke the hub token; revoke it on the hub. NVS is not protected against flash extraction.

## Host tests

From the repository root, with a C++17 compiler:

```sh
g++ -std=c++17 -Wall -Wextra -Werror apps/esp32/test/native/core_test.cpp -o /tmp/ks-esp32-test && /tmp/ks-esp32-test
```

On Windows: `cl /std:c++17 /EHsc apps\esp32\test\native\core_test.cpp` in a developer shell. The tests cover debounce, startup hold, timer wrap, outcome handling, operation ID checks, single submission on timeout, pin conflicts, LED timing, rotary decoding and dimming. They do not exercise the real Wi-Fi or TLS stack. CI runs them and compiles the firmware.
