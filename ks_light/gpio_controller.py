"""Raspberry Pi momentary buttons for named hub actions (BCM numbering)."""
import argparse
import asyncio
import json
import math
from pathlib import Path
import signal
import sys
import time

from .controller import ControllerError, execute, load_config, with_brightness


def load_hardware(path, actions, *, include_rotary=False):
    data = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict) or set(data) - {"buttons", "debounce_ms", "status_leds", "encoders"}:
        raise ValueError("Invalid button configuration")
    debounce = data.get("debounce_ms", 50)
    if type(debounce) not in (int, float) or not math.isfinite(debounce) or not 20 <= debounce <= 1000:
        raise ValueError("Debounce must be 20..1000 milliseconds")
    entries = data.get("buttons", [])
    if not isinstance(entries, list):
        raise ValueError("Buttons must be a list")
    buttons = {}
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != {"pin", "action"}:
            raise ValueError("Each button needs pin and action")
        pin, action = entry["pin"], entry["action"]
        if type(pin) is not int or not 2 <= pin <= 27 or pin in buttons:
            raise ValueError("Use unique BCM GPIO numbers from 2 to 27")
        if not isinstance(action, str) or action not in actions:
            raise ValueError("Button refers to an unknown action")
        buttons[pin] = action
    leds = data.get("status_leds", {})
    if not isinstance(leds, dict) or set(leds) - {"sending", "completed", "error"}:
        raise ValueError("Invalid status LED roles")
    used = set(buttons)
    for pin in leds.values():
        if type(pin) is not int or not 2 <= pin <= 27 or pin in used:
            raise ValueError("Status LEDs need unused BCM GPIO numbers from 2 to 27")
        used.add(pin)
    encoders = data.get("encoders", [])
    if not isinstance(encoders, list) or len(encoders) > 4:
        raise ValueError("Encoders must be a list with at most four entries")
    for encoder in encoders:
        if not isinstance(encoder, dict) or set(encoder) not in (
                {"a", "b", "press", "actions"}, {"a", "b", "press", "brightness_action"}):
            raise ValueError("Encoder needs a, b, press and actions or brightness_action")
        names = [encoder["brightness_action"]] if "brightness_action" in encoder else encoder["actions"]
        if (not isinstance(names, list) or not 1 <= len(names) <= 32 or
                any(not isinstance(name, str) or name not in actions for name in names) or
                len(set(names)) != len(names)):
            raise ValueError("Encoder needs 1..32 unique configured actions")
        if "brightness_action" in encoder:
            with_brightness(actions[names[0]], 50)
        for role in ("a", "b", "press"):
            pin = encoder[role]
            if type(pin) is not int or not 2 <= pin <= 27 or pin in used:
                raise ValueError("Encoder pins must be distinct unused BCM GPIO numbers from 2 to 27")
            used.add(pin)
        buttons[encoder["press"]] = names[0]
    if not buttons:
        raise ValueError("Configure at least one button or encoder")
    result = (buttons, debounce / 1000, leds)
    return (*result, encoders) if include_rotary else result


def load_buttons(path, actions):
    buttons, debounce, _ = load_hardware(path, actions)
    return buttons, debounce


class RotarySelection:
    """GPIO Zero decodes edges; we consume accumulated detents without sending."""
    def __init__(self, actions, steps):
        self.actions, self.steps, self.index = tuple(actions), steps, 0

    @property
    def action(self):
        return self.actions[self.index]

    def update(self, steps, busy=False):
        delta, self.steps = steps - self.steps, steps
        if not delta or busy:
            return False
        self.index = (self.index + delta) % len(self.actions)
        return True


class RotaryBrightness:
    """Latest absolute level only. Failure requires a deliberate press to re-arm."""
    def __init__(self, action, steps):
        self.action, self.steps, self.level = action, steps, 50
        self.pending, self.paused, self.due = False, False, 0

    def update(self, steps, now):
        delta, self.steps = steps - self.steps, steps
        level = max(1, min(100, self.level + max(-100, min(100, delta)) * 5))
        if level == self.level:
            return False
        if not self.pending:
            self.due = now + .2
        self.level, self.pending = level, not self.paused
        return True

    def take(self, now, manual=False):
        if not manual and (self.paused or not self.pending or now < self.due):
            return None
        self.pending, self.paused = False, False
        return self.level

    def fail(self):
        self.pending, self.paused = False, True


