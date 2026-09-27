import asyncio
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

from aiohttp.test_utils import TestClient, TestServer
from ks_light.controller import ControllerError, execute, load_config, with_brightness
from ks_light.hub import Hub, create_app, APIError
from ks_light.hub_library import load_library
from tests.test_hub import LIGHTS, TOKEN

LIBRARY = {
    "version": 1,
    "groups": [{"id": "room", "name": "Room", "members": ["desk", "sofa"]},
               {"id": "all", "name": "All", "members": ["desk", "ceiling"]}],
    "scenes": [{"id": "evening", "name": "Evening", "actions": [
        {"light": "desk", "type": "state", "body": {"power": True, "rgb": [255, 190, 120], "brightness": 35}},
        {"light": "sofa", "type": "native", "body": {"effect": 137, "speed": 35, "brightness": 25}}]}]}


class LibraryHTTPTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.sent = []
        self.broken = set()

        async def sender(light, packets):
            self.sent.append((light["id"], packets))
            if light["id"] in self.broken:
                raise OSError("private adapter failure")

        self.client = TestClient(TestServer(create_app(LIGHTS, TOKEN, sender=sender, library=LIBRARY)))
        await self.client.start_server()
        self.headers = {"Authorization": "Bearer " + TOKEN}

    async def asyncTearDown(self):
        await self.client.close()

    async def request(self, method, path, **kwargs):
        headers = {**self.headers, **kwargs.pop("headers", {})}
        response = await self.client.request(method, "/api/v1" + path, headers=headers, **kwargs)
        return response.status, await response.json()

    async def terminal(self, op_id):
        for _ in range(100):
            _, result = await self.request("GET", "/operations/" + op_id)
            if result["status"] in ("succeeded", "failed", "cancelled"):
                return result
            await asyncio.sleep(.01)
        self.fail("Operation did not finish")

    async def test_catalog_auth_and_capabilities(self):
        for kind in ("groups", "scenes"):
            code, result = await self.request("GET", "/" + kind)
            self.assertEqual(code, 200)
            self.assertEqual(result[kind], LIBRARY[kind])
            self.assertNotIn("fake-", json.dumps(result))
            code, _ = await self.request("GET", "/" + kind, headers={"Authorization": "invalid"})
            self.assertEqual(code, 401)
        _, caps = await self.request("GET", "/capabilities")
        self.assertTrue(caps["groups"] and caps["scenes"])
        self.assertEqual(self.sent, [])

    async def test_group_success_idempotency_and_key_namespace(self):
        headers = {"Idempotency-Key": "room-on"}
        code, first = await self.request("PATCH", "/groups/room/state", json={"power": True}, headers=headers)
        self.assertEqual(code, 202)
        _, repeat = await self.request("PATCH", "/groups/room/state", json={"power": True}, headers=headers)
        self.assertEqual(first["operation_id"], repeat["operation_id"])
        result = await self.terminal(first["operation_id"])
        self.assertEqual(result["status"], "succeeded")
        self.assertEqual(result["target_type"], "group")
        self.assertEqual({m["target_id"] for m in result["members"]}, {"desk", "sofa"})
        self.assertTrue(all(m["confirmation"] == "simulated" for m in result["members"]))
        self.assertEqual(len(self.sent), 2)
        for path in ("/groups/all/state", "/lights/desk/state"):
            code, _ = await self.request("PATCH", path, json={"power": True}, headers=headers)
            self.assertEqual(code, 409)

    async def test_invalid_member_prevents_every_write(self):
        code, _ = await self.request("PATCH", "/groups/all/state", json={"power": True, "rgb": [1, 2, 3], "brightness": 30})
        self.assertEqual(code, 422)
        code, _ = await self.request("POST", "/groups/all/effects/native", json={"effect": 137, "speed": 35, "brightness": 50})
        self.assertEqual(code, 422)
        for body in (None, [], {"power": "yes"}, {"rgb": [1, 2, 3]}):
            code, _ = await self.request("PATCH", "/groups/room/state", data=json.dumps(body), headers={"Content-Type": "application/json"})
            self.assertEqual(code, 422)
        await asyncio.sleep(.01)
        self.assertEqual(self.sent, [])

    async def test_scene_partial_failure_no_retry_and_successful_state_preserved(self):
        self.broken.add("sofa")
        headers = {"Idempotency-Key": "evening"}
        _, accepted = await self.request("POST", "/scenes/evening/apply", json={}, headers=headers)
        result = await self.terminal(accepted["operation_id"])
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["error"], "partial_failure")
        self.assertEqual([m["status"] for m in result["members"]], ["succeeded", "failed"])
        self.assertNotIn("private", json.dumps(result))
        _, desk = await self.request("GET", "/lights/desk")
        _, sofa = await self.request("GET", "/lights/sofa")
        self.assertEqual(desk["last_sent"]["rgb"], [255, 190, 120])
        self.assertIsNone(sofa["last_sent"])
        self.broken.clear()
        _, repeat = await self.request("POST", "/scenes/evening/apply", json={}, headers=headers)
        self.assertEqual(repeat["operation_id"], accepted["operation_id"])
        self.assertEqual(len(self.sent), 2)

    async def test_controller_executes_scene_and_group_brightness(self):
        url = str(self.client.server.make_url("/api/v1"))
        result = await execute(url, TOKEN, {"scene": "evening", "type": "apply", "body": {}})
        self.assertEqual(result["status"], "succeeded")
        action = {"group": "room", "type": "state", "body": {"power": True, "rgb": [20, 50, 90]}}
        result = await execute(url, TOKEN, with_brightness(action, 65))
        self.assertEqual(result["status"], "succeeded")
        for light in ("desk", "sofa"):
            _, state = await self.request("GET", "/lights/" + light)
            self.assertEqual(state["last_sent"]["brightness"], 65)
            self.assertEqual(state["last_sent"]["rgb"], [20, 50, 90])

    async def test_bad_requests_and_missing_targets(self):
        for path in ("/scenes/unknown/apply", "/groups/unknown/effects/native"):
            code, _ = await self.request("POST", path, json={})
            self.assertEqual(code, 404)
        for body in ([], None, {"brightness": 50}):
            code, _ = await self.request("POST", "/scenes/evening/apply", data=json.dumps(body), headers={"Content-Type": "application/json"})
            self.assertEqual(code, 422)
        code, _ = await self.request("POST", "/scenes/evening/apply", data="{")
        self.assertEqual(code, 415)
        code, _ = await self.request("POST", "/scenes/evening/apply", data="{", headers={"Content-Type": "application/json"})
        self.assertEqual(code, 400)
        self.assertEqual(self.sent, [])

    async def test_real_controller_cli_reports_members(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "token.txt").write_text(TOKEN, encoding="utf-8")
            config = root / "controller.json"
            config.write_text(json.dumps({"hub_url": str(self.client.server.make_url("/api/v1")),
                "token_file": "token.txt", "actions": {"evening": {"scene": "evening", "type": "apply", "body": {}}}}), encoding="utf-8")
            self.broken.add("sofa")
            process = await asyncio.create_subprocess_exec(sys.executable, "-m", "ks_light.controller", "--config", str(config), "evening",
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
            stdout, stderr = await asyncio.wait_for(process.communicate(), 15)
            self.assertEqual(process.returncode, 1, stderr)
            self.assertEqual(json.loads(stdout)["error"], "partial_failure")
            self.assertEqual(len(json.loads(stdout)["members"]), 2)
            self.assertNotIn(TOKEN.encode(), stdout + stderr)


class BatchTests(unittest.IsolatedAsyncioTestCase):
    async def test_queue_capacity_rejects_all_members_without_adding_work(self):
        sent = []
        async def sender(light, packets): sent.append(light["id"])
        hub = Hub(LIGHTS, sender=sender, library=LIBRARY)
        hub.queue.max_pending = 1
        first = hub.submit("sofa", "state", {"power": True}, None)
        with self.assertRaises(APIError) as error:
            hub.submit_collection("group", "room", "state", {"power": False}, "busy")
        self.assertEqual(error.exception.code, "queue_full")
        self.assertEqual(set(hub.operations), {first})
        self.assertNotIn("busy", hub.keys)
        self.assertNotIn("desk", hub.queue.pending)
        await asyncio.gather(*list(hub.tasks))
        self.assertEqual(sent, ["sofa"])
        await hub.close()

    async def test_operation_capacity_rejects_without_writes(self):
        hub = Hub(LIGHTS, library=LIBRARY, limit=0)
        with self.assertRaises(APIError) as error:
            hub.submit_collection("scene", "evening", "apply", {}, None)
        self.assertEqual(error.exception.code, "operation_capacity")
        self.assertEqual(hub.queue.pending, {})
        await hub.close()

    async def test_slow_member_progress_and_shutdown(self):
        blocked = asyncio.Event()
        async def sender(light, packets):
            if light["id"] == "sofa": await blocked.wait()
        hub = Hub(LIGHTS, sender=sender, library=LIBRARY)
        op_id = hub.submit_collection("group", "room", "state", {"power": True}, None)
        for _ in range(50):
            if hub.operations[op_id]["members"][0]["status"] == "succeeded": break
            await asyncio.sleep(.01)
        op = hub.operations[op_id]
        self.assertEqual(op["status"], "queued")
        self.assertEqual(op["members"][0]["status"], "succeeded")
        await asyncio.wait_for(hub.close(), 1)
        self.assertEqual(op["status"], "failed")
        self.assertEqual(op["error"], "partial_failure")
        self.assertEqual(op["members"][1]["status"], "cancelled")
        self.assertFalse(hub.queue.workers)


class LibraryConfigTests(unittest.TestCase):
    def test_invalid_library_never_reaches_runtime(self):
        cases = []
        for mutate in [
            lambda d: d.update(version=True),
            lambda d: d["groups"][0].update(members=["desk", "desk"]),
            lambda d: d["groups"][0].update(members=["missing"]),
            lambda d: d["groups"].append(copy.deepcopy(d["groups"][0])),
            lambda d: d["scenes"][0]["actions"][1].update(light="desk"),
            lambda d: d["scenes"][0]["actions"][0].update(body={"power": True, "brightness": 30}),
            lambda d: d["scenes"][0]["actions"][1].update(light="ceiling"),
            lambda d: d["scenes"][0]["actions"][0].update(body={"power": "yes"}),
        ]:
            data = copy.deepcopy(LIBRARY); mutate(data); cases.append(data)
        for data in cases:
            with self.subTest(data=data), self.assertRaises(ValueError): Hub(LIGHTS, library=data)

    def test_library_copy_and_size_limit(self):
        data = copy.deepcopy(LIBRARY)
        hub = Hub(LIGHTS, library=data)
        data["groups"][0]["members"].clear()
        self.assertEqual(hub.groups["room"]["members"], ["desk", "sofa"])
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "library.json"
            path.write_text(json.dumps(LIBRARY), encoding="utf-8")
            self.assertEqual(load_library(path), LIBRARY)
            path.write_bytes(b" " * 262145)
            with self.assertRaises(ValueError): load_library(path)

    def test_controller_config_targets_and_scene_override_rejection(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "token.txt").write_text(TOKEN, encoding="utf-8")
            data = {"hub_url": "http://127.0.0.1:8765/api/v1", "token_file": "token.txt", "actions": {}}
            path = root / "controller.json"
            for action in [{"scene": "evening", "type": "apply", "body": {}},
                           {"group": "room", "type": "state", "body": {"power": False}}]:
                data["actions"] = {"test": action}
                path.write_text(json.dumps(data), encoding="utf-8")
                self.assertEqual(load_config(path)[3]["test"], action)
            for action in [{"scene": "evening", "type": "state", "body": {}},
                           {"light": "desk", "group": "room", "type": "state", "body": {}},
                           {"scene": "evening", "type": "apply", "body": {"power": True}}]:
                data["actions"] = {"test": action}
                path.write_text(json.dumps(data), encoding="utf-8")
                with self.assertRaises(ValueError): load_config(path)
            with self.assertRaises(ControllerError):
                with_brightness({"scene": "evening", "type": "apply", "body": {}}, 50)
