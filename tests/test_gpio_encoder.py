import asyncio
import json
from pathlib import Path
import tempfile
import unittest
from ks_light.gpio_controller import RotarySelection, load_hardware, run_buttons


class EncoderTests(unittest.TestCase):
    def test_direction_wrap_and_busy_motion_is_not_replayed(self):
        selection = RotarySelection(["on", "reading", "off"], 100)
        self.assertEqual(selection.action, "on")
        selection.update(99)
        self.assertEqual(selection.action, "off")
        selection.update(103)
        self.assertEqual(selection.action, "on")
        self.assertFalse(selection.update(110, busy=True))
        self.assertFalse(selection.update(110))
        self.assertEqual(selection.action, "on")
        selection.update(111)
        self.assertEqual(selection.action, "reading")

    def test_encoder_only_setup_and_all_pin_collisions(self):
        good={"a":5,"b":6,"press":13,"actions":["on","off"]}
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"gpio.json"
            path.write_text(json.dumps({"encoders":[good]}))
            mapping,_,_,encoders=load_hardware(path,{"on":{},"off":{}},include_rotary=True)
            self.assertEqual(mapping,{13:"on"});self.assertEqual(encoders,[good])
            for bad in [
                {"encoders":[{**good,"b":5}]},
                {"encoders":[{**good,"press":True}]},
                {"encoders":[{**good,"actions":["missing"]}]},
                {"encoders":[{**good,"actions":["on","on"]}]},
                {"encoders":[good,good]},
                {"encoders":[good],"buttons":[{"pin":6,"action":"on"}]},
                {"encoders":[good],"status_leds":{"error":13}}]:
                path.write_text(json.dumps(bad))
                with self.subTest(bad=bad),self.assertRaises(ValueError):
                    load_hardware(path,{"on":{},"off":{}},include_rotary=True)


class EncoderRuntimeTests(unittest.IsolatedAsyncioTestCase):
    async def test_turn_only_selects_press_sends_selected_action_and_closes_hardware(self):
        class Button:
            is_pressed=False
            closed=False
            def close(self):self.closed=True
        class Rotor:
            steps=0
            closed=False
            def close(self):self.closed=True
        button,rotor,stop=Button(),Rotor(),asyncio.Event()
        calls=[];selected=asyncio.Event()
        async def send(action):
            calls.append(action);stop.set()
            return {"status":"succeeded","confirmation":"simulated"}
        def emit(event):
            if event.get("status")=="selected" and event.get("action")=="off":selected.set()
        def encoder_factory(a,b,**kwargs):
            self.assertEqual((a,b),(5,6));self.assertEqual(kwargs,{"max_steps":0,"bounce_time":None})
            return rotor
        task=asyncio.create_task(run_buttons({13:"on"},.02,lambda *a,**k:button,send,stop,emit,
            encoders=[{"a":5,"b":6,"press":13,"actions":["on","off"]}],encoder_factory=encoder_factory))
        try:
            await asyncio.sleep(.02);rotor.steps=1
            await asyncio.wait_for(selected.wait(),1)
            self.assertEqual(calls,[])
            button.is_pressed=True
            await asyncio.wait_for(task,1)
            self.assertEqual(calls,["off"])
            self.assertTrue(button.closed and rotor.closed)
        finally:
            stop.set();await task

    async def test_partial_encoder_setup_releases_buttons_and_first_rotor(self):
        class Device:
            is_pressed=False
            steps=0
            closed=False
            def close(self):self.closed=True
        buttons=[];rotor=Device()
        def button_factory(*args,**kwargs):
            device=Device();buttons.append(device);return device
        def rotor_factory(a,b,**kwargs):
            if a==7:raise OSError("not available")
            return rotor
        encoders=[{"a":5,"b":6,"press":13,"actions":["on"]},
                  {"a":7,"b":8,"press":19,"actions":["on"]}]
        with self.assertRaises(OSError):
            await run_buttons({13:"on",19:"on"},.02,button_factory,None,asyncio.Event(),lambda _:None,
                encoders=encoders,encoder_factory=rotor_factory)
        self.assertTrue(rotor.closed and all(b.closed for b in buttons))


class GPIOZeroIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def test_real_gpiozero_decoder_with_mock_pins(self):
        try:
            from gpiozero import Button, RotaryEncoder
            from gpiozero.pins.mock import MockFactory
        except ImportError:
            self.skipTest("Install requirements-gpio.txt for GPIO Zero integration")
        pins=MockFactory();stop=asyncio.Event();selected=asyncio.Event();calls=[]
        async def send(action):
            calls.append(action);stop.set()
            return {"status":"succeeded","confirmation":"simulated"}
        def emit(event):
            if event.get("status")=="selected" and event.get("action")=="off":selected.set()
        task=asyncio.create_task(run_buttons({13:"on"},.02,
            lambda pin,**kw:Button(pin,pin_factory=pins,**kw),send,stop,emit,
            encoders=[{"a":5,"b":6,"press":13,"actions":["on","off"]}],
            encoder_factory=lambda a,b,**kw:RotaryEncoder(a,b,pin_factory=pins,**kw)))
        try:
            await asyncio.sleep(.03)
            a,b=pins.pin(5),pins.pin(6)
            a.drive_low();b.drive_low();a.drive_high();b.drive_high()
            await asyncio.wait_for(selected.wait(),1)
            self.assertEqual(calls,[])
            pins.pin(13).drive_low()
            await asyncio.wait_for(task,1)
            self.assertEqual(calls,["off"])
        finally:
            stop.set();await task;pins.close()