class StatusLights:
    """Command feedback only. No LED is a claim about physical lamp state."""
    def __init__(self, mapping, factory):
        self.devices = {}
        self.disabled = False
        try:
            for role, pin in mapping.items():
                self.devices[role] = factory(pin, active_high=True, initial_value=False)
        except Exception:
            self.close()
            raise

    def show(self, event):
        if self.disabled:
            return True
        status = event.get("status")
        if status == "busy":  # A discarded press must not hide the active operation.
            return True
        if status not in {"ready", "sending", "succeeded", "failed", "cancelled", "error"}:
            return True
        role = {"sending": "sending", "succeeded": "completed", "failed": "error",
                "cancelled": "error", "error": "error"}.get(status)
        try:
            for name, device in self.devices.items():
                if name != role:
                    device.off()
            if role in self.devices:
                self.devices[role].on()
            return True
        except Exception:
            # A broken indicator must not affect delivery or cause a second send.
            self.close()
            return False

    def close(self):
        self.disabled = True
        for device in self.devices.values():
            try:
                device.off()
            except Exception:
                pass
            try:
                device.close()
            except Exception:
                pass


class DebouncedButton:
    """Emit only a stable released-to-pressed edge; a held startup is inert."""
    def __init__(self, pressed, now, delay):
        self.stable = self.candidate = bool(pressed)
        self.since = now
        self.delay = delay

    def update(self, pressed, now):
        pressed = bool(pressed)
        if pressed != self.candidate:
            self.candidate, self.since = pressed, now
        if self.candidate != self.stable and now - self.since >= self.delay:
            self.stable = self.candidate
            return self.stable
        return False


class ActionGate:
    """One operation at a time, no backlog and no replay after uncertain failure."""
    def __init__(self, send, emit):
        self.send, self.emit = send, emit
        self.task = None

    def press(self, action, brightness=None):
        if self.task is not None and not self.task.done():
            self.emit({"action": action, "status": "busy", "discarded": True})
            return False
        self.task = asyncio.create_task(self._run(action, brightness))
        return True

    async def _run(self, action, brightness=None):
        try:
            self.emit({"action": action, "status": "sending"})
            result = await self.send(action) if brightness is None else await self.send(action, brightness)
            self.emit({"action": action, **{k: result[k] for k in
                ("operation_id", "status", "confirmation") if k in result}})
        except ControllerError as error:
            self.emit({"action": action, "status": "error", "message": str(error)})
        except Exception:
            self.emit({"action": action, "status": "error",
                "message": "Controller failed; delivery unknown. Command was not retried."})

    async def drain(self):
        if self.task is not None:
            await self.task


