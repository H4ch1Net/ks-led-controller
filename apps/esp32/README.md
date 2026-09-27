# ESP32 four-button controller — Experimental

> **Experimental DIY integration.** Host-side sanity checks pass, but physical wiring, board-specific behavior and live lamp delivery have not been verified. Treat this as a development example, not a hardware-tested product. [Evidence and limits](../../docs/v2/EXPERIMENTAL_HARDWARE.md).

Arduino-framework firmware for a **classic ESP32 DevKit** (`esp32dev`). Four normally-open buttons request On, Off, reading color and Purple breathing through the KS Light hub. The hub remains the Bluetooth owner. This is not firmware for an Arduino Uno, ESP8266, ESP32-C3 or ESP32-S3.

## Build and wiring

1. Install Python and PlatformIO Core 6.1.18: `python -m pip install platformio==6.1.18`.
2. From this folder run `pio run` to compile the dry-run, network-selector and network-dimmer variants. Use `esp32dev` for dry-run. The network-check variant links the network code but placeholder credentials disable controls. The platform and JSON library versions are pinned in `platformio.ini`. Without a local configuration the example builds in **dry-run**, with Wi-Fi disabled.
3. With power disconnected, wire normally-open buttons from GPIO **18, 19, 21 and 22** respectively to GND. Internal pull-ups are enabled. Check your specific board's labels; these are GPIO numbers, not header positions. Do not connect switches to mains or 5V.
4. When the intended board is connected, explicitly select its serial port: `pio run -e esp32dev -t upload --upload-port YOUR_PORT`. Uploading replaces its existing firmware. No device has been flashed as part of development.
5. Use `pio device monitor --port YOUR_PORT --baud 115200`. Each press should print one dry-run action. Holding a button at boot should print nothing until it is released and pressed again.

## Enable hub control

Copy `include/config.example.h` to `include/ks_config.h` (ignored by Git). Set the Wi-Fi credentials, hub HTTPS origin, bearer token, trusted PEM CA, and saved hub light ID. The origin contains a hostname and optional port only, such as `https://hub.example.test:8443`; the firmware adds `/api/v1`. It must match the TLS certificate. Use the configured hub service's TLS listener (see SERVICE_DEPLOYMENT.md), or a trusted HTTPS reverse proxy; direct remote HTTP and disabling certificate verification are not supported.

Keep `DRY_RUN = true` until button wiring is verified. Then set `constexpr bool DRY_RUN = false;` in your local header, rebuild and upload. A synchronized clock is needed for TLS verification; `NTP_HOST` can point to your local time server. The controller waits for Wi-Fi and a clock before accepting actions. TLS verifies the configured CA and hostname. Redirects are rejected. Proxy responses must have a Content-Length of 1..2048 bytes; chunked responses are deliberately rejected. Native hub JSON responses have Content-Length, but confirm your reverse proxy preserves it.

The hub token must contain at least 32 non-whitespace ASCII characters, matching the hub requirement. Credentials are compiled into firmware: keep config, build caches and configured firmware images private. Use a scoped control credential limited to this light (see HUB_API.md). USB runtime setup is available below; secure boot and encrypted flash provisioning remain separate deployment work. Serial output includes action/result labels, never token or HTTP response bodies.

## Behavior and feedback

Inputs are polled with a 1 ms loop delay with a 50 ms stable press/release debounce. Startup-held buttons and continued holds never repeat. A separate worker performs HTTP so input sampling continues during requests. Only one action can be in flight; busy and offline presses are discarded, not queued for reconnect. Wi-Fi reconnects automatically, but commands are never automatically replayed. After an error, release and press again for a new action.

Each accepted action submits once with a random idempotency key, then polls that operation. The polling budget is 20 seconds with separate 3-second connection, TLS handshake and read timeouts. These are not a strict wall-clock deadline: an in-flight request and network-stack DNS work can exceed the polling budget. A lost response or timeout reports delivery unknown and never retries. Failure/cancellation, simulator success and unconfirmed transport success have distinct serial labels. No label proves the physical lamp state.

Default action payloads live in `src/main.cpp`; change the reading color or native effect there and rebuild. They do not import Android calibration; the hub applies its configured per-light RGB gains to static color commands. The controller uses one light ID and four actions. USB runtime connection setup and optional continuous rotary dimming are implemented; OTA updating is not.

## Optional rotary action selector

Set `KS_ROTARY_A`, `KS_ROTARY_B` and `KS_ROTARY_PRESS` in the local configuration to unused GPIOs (suggested 32, 33 and 27). Enable all three together, or leave all at `-1`. Contacts use internal pull-ups: wire the encoder common and press switch return to GND. Use a full-cycle mechanical encoder with both A and B HIGH at each detent. Swap A/B if the direction feels reversed. Half-step encoders and boards with different pin assignments need separate support/testing.

Turning previews one of the four action names on serial; pressing executes that selection through the same command gate as the buttons. Turning alone sends nothing. Motion during a request is consumed and discarded, including a partial turn spanning completion. Startup-held presses remain inert. The decoder rejects invalid two-contact jumps and cancels reversible contact bounce. This is polled input; fast turns or scheduling stalls may lose movement, so physical turn-rate acceptance remains open. The network-check build compiles with the suggested encoder and LED pins enabled. There is no display or selection persistence yet.

## Optional status LEDs

