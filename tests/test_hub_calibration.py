import asyncio
import copy
import json
from pathlib import Path
import tempfile
import unittest

from aiohttp.test_utils import TestClient, TestServer
from ks_light.calibration import apply, valid_gains
from ks_light.hub import Hub, create_app, validate_lights
from ks_light.hub_state import StateStore
from ks_light.protocol import color, power
from tests.test_hub import LIGHTS, TOKEN
from tests.test_hub_library import LIBRARY


class CalibrationConfigTests(unittest.TestCase):
    def test_gain_validation_and_android_rounding(self):
        self.assertEqual(apply([1, 3, 255], [.5, .5, .5]), [1, 2, 128])
        self.assertEqual(apply([239, 66, 255], [1, .3, .75]), [239, 20, 191])
        self.assertEqual(apply([255, 255, 255], [0, 0, 0]), [0, 0, 0])
        for invalid in [None, [], [1, 1], [1, 1, 1, 1], [True, 1, 1], ["1", 1, 1],
                        [float("nan"), 1, 1], [float("inf"), 1, 1], [-.1, 1, 1], [1.1, 1, 1]]:
            self.assertFalse(valid_gains(invalid), repr(invalid))
            with self.assertRaises(ValueError):
                validate_lights([{**LIGHTS[0], "calibration": {"rgb_gains": invalid}}])

    def test_config_is_copied_and_unsupported_profiles_rejected(self):
        item = {**LIGHTS[0], "calibration": {"rgb_gains": [1, .3, .75]}}
        copied = validate_lights([item])
        item["calibration"]["rgb_gains"][0] = 0
        self.assertEqual(copied["desk"]["calibration"]["rgb_gains"], [1, .3, .75])
        for calibration in [None, [], {}, {"rgb_gains": [1, 1, 1], "gamma": 2}]:
            with self.assertRaises(ValueError): validate_lights([{**LIGHTS[0], "calibration": calibration}])
        with self.assertRaises(ValueError):
            validate_lights([{**LIGHTS[0], "prefix": "KS04~", "calibration": {"rgb_gains": [1, 1, 1]}}])

    def test_snapshot_calibration_identity_and_legacy_neutral_compatibility(self):
        state = {"power": True, "rgb": [239, 66, 255], "brightness": 40}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "state.json"
            neutral = {"desk": LIGHTS[0]}
            calibrated = {"desk": {**LIGHTS[0], "calibration": {"rgb_gains": [1, .3, .75]}}}
            StateStore(path, neutral, True).save({"desk": state}, set())
            self.assertNotIn("rgb_gains", json.loads(path.read_text())["lights"]["desk"])
            self.assertEqual(StateStore(path, neutral, True).load(), {"desk": state})
            self.assertEqual(StateStore(path, calibrated, True).load(), {})
            StateStore(path, calibrated, True).save({"desk": state}, set())
            self.assertEqual(StateStore(path, calibrated, True).load(), {"desk": state})
            self.assertEqual(StateStore(path, neutral, True).load(), {})
            raw = json.loads(path.read_text())
            raw["lights"]["desk"]["rgb_gains"] = [True, 1, 1]
            path.write_text(json.dumps(raw), encoding="utf-8")
            with self.assertRaises(ValueError): StateStore(path, neutral, True).load()


class CalibrationDeliveryTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.lights = copy.deepcopy(LIGHTS)
        self.lights[0]["calibration"] = {"rgb_gains": [1, .3, .75]}
        self.lights[1]["calibration"] = {"rgb_gains": [.5, 1, .5]}
        self.writes = []
        async def sender(light, packets): self.writes.append((light["id"], packets))
        self.sender = sender
        self.hub = Hub(self.lights, sender=sender, library=LIBRARY)

    async def asyncTearDown(self):
        await self.hub.close()

    async def test_color_wire_and_remembered_brightness_do_not_compound_gains(self):
        command = {"power": True, "rgb": [239, 66, 255], "brightness": 40}
        await self.hub._deliver("desk", ("state", command))
        self.assertEqual(self.writes[-1][1], [power(True), color(239, 20, 191, "floor", 40)])
        self.assertEqual(self.hub.last_sent["desk"], command)
        await self.hub._deliver("desk", ("state", {"power": True, "brightness": 65}))
        self.assertEqual(self.writes[-1][1][-1], color(239, 20, 191, "floor", 65))
        self.assertEqual(self.hub.last_sent["desk"]["rgb"], [239, 66, 255])
        self.assertEqual(command["rgb"], [239, 66, 255])

    async def test_native_effect_and_power_do_not_apply_rgb_balance(self):
        await self.hub._deliver("desk", ("native", {"effect": 137, "speed": 35, "brightness": 40}))
        self.assertEqual(self.writes[-1][1][-1], bytes([0x5c, 0, 137, 35, 40, 0, 0xc5]))
        await self.hub._deliver("desk", ("state", {"power": True, "brightness": 70}))
        self.assertEqual(self.writes[-1][1][-1], bytes([0x5c, 0, 137, 35, 70, 0, 0xc5]))
        await self.hub._deliver("desk", ("state", {"power": False}))
        self.assertEqual(self.writes[-1][1], [power(False)])

    async def test_group_uses_each_members_balance(self):
        op = self.hub.submit_collection("group", "room", "state", {"power": True, "rgb": [100, 100, 100], "brightness": 40}, None)
        await asyncio.gather(*list(self.hub.tasks))
        self.assertEqual(self.hub.operations[op]["status"], "succeeded")
        packets = dict(self.writes)
        self.assertEqual(packets["desk"][-1], color(100, 30, 75, "floor", 40))
        self.assertEqual(packets["sofa"][-1], color(50, 100, 50, "floor", 40))

    async def test_api_exposes_active_balance_without_physical_address(self):
        client = TestClient(TestServer(create_app(self.lights, TOKEN, sender=self.sender)))
        await client.start_server()
        try:
            headers = {"Authorization": "Bearer " + TOKEN}
            response = await client.get('/api/v1/lights/desk', headers=headers)
            light = await response.json()
            self.assertEqual(light['calibration'], {'rgb_gains': [1, .3, .75]})
            self.assertNotIn('address', light)
            response = await client.get('/api/v1/capabilities', headers=headers)
            self.assertTrue((await response.json())['calibration'])
        finally:
            await client.close()
