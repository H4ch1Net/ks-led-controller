# Raspberry Pi GPIO controller (experimental)

> **Experimental.** Covered by host-side tests with mocked GPIO only. Wiring, pin backends, timing and live lamp behavior have not been verified on a Raspberry Pi. See [HARDWARE_TESTING.md](HARDWARE_TESTING.md).

`python -m ks_light.gpio_controller` maps momentary buttons, rotary encoders and status LEDs on GPIO to [named controller actions](CONTROLLER_ACTIONS.md). It sends requests to the hub; the hub owns Bluetooth. The hub can run on the same Pi ([SERVICE_DEPLOYMENT.md](SERVICE_DEPLOYMENT.md)) or elsewhere over trusted HTTPS.

## Setup

1. Raspberry Pi OS (or another Linux) with Python 3.10 or newer.
2. In a virtual environment: `pip install --require-hashes -r requirements-controllers.lock`. GPIO Zero needs a pin backend for your board; see its [installation guide](https://gpiozero.readthedocs.io/en/stable/installing.html). The runtime user needs GPIO access.
3. Copy `examples/controller.example.json` and one of the GPIO examples to a private directory. Configure the controller file and its token file, and match light IDs to the hub catalog.

| Example | Contents |
| --- | --- |
| `gpio-buttons.example.json` | Four buttons |
| `gpio-buttons-with-leds.example.json` | Four buttons and status LEDs |
| `gpio-encoder.example.json` | Rotary action selector and status LEDs |
| `gpio-dimmer.example.json` | Rotary brightness control |

## Run

```sh
python -m ks_light.gpio_controller --config controller.json --buttons gpio.json --check
python -m ks_light.gpio_controller --config controller.json --buttons gpio.json --simulate 17 27
python -m ks_light.gpio_controller --config controller.json --buttons gpio.json --dry-run
python -m ks_light.gpio_controller --config controller.json --buttons gpio.json
```

| Mode | GPIO | Hub |
| --- | --- | --- |
| `--check` | not opened | not contacted; validates files |
| `--simulate PIN...` | not opened | not contacted; simulates presses on the listed BCM pins |
| `--dry-run` | real inputs and LEDs | not contacted |
| (none) | real | real requests |

Output is JSON lines. Stop with Ctrl+C or SIGTERM. Configuration is read at startup only.

## Configuration

```json
{
  "debounce_ms": 50,
  "buttons": [{"pin": 17, "action": "desk-on"}, {"pin": 27, "action": "desk-off"}],
  "encoders": [{"a": 5, "b": 6, "press": 13, "actions": ["desk-on", "reading", "desk-off"]}],
  "status_leds": {"sending": 24, "completed": 25, "error": 26}
}
```

- Pins are BCM GPIO numbers, not header positions. All pins must be distinct.
- `debounce_ms`: 20 to 1000, default 50.
- `encoders`: up to four. Each has `a`, `b`, `press` and either `actions` (1 to 32 names) or `brightness_action` (one name).
- `status_leds`: each role is optional.

## Wiring

Disconnect power while wiring and check your board's pinout.

- **Buttons**: normally open momentary switch between the GPIO and GND. Internal pull-ups are enabled.
- **Encoders**: A and B to their GPIOs, common to GND; the push switch between its GPIO and GND. Swap A and B if direction is reversed.
- **LEDs**: GPIO, current-limiting resistor, LED anode; cathode to GND. Outputs are active high. Never connect an LED without a resistor.
- Never connect a GPIO to 5 V or mains.

References: GPIO Zero [Button and RotaryEncoder](https://gpiozero.readthedocs.io/en/stable/api_input.html), [LED](https://gpiozero.readthedocs.io/en/stable/api_output.html#led).

## Behavior

**Buttons.** Inputs are sampled every 10 ms and must be stable for the debounce period, both on press and release. A button held at startup does nothing until released and pressed again. Holding does not repeat.

**One request at a time.** Presses or turns during an active request are discarded, never queued. Each action is submitted once and polled with the controller timeout. A timeout or lost connection is reported and never retried; press again to try again.

**Action selector encoder.** Turning selects the next or previous action (wrapping) and prints a `selected` event; it sends nothing. Pressing runs the selection. Selection starts at the first action. `--simulate` with the press pin runs the first action; rotation is not simulated.

**Brightness encoder.** `brightness_action` must name a color action with `power: true` and `rgb`, or a native-effect action. The level starts at 50% and moves in 5% steps (1 to 100%). The latest level is sent after a 200 ms window, one command at a time; intermediate levels are dropped. After a failure, automatic sending pauses until a deliberate press. The level is a commanded value, not readback.

**Status LEDs.**

| LED | Meaning |
| --- | --- |
| Sending | On while an accepted request is in flight |
| Completed | On after success (including dry-run and simulation) until the next action |
| Error | On after a failed, cancelled or uncertain request until the next action |

LEDs describe command processing, not lamp state. All outputs start off. If an LED output fails at runtime, indicators are disabled with a warning and commands continue.

**Shutdown.** Inputs stop, an in-flight request may finish within its timeout (up to 120 seconds), then LEDs are turned off and GPIO is released. Stopping cannot undo a command already sent.