In `include/ks_config.h`, set `KS_LED_SENDING`, `KS_LED_COMPLETED` and `KS_LED_ERROR` to GPIO numbers; each defaults to `-1` (disabled). Existing local headers remain compatible. Suggested external outputs are 23, 25 and 26 respectively. With power disconnected, connect each output through its own current-limiting resistor to the LED anode, with its cathode to GND. Choose the resistor for your LED and the board's 3.3 V GPIO limits; this example does not support active-low or addressable LEDs.

The example accepts only GPIO 18, 19, 21, 22, 23, 25, 26, 27, 32 or 33, with no duplicate outputs or overlap with configured buttons. Check your particular board for other connected peripherals. Invalid assignments disable controls before configuring outputs. The conservative list avoids flash, serial, strapping and input-only connections described in the [Espressif GPIO reference](https://docs.espressif.com/projects/esp-idf/en/v4.4.2/esp32/api-reference/peripherals/gpio.html).

- Sending stays on while an accepted command is in flight.
- Completed lights for two seconds after simulated or unconfirmed command completion. Dry-run presses also show Completed without connecting to Wi-Fi.
- Error lights for two seconds on failure, unknown delivery or an offline press. Busy presses do not replace Sending.

All LEDs start off. Completion is **not physical lamp readback**; serial output distinguishes dry-run, simulator, unconfirmed delivery and errors. Only the main loop writes LEDs. The worker returns its result through a bounded queue before another command is accepted. The network-check build enables the suggested outputs for compilation coverage; do not upload that environment as a substitute for your configured firmware.

## Repeatable checks

On a host with a C++17 compiler, from the repository root:

```sh
g++ -std=c++17 -Wall -Wextra -Werror apps/esp32/test/native/core_test.cpp -o /tmp/ks-esp32-test
/tmp/ks-esp32-test
```

Windows can use a Visual Studio developer shell and `cl /std:c++17 /EHsc apps\esp32\test\native\core_test.cpp` instead. The CI workflow runs the host checks and cross-compiles the default firmware. Host checks cover indicator timing, pin conflicts, busy rejection, debounce, startup hold, 32-bit timer wrap, terminal outcomes, invalid/mismatched operation IDs, errors and one submission despite timeout. These checks do not execute the real ESP32 Wi-Fi/TLS stack or validate wiring. Physical board, TLS handshake, reconnection, busy presses and live lamp acceptance remain pending.

API references: [Espressif HTTPClient](https://github.com/espressif/arduino-esp32/blob/2.0.17/libraries/HTTPClient/src/HTTPClient.h), [WiFiClientSecure](https://github.com/espressif/arduino-esp32/blob/2.0.17/libraries/WiFiClientSecure/src/WiFiClientSecure.h).

## Continuous rotary dimming

Set `KS_ROTARY_DIMMER=1` with all three encoder pins enabled. `KS_ROTARY_DIM_ACTION=2` dims the reading color; `3` dims Purple breathing. Brightness starts at a 50% preview, moves in 5% steps and stays within 1..100%. This is a commanded level, not lamp readback. A first-turn 200 ms window combines rapid turns without postponing sending indefinitely. During a dim command, only the latest pending level is retained; returning to the level already sent avoids a duplicate request.

Uncertain/failed delivery or offline sending drops the pending value and pauses automatic dimming. Press the encoder to deliberately send the preview and resume. A regular button cancels pending dimming and pauses it so an old turn cannot undo Off. Motion during regular button commands is consumed. Restart discards pending input. The `esp32-dimmer-check` environment compiles this mode with placeholder credentials; it does not contact a hub.

## USB runtime configuration

After the firmware has been flashed, change connection settings without recompiling:

1. Copy `connection.example.json` to the ignored `connection.private.json` and fill all seven fields. Use a scoped hub control token for the chosen light and the trusted CA certificate as a JSON string. The example placeholders are intentionally invalid.
2. Close the serial monitor and identify the board's port yourself. The helper never chooses a port or flashes firmware.
3. From the repository root, install `python -m pip install --require-hashes -r requirements-controllers.lock`, or use the existing PlatformIO Python environment.
4. Run `python -m ks_light.esp32_setup --port YOUR_PORT --config apps/esp32/connection.private.json`.
5. Request status with `python -m ks_light.esp32_setup --port YOUR_PORT --status`. A saved response means settings were stored; it does not establish Wi-Fi, clock, TLS or lamp connectivity.

The board validates one bounded JSON request, stores one NVS record and reboots after saving. The physical pin/mode configuration remains a firmware choice. A dry-run build stays dry-run after setup; use the network build only once wiring is accepted. Setup requests are rejected while a light command is running. Serial requests and responses have limits; credentials and arbitrary serial output are never echoed by the helper. Unknown acknowledgment is never automatically retried.

`--forget` disables the stored connection and reboots. It does not fall back to compiled-in credentials and does not revoke the hub token; revoke that credential through the hub separately. A new valid USB setup can reconfigure the device. These settings use ordinary ESP32 NVS: they are not protected against physical flash extraction. Keep the private JSON and configured flash dumps out of shared artifacts. No web setup service is opened.

Development evidence: portable C++ dimming/core checks passed; the network-dimmer firmware cross-compiled after adding runtime setup. Three USB helper tests and the firmware/API contract check passed. Actual USB save/reboot/persistence/forget, TLS and rotary behavior remain hardware acceptance tasks.
