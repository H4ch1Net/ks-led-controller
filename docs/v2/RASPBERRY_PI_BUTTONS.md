# Raspberry Pi button controller — Experimental

> **Experimental DIY integration.** Host-side sanity checks pass, but physical wiring, board-specific behavior and live lamp delivery have not been verified. Treat this as a development example, not a hardware-tested product. [Evidence and limits](EXPERIMENTAL_HARDWARE.md).

Implemented 2026-09-26. Momentary GPIO buttons run named actions from the existing controller configuration. The hub owns Bluetooth; this adapter opens no BLE connections. Power, saved RGB/brightness actions and native effects use the same API as Stream Deck and keyboard actions.

## Setup

Use a Raspberry Pi running Linux and Python 3.10 or later. From the checkout, install the GPIO/controller lock with `pip install --require-hashes -r requirements-controllers.lock` in a virtual environment. GPIO Zero also needs a pin backend supported by your board and OS; follow its [installation guidance](https://gpiozero.readthedocs.io/en/stable/installing.html). The runtime user needs access to GPIO devices. Raspberry Pi OS normally provides GPIO packages; board/backend availability has not been verified on physical hardware in this project.

Copy `examples/controller.example.json` and `examples/gpio-buttons.example.json` to your private configuration directory. Configure the controller file and separate token as described in CONTROLLER_ACTIONS.md. Match action light IDs to your hub catalog. A local hub can use loopback HTTP; a remote hub requires trusted HTTPS. Restrict token-file access to the runtime user. No credentials are printed in normal status output.

The example maps BCM 17 to desk-on, 27 to desk-off, 22 to reading and 23 to purple-breathing. These are BCM GPIO identifiers, not physical header positions. Use normally open momentary buttons between each chosen GPIO and ground; internal pull-ups are enabled. Do not connect a GPIO to 5V or mains. Verify header positions for your board before wiring, with power disconnected. See the official [GPIO Zero Button wiring and API](https://gpiozero.readthedocs.io/en/stable/api_input.html#button).

From the repository root (use your actual configuration paths):

```sh
python -m ks_light.gpio_controller --config /path/controller.json --buttons /path/buttons.json --check
python -m ks_light.gpio_controller --config /path/controller.json --buttons /path/buttons.json --simulate 17 27 22 23
python -m ks_light.gpio_controller --config /path/controller.json --buttons /path/buttons.json --dry-run
python -m ks_light.gpio_controller --config /path/controller.json --buttons /path/buttons.json
```

`--check` validates files without GPIO or network access. `--simulate` exercises named mappings, requires no GPIO dependency and never contacts the hub; output says dry-run. `--dry-run` reads real buttons without sending commands. The last command enables real hub requests. Stop with Ctrl+C or SIGTERM. Configuration is loaded at startup; restart after edits.

## Behavior

Inputs are sampled every 10 ms and must remain stable for the configured debounce period (50 ms default, configurable 20..1000 ms). A button held during startup sends nothing until released and pressed again. Holding does not repeat. Release must also debounce before another press can be accepted. This debounce applies to human-operated press buttons. Rotary detents use GPIO Zero decoding as described below.

One request may be active at a time. Additional presses are discarded with a busy status, never saved for later. Each accepted action submits once and polls for completion using the existing controller timeout. A timeout or lost connection can mean delivery occurred; it is never automatically retried. Once the request finishes or times out, release and press again to try a new action. There is no network backlog to replay after reconnecting.

JSON output distinguishes succeeded/failed operations, simulated hub confirmation, dry-run, and errors. Successful BLE transport remains unconfirmed physical state. A stop request closes GPIO inputs, then lets an already-submitted operation finish within its configured timeout (up to 120 seconds). Stopping cannot undo an already-sent light command. No global hotkeys, services, or system permissions are installed automatically.

## Validation and remaining work

Seven focused tests cover bounce/hold/release, held startup, invalid/duplicate pin mappings, busy discard and failure recovery, partial setup cleanup, mocked GPIO through an authenticated simulator hub, and actual CLI subprocesses for check/simulation with credential omission. These tests run without Pi hardware or GPIO Zero. The full Python suite now passes 127 tests, including rotary, status-LED, ESP32 contract and hub persistence checks. Physical wiring, board-specific pin backend, timing/CPU load and live lamp acceptance remain open. Optional status LEDs are now implemented below. Rotary action selection is now implemented below; ESP32 firmware is documented separately in ESP32_CONTROLLER.md.


## Optional status LEDs

Use `examples/gpio-buttons-with-leds.example.json` for three optional outputs. The original buttons-only configuration still works. Each role can be omitted; pins must be distinct from all button pins and other LED pins.

```json
"status_leds": {"sending": 24, "completed": 25, "error": 26}
```

Wire each chosen GPIO through a current-limiting resistor to its LED anode, with its cathode to GND. Choose a resistor appropriate to the LED and the Pi's GPIO current limits; never connect a bare LED directly. Use power-off wiring and verify your board's BCM pin mapping. The implementation uses active-high outputs initialized off, following the [GPIO Zero LED interface](https://gpiozero.readthedocs.io/en/stable/api_output.html#led).

- **Sending** stays lit while the accepted operation is in flight. Discarded busy presses do not change it.
- **Completed** stays lit after successful completion until another action starts. This includes dry-run and simulator success; consult the JSON confirmation to distinguish them. It is never a physical lamp-state indicator.
- **Error** replaces the previous result for failed, cancelled or uncertain operations. A new action clears it while sending.

On startup all outputs are off. `--check` validates pins without opening GPIO. `--simulate` opens neither buttons nor LEDs. `--dry-run` uses the real buttons and LEDs, but sends no network commands. Normal shutdown stops button sampling, waits for an in-flight bounded operation and turns off/closes LEDs. A hardware/OS failure cannot guarantee an electrical output is off.

Partial initialization cleans up already-open outputs and prevents command startup. If an output fails later, indicator handling is disabled with one log warning; command processing and its no-retry behavior continue. Monitor JSON logs if that warning occurs.

Validation: five additional tests cover pin collisions and optional roles, sending/completed/error transitions, busy feedback, partial setup cleanup, indicator faults without delivery changes, and shutdown ordering. All 12 focused GPIO tests pass. Physical LEDs, resistor selection and Pi GPIO backend acceptance remain pending.


## Rotary action selection

`examples/gpio-encoder.example.json` maps a rotary encoder's A/B contacts to BCM 5/6 and its separate push switch to BCM 13. Up to four encoders can coexist with normal buttons and status LEDs. All pins must be distinct. Each encoder lists 1..32 unique configured action names; encoder-only setups are supported.

Wire A and B to the selected GPIOs and common to GND; wire the separate push switch between its GPIO and GND. Follow your component pinout and the [GPIO Zero RotaryEncoder wiring/API](https://gpiozero.readthedocs.io/en/stable/api_input.html#rotaryencoder); do not feed 5V into GPIO. Swap A/B if direction is reversed. GPIO Zero decodes quadrature transitions while the runner samples accumulated detent counts; physical encoder bounce and maximum usable turn rate still need hardware testing.

Turn to select an action, press to run it. Selection starts at the first configured action on process startup, wraps in both directions, and is printed as a `selected` JSON event. No display hardware is provided. Turning never sends a light command. During an operation, rotation and additional presses are discarded; discarded rotation does not change selection afterward. A switch held at startup does not execute until released and pressed again. GPIO resources close on shutdown or partial initialization failure.

`--check` validates the encoder configuration without GPIO. `--dry-run` exercises the actual knob without network delivery. `--simulate 13` simulates its push switch using the first configured action; that mode does not simulate rotary movement. Unit tests exercise rotation independently.

Four additional encoder tests verify direction/wrap, discarded busy motion, pin collision checks, no-write preview followed by selected-action delivery, and cleanup after partial initialization. GPIO Zero mock-pin integration also verifies actual quadrature decoding and press dispatch. All 17 focused GPIO tests pass; physical acceptance remains pending.

## Continuous brightness

`examples/gpio-dimmer.example.json` uses `brightness_action` instead of an action list. Select a named explicit RGB/power-on or native-effect action. The knob starts at 50%, changes in 5-point steps and sends the latest level after a 200 ms coalescing window, even while turning continues. In-flight delivery is serialized; intermediate levels are replaced. A failure/cancellation clears pending levels and pauses automatic sending until a deliberate press. Rotation while paused only changes the preview. Shutdown discards unsent previews and waits only for already submitted work. This reapplies the named color/effect; it is not physical brightness readback. Hardware smoothness and direction remain unverified.
