import asyncio
import json
from pathlib import Path
import tempfile
import unittest

from ks_light.gpio_controller import RotaryBrightness, load_hardware, run_buttons
from ks_light.controller import ControllerError


class BrightnessTests(unittest.TestCase):
    def test_latest_level_debounce_clamp_and_manual_recovery(self):
        dial = RotaryBrightness('reading', 0)
        self.assertIsNone(dial.take(50))
        dial.update(1, 1)
        dial.update(3, 1.1)
        self.assertIsNone(dial.take(1.19))
        self.assertEqual(dial.take(1.4), 65)
        self.assertIsNone(dial.take(2))
        dial.update(1000, 3)
        self.assertEqual(dial.level, 100)
        dial.fail()
        dial.update(-1000, 4)
        self.assertIsNone(dial.take(8))
        self.assertEqual(dial.take(8, manual=True), 1)
        dial.update(-999, 9)
        self.assertEqual(dial.take(10), 6)

    def test_config_requires_explicit_color_or_effect_action(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'pins.json'
            path.write_text(json.dumps({'encoders': [{'a': 5, 'b': 6, 'press': 13, 'brightness_action': 'reading'}]}))
            action = {'light': 'desk', 'type': 'state', 'body': {'power': True, 'rgb': [10, 20, 30]}}
            self.assertEqual(load_hardware(path, {'reading': action})[0], {13: 'reading'})
            with self.assertRaises(ControllerError):
                load_hardware(path, {'reading': {**action, 'body': {'power': True}}})


class RuntimeTests(unittest.IsolatedAsyncioTestCase):
    async def test_rotation_during_send_coalesces_and_closes_inputs(self):
        class Device:
            steps = 0
            is_pressed = False
            closed = False
            def close(self): self.closed = True
        rotor, button = Device(), Device()
        stop, first_started, release, second_started = (asyncio.Event() for _ in range(4))
        calls = []
        async def send(action, level):
            calls.append((action, level))
            if len(calls) == 1:
                first_started.set()
                await release.wait()
            else:
                second_started.set()
                stop.set()
            return {'status': 'succeeded', 'confirmation': 'simulated'}
        task = asyncio.create_task(run_buttons({13: 'reading'}, .02, lambda *a, **k: button,
            send, stop, lambda _: None, encoders=[{'a': 5, 'b': 6, 'press': 13, 'brightness_action': 'reading'}],
            encoder_factory=lambda *a, **k: rotor))
        try:
            await asyncio.sleep(.03)
            rotor.steps = 1
            await asyncio.wait_for(first_started.wait(), 2)
            rotor.steps = 4
            await asyncio.sleep(.25)
            self.assertEqual(calls, [('reading', 55)])
            release.set()
            await asyncio.wait_for(second_started.wait(), 2)
            await task
            self.assertEqual(calls, [('reading', 55), ('reading', 70)])
            self.assertTrue(rotor.closed and button.closed)
        finally:
            release.set(); stop.set()
            await task
