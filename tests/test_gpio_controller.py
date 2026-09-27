import asyncio
import json
from pathlib import Path
import sys
import tempfile
import unittest
from aiohttp.test_utils import TestServer
from ks_light.controller import ControllerError, execute
from ks_light.gpio_controller import ActionGate, DebouncedButton, load_buttons, run_buttons
from ks_light.hub import create_app


class ButtonTests(unittest.TestCase):
    def test_bounce_hold_release_and_repress(self):
        button = DebouncedButton(False, 0, .05)
        self.assertFalse(button.update(True, .01))
        self.assertFalse(button.update(False, .02))
        self.assertFalse(button.update(True, .03))
        self.assertFalse(button.update(True, .06))
        self.assertTrue(button.update(True, .09))
        self.assertFalse(button.update(True, 5))
        self.assertFalse(button.update(False, 6))
        self.assertFalse(button.update(False, 6.1))
        self.assertFalse(button.update(True, 7))
        self.assertTrue(button.update(True, 7.1))

    def test_held_at_startup_requires_release(self):
        button = DebouncedButton(True, 0, .05)
        self.assertFalse(button.update(True, 10))
        self.assertFalse(button.update(False, 11))
        self.assertFalse(button.update(False, 11.1))
        self.assertFalse(button.update(True, 12))
        self.assertTrue(button.update(True, 12.1))

    def test_invalid_mapping_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "buttons.json"
            valid = {"buttons": [{"pin": 17, "action": "on"}]}
            path.write_text(json.dumps(valid))
            self.assertEqual(load_buttons(path, {"on": {}}), ({17: "on"}, .05))
            for data in [[], {}, {**valid, "debounce_ms": True}, {**valid, "debounce_ms": 0},
                         {**valid, "debounce_ms": float("nan")},
                         {"buttons": valid["buttons"] * 2},
                         {"buttons": [{"pin": True, "action": "on"}]},
                         {"buttons": [{"pin": 28, "action": "on"}]},
                         {"buttons": [{"pin": 17, "action": "missing"}]}]:
                path.write_text(json.dumps(data))
                with self.subTest(data=data), self.assertRaises(ValueError):
                    load_buttons(path, {"on": {}})


class RuntimeTests(unittest.IsolatedAsyncioTestCase):
    async def test_busy_press_discarded_failure_not_replayed_and_next_press_recovers(self):
        events, calls = [], []
        release = asyncio.Event()
        async def send(name):
            calls.append(name)
            await release.wait()
            if len(calls) == 1:
                raise ControllerError("Delivery unknown; not retried")
            return {"status": "succeeded", "confirmation": "simulated"}
        gate = ActionGate(send, events.append)
        self.assertTrue(gate.press("on"))
        self.assertFalse(gate.press("off"))
        release.set()
        await gate.drain()
        self.assertEqual(calls, ["on"])
        self.assertEqual(events[-1]["status"], "error")
        self.assertTrue(gate.press("off"))
        await gate.drain()
        self.assertEqual(calls, ["on", "off"])
        self.assertEqual(events[-1]["confirmation"], "simulated")

    async def test_inputs_close_even_if_partial_setup_fails(self):
        class Device:
            closed = False
            def close(self): self.closed = True
        device = Device()
        def factory(pin, **kwargs):
            if pin == 27: raise RuntimeError("GPIO unavailable")
            return device
        with self.assertRaises(RuntimeError):
            await run_buttons({17: "on", 27: "off"}, .02, factory, None, asyncio.Event(), lambda _: None)
        self.assertTrue(device.closed)

    async def test_button_loop_to_authenticated_hub_and_clean_shutdown(self):
        writes, events = [], []
        async def sender(light, packets): writes.append(packets)
        token = "gpio-test-token-only-00000000000000000"
        server = TestServer(create_app([{"id": "desk", "name": "Desk", "prefix": "KS03~", "address": "fake"}], token, sender=sender))
        await server.start_server()
        class Device:
            is_pressed = False
            closed = False
            def close(self): self.closed = True
        device, stop = Device(), asyncio.Event()
        def factory(pin, **kwargs):
            self.assertEqual(kwargs, {"pull_up": True, "bounce_time": None})
            return device
        async def send(name):
            self.assertEqual(name, "on")
            return await execute(str(server.make_url("/api/v1")), token,
                {"light": "desk", "type": "state", "body": {"power": True}})
        def emit(event):
            events.append(event)
            if event.get("confirmation") == "simulated": stop.set()
        task = asyncio.create_task(run_buttons({17: "on"}, .02, factory, send, stop, emit))
        try:
            await asyncio.sleep(.02)
            device.is_pressed = True
            await asyncio.wait_for(task, 3)
            self.assertEqual(len(writes), 1)
            self.assertTrue(device.closed)
            self.assertEqual(events[-1]["status"], "succeeded")
        finally:
            stop.set()
            await task
            await server.close()

    async def test_check_and_simulate_cli_need_no_gpio_or_network(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            secret = "private-test-credential"
            (root / "token").write_text(secret)
            (root / "controller.json").write_text(json.dumps({
                "hub_url": "http://127.0.0.1:1/api/v1", "token_file": "token",
                "actions": {"on": {"light": "desk", "type": "state", "body": {"power": True}}}}))
            (root / "buttons.json").write_text(json.dumps({"buttons": [{"pin": 17, "action": "on"}]}))
            for mode, expected in [(["--check"], 0), (["--simulate", "17", "17"], 0), (["--simulate", "27"], 2)]:
                proc = await asyncio.create_subprocess_exec(sys.executable, "-m", "ks_light.gpio_controller",
                    "--config", str(root / "controller.json"), "--buttons", str(root / "buttons.json"), *mode,
                    stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
                out, err = await asyncio.wait_for(proc.communicate(), 5)
                self.assertEqual(proc.returncode, expected, err)
                self.assertNotIn(secret.encode(), out + err)
                if mode[0] == "--simulate" and expected == 0:
                    self.assertEqual(len(out.splitlines()), 4)
                    self.assertTrue(all(json.loads(line)["confirmation"] == "dry-run" for line in out.splitlines() if json.loads(line)["status"] == "succeeded"))
