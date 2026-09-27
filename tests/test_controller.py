import asyncio
import json
import ssl
from pathlib import Path
import tempfile
import sys
import unittest
from aiohttp import web
from aiohttp.test_utils import TestServer
from ks_light.controller import ControllerError, execute, load_config, with_brightness
from ks_light.hub import create_app

TOKEN = "test-only-controller-token-000000000000"
LIGHTS = [{"id": "desk", "name": "Desk", "prefix": "KS03~", "address": "fake"}]

class ControllerTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.writes = []
        self.fail = False
        async def sender(light, packets):
            self.writes.append(packets)
            if self.fail: raise RuntimeError("private internal failure")
        self.server = TestServer(create_app(LIGHTS, TOKEN, sender=sender))
        await self.server.start_server()
        self.url = str(self.server.make_url("/api/v1"))
        self.action = {"light": "desk", "type": "state", "body": {"power": True}}
    async def asyncTearDown(self):
        await self.server.close()
    async def test_waits_for_delivery_and_reports_simulation(self):
        result = await execute(self.url, TOKEN, self.action)
        self.assertEqual(result["status"], "succeeded")
        self.assertEqual(result["confirmation"], "simulated")
        self.assertEqual(len(self.writes), 1)
    async def test_failed_delivery_does_not_retry(self):
        self.fail = True
        result = await execute(self.url, TOKEN, self.action)
        self.assertEqual(result["status"], "failed")
        self.assertEqual(len(self.writes), 1)
    async def test_auth_rejection_and_invalid_command_never_write(self):
        with self.assertRaisesRegex(ControllerError, "401"):
            await execute(self.url, "wrong", self.action)
        with self.assertRaises(ControllerError):
            await execute(self.url, TOKEN, {**self.action, "body": {"power": "yes"}})
        self.assertEqual(self.writes, [])
    async def test_native_effect_delivery(self):
        result = await execute(self.url, TOKEN, {"light": "desk", "type": "native",
            "body": {"effect": 137, "speed": 35, "brightness": 50}})
        self.assertEqual(result["status"], "succeeded")
        self.assertEqual(len(self.writes), 1)
    async def test_deadline_does_not_resubmit(self):
        calls = []
        async def submit(request):
            calls.append(1)
            return web.json_response({"operation_id": "slow"})
        async def poll(request):
            return web.json_response({"operation_id": "slow", "status": "queued"})
        app = web.Application()
        app.router.add_patch("/lights/desk/state", submit)
        app.router.add_get("/operations/slow", poll)
        server = TestServer(app)
        await server.start_server()
        # Windows certificate-store loading can exceed the old 200 ms deadline.
        # Keep TLS setup outside the deadline so this tests an accepted command
        # timing out while polling, rather than timing out before submission.
        context = ssl.create_default_context()
        try:
            with self.assertRaisesRegex(ControllerError, "not retried"):
                await execute(str(server.make_url("")).rstrip("/"), TOKEN, self.action,
                              timeout=1, context=context)
            self.assertEqual(len(calls), 1)
        finally: await server.close()

    async def test_real_cli_process_and_exit_codes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "token.txt").write_text(TOKEN)
            config = root / "controller.json"
            config.write_text(json.dumps({"hub_url": self.url, "token_file": "token.txt",
                "actions": {"on": self.action}}))
            async def invoke(*args):
                process = await asyncio.create_subprocess_exec(sys.executable, "-m", "ks_light.controller",
                    "--config", str(config), *args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
                stdout, stderr = await asyncio.wait_for(process.communicate(), 10)
                self.assertNotIn(TOKEN.encode(), stdout + stderr)
                return process.returncode, stdout, stderr
            code, output, _ = await invoke()
            self.assertEqual(code, 0)
            self.assertEqual(output.strip(), b"on")
            self.assertEqual(self.writes, [])
            code, output, _ = await invoke("on")
            self.assertEqual(code, 0)
            self.assertEqual(json.loads(output)["status"], "succeeded")
            self.fail = True
            code, output, _ = await invoke("on")
            self.assertEqual(code, 1)
            self.assertEqual(json.loads(output)["status"], "failed")
            code, _, _ = await invoke("missing")
            self.assertEqual(code, 2)

class ConfigTests(unittest.TestCase):
    def test_relative_token_and_remote_http_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "token.txt").write_text(TOKEN)
            data = {"hub_url": "http://127.0.0.1:8765/api/v1", "token_file": "token.txt",
                "actions": {"on": {"light": "desk", "type": "state", "body": {"power": True}}}}
            path = root / "controls.json"
            path.write_text(json.dumps(data))
            self.assertEqual(load_config(path)[1], TOKEN)
            for url in ("http://192.168.1.1:8765/api/v1", "https://user:secret@example.com/api/v1", "https://example.com/api/v1?x=y"):
                data["hub_url"] = url
                path.write_text(json.dumps(data))
                with self.assertRaises(ValueError): load_config(path)


class BrightnessTests(unittest.TestCase):
    def test_override_copies_color_and_effect_without_mutating_saved_action(self):
        for action in [
            {"light":"desk","type":"state","body":{"power":True,"rgb":[255,0,0],"brightness":20}},
            {"light":"desk","type":"native","body":{"effect":137,"speed":35,"brightness":20}}]:
            changed = with_brightness(action, 55)
            self.assertEqual(changed["body"]["brightness"], 55)
            self.assertEqual(action["body"]["brightness"], 20)
            self.assertEqual(changed["light"], action["light"])
    def test_no_guessing_color_or_accepting_out_of_range_levels(self):
        base={"light":"desk","type":"state","body":{"power":True,"rgb":[1,2,3]}}
        for value in [0,101,True,1.5,"50"]:
            with self.assertRaises(ControllerError): with_brightness(base,value)
        for body in [{"power":True},{"power":False,"rgb":[1,2,3]}]:
            with self.assertRaises(ControllerError): with_brightness({**base,"body":body},50)
