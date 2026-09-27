import asyncio
import json
from pathlib import Path
import tempfile
import unittest
from ks_light.gpio_controller import ActionGate, StatusLights, load_hardware, run_buttons


class LED:
    def __init__(self, pin, **kwargs):
        assert kwargs == {"active_high": True, "initial_value": False}
        self.pin, self.lit, self.closed, self.broken = pin, False, False, False
    def on(self):
        if self.broken: raise OSError("private GPIO error")
        self.lit = True
    def off(self): self.lit = False
    def close(self): self.closed = True


class StatusTests(unittest.TestCase):
    def test_pin_collisions_and_invalid_roles_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "buttons.json"
            base = {"buttons": [{"pin": 17, "action": "on"}]}
            for leds in [[], {"wrong": 24}, {"sending": True}, {"sending": 28},
                         {"sending": 17}, {"sending": 24, "error": 24}]:
                path.write_text(json.dumps({**base, "status_leds": leds}))
                with self.subTest(leds=leds), self.assertRaises(ValueError):
                    load_hardware(path, {"on": {}})
            path.write_text(json.dumps({**base, "status_leds": {"error": 24}}))
            self.assertEqual(load_hardware(path, {"on": {}})[2], {"error": 24})
            path.write_text(json.dumps(base))
            self.assertEqual(load_hardware(path, {"on": {}})[2], {})

    def test_status_transition_busy_does_not_hide_request_and_close_turns_off(self):
        lights = StatusLights({"sending": 24, "completed": 25, "error": 26}, LED)
        def lit(): return {k for k, v in lights.devices.items() if v.lit}
        for status, expected in [("ready", set()), ("sending", {"sending"}),
                                 ("busy", {"sending"}), ("succeeded", {"completed"}),
                                 ("sending", {"sending"}), ("failed", {"error"}),
                                 ("cancelled", {"error"}), ("error", {"error"})]:
            lights.show({"status": status})
            self.assertEqual(lit(), expected)
        lights.close()
        self.assertEqual(lit(), set())
        self.assertTrue(all(v.closed for v in lights.devices.values()))

    def test_partial_led_setup_closes_previous_outputs(self):
        created = []
        def factory(pin, **kwargs):
            if pin == 25: raise OSError("unavailable")
            created.append(LED(pin, **kwargs))
            return created[-1]
        with self.assertRaises(OSError):
            StatusLights({"sending": 24, "completed": 25}, factory)
        self.assertTrue(created[0].closed)
        self.assertFalse(created[0].lit)


class StatusRuntimeTests(unittest.IsolatedAsyncioTestCase):
    async def test_failed_indicator_does_not_change_or_repeat_delivery(self):
        lights = StatusLights({"completed": 25}, LED)
        lights.devices["completed"].broken = True
        events, calls, failures = [], [], []
        def emit(event):
            if not lights.show(event): failures.append(True)
            events.append(event)
        async def send(action):
            calls.append(action)
            return {"status": "succeeded", "confirmation": "unconfirmed"}
        gate = ActionGate(send, emit)
        gate.press("on")
        await gate.drain()
        self.assertEqual(calls, ["on"])
        self.assertEqual(events[-1]["status"], "succeeded")
        self.assertEqual(failures, [True])
        self.assertTrue(lights.devices["completed"].closed)
        gate.press("off")
        await gate.drain()
        self.assertEqual(calls, ["on", "off"])
        self.assertEqual(failures, [True])

    async def test_shutdown_closes_inputs_then_waits_for_completion_then_leds(self):
        stop, started, release = asyncio.Event(), asyncio.Event(), asyncio.Event()
        outputs, snapshots = {}, []
        class Button:
            is_pressed = False
            closed = False
            def close(self): self.closed = True
        button = Button()
        def factory(pin, **kwargs):
            outputs[pin] = LED(pin, **kwargs)
            return outputs[pin]
        async def send(action):
            started.set()
            await release.wait()
            return {"status": "succeeded", "confirmation": "simulated"}
        def emit(event):
            snapshots.append((event["status"], {p for p, d in outputs.items() if d.lit}))
        task = asyncio.create_task(run_buttons({17: "on"}, .02, lambda *a, **k: button,
            send, stop, emit, led_mapping={"sending": 24, "completed": 25}, led_factory=factory))
        try:
            await asyncio.sleep(.02)
            button.is_pressed = True
            await asyncio.wait_for(started.wait(), 1)
            stop.set()
            await asyncio.sleep(.03)
            self.assertTrue(button.closed)
            self.assertFalse(task.done())
            self.assertTrue(outputs[24].lit)
            release.set()
            await asyncio.wait_for(task, 1)
            self.assertIn(("sending", {24}), snapshots)
            self.assertIn(("succeeded", {25}), snapshots)
            self.assertTrue(all(d.closed and not d.lit for d in outputs.values()))
        finally:
            stop.set(); release.set()
            await task