async def run_buttons(mapping, debounce, factory, send, stop, emit, interval=0.01,
                      led_mapping=None, led_factory=None, encoders=None, encoder_factory=None):
    mapping = dict(mapping)
    devices, rotors, selectors, dimmers = {}, {}, {}, {}
    indicators = None
    def report(event):
        if event.get("status") in {"failed", "cancelled", "error"}:
            for dimmer in dimmers.values():
                dimmer.fail()
        if indicators is not None and not indicators.show(event):
            emit({"status": "indicator_error", "message": "Status LEDs disabled; see command results in this log"})
        emit(event)
    gate = ActionGate(send, report)
    try:
        if led_mapping:
            if led_factory is None:
                raise ValueError("LED factory required for configured indicators")
            indicators = StatusLights(led_mapping, led_factory)
        for pin in mapping:
            devices[pin] = factory(pin, pull_up=True, bounce_time=None)
        now = time.monotonic()
        states = {pin: DebouncedButton(device.is_pressed, now, debounce)
                  for pin, device in devices.items()}
        for encoder in encoders or []:
            pin = encoder["press"]
            if encoder_factory is None:
                raise ValueError("Encoder factory required")
            rotors[pin] = encoder_factory(encoder["a"], encoder["b"], max_steps=0, bounce_time=None)
            if "brightness_action" in encoder:
                dimmers[pin] = RotaryBrightness(encoder["brightness_action"], rotors[pin].steps)
                mapping[pin] = dimmers[pin].action
            else:
                selectors[pin] = RotarySelection(encoder["actions"], rotors[pin].steps)
                mapping[pin] = selectors[pin].action
            report({"status": "selected", "pin": pin, "action": mapping[pin]})
        report({"status": "ready", "buttons": len(devices), "encoders": len(rotors)})
        while not stop.is_set():
            now = time.monotonic()
            busy = gate.task is not None and not gate.task.done()
            for pin, rotor in rotors.items():
                if pin in dimmers:
                    if dimmers[pin].update(rotor.steps, now):
                        report({"status": "preview", "pin": pin, "brightness": dimmers[pin].level,
                                "paused": dimmers[pin].paused})
                elif selectors[pin].update(rotor.steps, busy):
                    mapping[pin] = selectors[pin].action
                    report({"status": "selected", "pin": pin, "action": mapping[pin]})
            for pin, device in devices.items():
                if states[pin].update(device.is_pressed, now):
                    if pin in dimmers and not (gate.task is not None and not gate.task.done()):
                        gate.press(mapping[pin], dimmers[pin].take(now, manual=True))
                    else:
                        gate.press(mapping[pin])
            if gate.task is None or gate.task.done():
                for pin, dimmer in dimmers.items():
                    level = dimmer.take(now)
                    if level is not None:
                        gate.press(mapping[pin], level)
                        break
            await asyncio.sleep(interval)
    finally:
        # Stop reading inputs first. Already submitted commands have bounded completion.
        for device in list(devices.values()) + list(rotors.values()):
            try:
                device.close()
            except Exception:
                emit({"status": "error", "message": "Could not release a GPIO input"})
        try:
            await gate.drain()
        finally:
            if indicators is not None:
                indicators.close()


def output(event):
    print(json.dumps(event), flush=True)


async def run(args, config, mapping, debounce, led_mapping=None, encoders=None):
    url, token, timeout, actions, context = config
    async def send(name, brightness=None):
        if args.dry_run or args.simulate is not None:
            return {"status": "succeeded", "confirmation": "dry-run"}
        action = actions[name] if brightness is None else with_brightness(actions[name], brightness)
        return await execute(url, token, action, timeout, context)
    if args.simulate is not None:
        for pin in args.simulate:
            if pin not in mapping:
                raise ValueError("Simulated pin is not configured")
        gate = ActionGate(send, output)
        for pin in args.simulate:
            gate.press(mapping[pin])
            await gate.drain()
        return
    try:
        from gpiozero import Button, LED, RotaryEncoder
    except ImportError:
        raise ControllerError("Install gpiozero on the Pi before using GPIO; --check and --simulate need no GPIO package.") from None
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    previous = {}
    for sig in (signal.SIGINT, signal.SIGTERM):
        previous[sig] = signal.signal(sig, lambda *_: loop.call_soon_threadsafe(stop.set))
    try:
        await run_buttons(mapping, debounce, Button, send, stop, output,
                          led_mapping=led_mapping, led_factory=LED, encoders=encoders, encoder_factory=RotaryEncoder)
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, help="Existing controller action configuration")
    parser.add_argument("--buttons", required=True, help="GPIO pin-to-action JSON")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--check", action="store_true", help="Validate files without GPIO or network access")
    modes.add_argument("--dry-run", action="store_true", help="Read real buttons but never send commands")
    modes.add_argument("--simulate", type=int, nargs="+", help="Simulate listed BCM presses without GPIO or network")
    args = parser.parse_args()
    try:
        config = load_config(args.config)
        mapping, debounce, leds, encoders = load_hardware(args.buttons, config[3], include_rotary=True)
        if args.check:
            output({"status": "valid", "buttons": len(mapping), "status_leds": len(leds), "encoders": len(encoders)})
        else:
            asyncio.run(run(args, config, mapping, debounce, leds, encoders))
        return 0
    except Exception:
        error = sys.exc_info()[1]
        print(str(error) if isinstance(error, ControllerError) else
              "Invalid controller setup or GPIO unavailable; no command will be replayed.", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
