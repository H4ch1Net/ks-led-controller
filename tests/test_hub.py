import asyncio
import unittest
from aiohttp.test_utils import TestClient, TestServer
from ks_light.hub import APIError, Hub, create_app, validate_lights

TOKEN = "test-only-operator-token-00000000000000"
LIGHTS = [
    {"id": "desk", "name": "Desk", "prefix": "KS03~", "address": "fake-a"},
    {"id": "sofa", "name": "Sofa", "prefix": "KS03~", "address": "fake-b"},
    {"id": "ceiling", "name": "Ceiling", "prefix": "KS03-", "address": "fake-c"},
]


class HubHTTPTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.sent = []
        self.fail = set()
        async def sender(light, packets):
            await asyncio.sleep(0)
            if light["id"] in self.fail:
                raise RuntimeError("internal transport detail")
            self.sent.append((light["id"], packets))
        self.client = TestClient(TestServer(create_app(LIGHTS, TOKEN, sender=sender)))
        await self.client.start_server()
        self.headers = {"Authorization": "Bearer " + TOKEN}

    async def asyncTearDown(self):
        await self.client.close()

    async def request(self, method, path, **kwargs):
        headers = {**self.headers, **kwargs.pop("headers", {})}
        response = await self.client.request(method, "/api/v1" + path, headers=headers, **kwargs)
        return response.status, await response.json()

    async def terminal(self, op):
        for _ in range(40):
            _, result = await self.request("GET", "/operations/" + op)
            if result["status"] != "queued":
                return result
            await asyncio.sleep(.01)
        self.fail("operation never completed")

    async def test_health_reports_optional_mqtt_status(self):
        code, health = await self.request('GET','/health')
        self.assertEqual(code,200)
        self.assertEqual(health['mqtt']['state'],'disabled')
        self.assertEqual(health['status'],'ok')
        from unittest.mock import patch
        class UnavailableBridge:
            def __init__(self,*args,**kwargs): pass
            def status(self): return {'state':'retrying','attempts':2,'last_error':'connection_failed','retry_in_seconds':4}
            async def run(self): await asyncio.Event().wait()
        with patch('ks_light.mqtt_bridge.MQTTBridge',UnavailableBridge):
            client=TestClient(TestServer(create_app(LIGHTS,TOKEN,mqtt={'hostname':'unused'})))
            await client.start_server()
            try:
                response=await client.get('/api/v1/health',headers=self.headers)
                health=await response.json()
                self.assertEqual(health['status'],'degraded')
                self.assertEqual(health['mqtt']['state'],'retrying')
                self.assertEqual(health['mqtt']['retry_in_seconds'],4)
            finally: await client.close()

    async def test_authentication_and_no_browser_origin(self):
        response = await self.client.get("/api/v1/lights")
        self.assertEqual(response.status, 401)
        code, _ = await self.request("PATCH", "/lights/desk/state", json={"power": True}, headers={"Authorization": "Bearer wrong"})
        self.assertEqual(code, 401)
        code, _ = await self.request("GET", "/lights", headers={"Origin": "https://example.invalid"})
        self.assertEqual(code, 403)
        self.assertEqual(self.sent, [])

    async def test_rgb_delivery_percent_scale_and_events(self):
        code, op = await self.request("PATCH", "/lights/desk/state", json={"power": True, "rgb": [239, 66, 255], "brightness": 35})
        self.assertEqual(code, 202)
        result = await self.terminal(op["operation_id"])
        self.assertEqual(result["status"], "succeeded")
        self.assertEqual(result["confirmation"], "simulated")
        self.assertEqual(self.sent[0][1][-1].hex(), "5a0001ef42ff002300a5")
        _, light = await self.request("GET", "/lights/desk")
        self.assertEqual(light["last_sent"]["brightness"], 35)
        self.assertNotIn("address", light)
        _, events = await self.request("GET", "/events?after=0")
        self.assertEqual([e["type"] for e in events["events"]], ["operation.updated", "operation.updated", "light.updated"])

    async def test_idempotency_retry_and_conflict(self):
        headers = {"Idempotency-Key": "test-action-1"}
        _, first = await self.request("PATCH", "/lights/desk/state", json={"power": True}, headers=headers)
        _, second = await self.request("PATCH", "/lights/desk/state", json={"power": True}, headers=headers)
        self.assertEqual(first["operation_id"], second["operation_id"])
        await self.terminal(first["operation_id"])
        self.assertEqual(len(self.sent), 1)
        code, _ = await self.request("PATCH", "/lights/desk/state", json={"power": False}, headers=headers)
        self.assertEqual(code, 409)

    async def test_reject_unsupported_or_invalid_commands_before_writes(self):
        bodies = [{"rgb": [1, 2, 3]}, {"power": "yes"}, {"power": True, "rgb": [True, 0, 0]},
                  {"power": True, "brightness": 35}, {"power": True, "transition_ms": 500},
                  {"power": False, "rgb": [1, 2, 3]}, {"power": True, "secret": 1}]
        for body in bodies:
            code, _ = await self.request("PATCH", "/lights/desk/state", json=body)
            self.assertEqual(code, 422, body)
        code, _ = await self.request("PATCH", "/lights/ceiling/state", json={"power": True, "rgb": [1, 2, 3], "brightness": 35})
        self.assertEqual(code, 422)
        code, _ = await self.request("PATCH", "/lights/missing/state", json={"power": True})
        self.assertEqual(code, 404)
        self.assertEqual(self.sent, [])

    async def test_native_effect_and_off(self):
        _, op = await self.request("POST", "/lights/desk/effects/native", json={"effect": 137, "speed": 35, "brightness": 50})
        await self.terminal(op["operation_id"])
        self.assertEqual(self.sent[-1][1][-1].hex(), "5c0089233200c5")
        _, op = await self.request("PATCH", "/lights/desk/state", json={"power": False})
        await self.terminal(op["operation_id"])
        self.assertEqual(self.sent[-1][1], [bytes.fromhex("5b0f01b5")])

    async def test_failure_isolated_and_internal_detail_not_exposed(self):
        self.fail.add("desk")
        _, bad = await self.request("PATCH", "/lights/desk/state", json={"power": True})
        _, good = await self.request("PATCH", "/lights/sofa/state", json={"power": True})
        result = await self.terminal(bad["operation_id"])
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["error"], "write_failed")
        self.assertNotIn("internal", str(result))
        self.assertEqual((await self.terminal(good["operation_id"]))["status"], "succeeded")

    async def test_malformed_and_oversized_json(self):
        code, _ = await self.request("PATCH", "/lights/desk/state", data="{broken", headers={"Content-Type": "application/json"})
        self.assertEqual(code, 400)
        code, _ = await self.request("PATCH", "/lights/desk/state", data="x" * 17000, headers={"Content-Type": "application/json"})
        self.assertEqual(code, 413)
        code, _ = await self.request("GET", "/events?after=999")
        self.assertEqual(code, 409)
        code, snapshot = await self.request("GET", "/lights")
        self.assertEqual(code, 200)
        self.assertEqual(snapshot["cursor"], 0)
        code, error = await self.request("GET", "/events?after=0&instance=previous-process")
        self.assertEqual(code, 409)
        self.assertEqual(error["error"], "resync_required")
        code, _ = await self.request("GET", "/events?after=0&instance=" + snapshot["instance"])
        self.assertEqual(code, 200)

    async def test_expired_event_cursor_recovers_from_snapshot(self):
        for _ in range(172):
            _, op = await self.request("PATCH", "/lights/desk/state", json={"power": True})
            await self.terminal(op["operation_id"])
        code, error = await self.request("GET", "/events?after=0")
        self.assertEqual(code, 409)
        self.assertEqual(error["error"], "resync_required")
        _, snapshot = await self.request("GET", "/lights")
        code, result = await self.request("GET", "/events?after=" + str(snapshot["cursor"]))
        self.assertEqual(code, 200)
        self.assertEqual(result["events"], [])


class HubQueueTests(unittest.IsolatedAsyncioTestCase):
    async def test_retention_capacity_and_replay_window(self):
        hub = Hub(LIGHTS, limit=1, retention=600)
        try:
            first = hub.submit("desk", "state", {"power": True}, "a")
            with self.assertRaises(APIError) as caught:
                hub.submit("desk", "state", {"power": False}, "b")
            self.assertEqual(caught.exception.status, 429)
            await asyncio.gather(*list(hub.tasks))
            self.assertEqual(hub.submit("desk", "state", {"power": True}, "a"), first)
            hub.operations[first]["completed"] -= 601
            second = hub.submit("desk", "state", {"power": True}, "a")
            self.assertNotEqual(first, second)
        finally:
            await hub.close()

    async def test_shutdown_cancels_active_and_pending_work(self):
        entered = asyncio.Event()
        cleaned = asyncio.Event()
        async def sender(light, packets):
            entered.set()
            try:
                await asyncio.Event().wait()
            finally:
                cleaned.set()
        hub = Hub(LIGHTS, sender=sender)
        first = hub.submit("desk", "state", {"power": True}, None)
        await entered.wait()
        second = hub.submit("desk", "state", {"power": False}, None)
        await hub.close()
        self.assertTrue(cleaned.is_set())
        self.assertEqual(hub.operations[first]["status"], "cancelled")
        self.assertEqual(hub.operations[second]["status"], "cancelled")

    async def test_brightness_patch_keeps_last_color_and_power_off_does_not_erase_it(self):
        hub = Hub(LIGHTS)
        try:
            hub.submit("desk", "state", {"power": True, "rgb": [12, 34, 56], "brightness": 80}, None)
            await asyncio.gather(*list(hub.tasks))
            hub.submit("desk", "state", {"power": False}, None)
            await asyncio.gather(*list(hub.tasks))
            hub.submit("desk", "state", {"power": True, "brightness": 25}, None)
            await asyncio.gather(*list(hub.tasks))
            self.assertEqual(hub.last_sent["desk"], {"rgb": [12, 34, 56], "brightness": 25, "power": True})
        finally:
            await hub.close()

    def test_duplicate_physical_targets_and_short_tokens_rejected(self):
        with self.assertRaises(ValueError):
            validate_lights([LIGHTS[0], {**LIGHTS[0], "id": "duplicate"}])
        with self.assertRaises(ValueError):
            create_app(LIGHTS, "weak")


class DashboardTests(unittest.IsolatedAsyncioTestCase):
    async def client(self, **kwargs):
        client = TestClient(TestServer(create_app(LIGHTS, TOKEN, **kwargs)))
        await client.start_server()
        self.addAsyncCleanup(client.close)
        return client

    async def test_static_files_need_no_token_and_carry_security_headers(self):
        client = await self.client()
        for path, kind in [("/", "text/html"), ("/app.js", "text/javascript"), ("/app.css", "text/css"), ("/icon.svg", "image/svg+xml")]:
            response = await client.get(path)
            self.assertEqual(response.status, 200, path)
            self.assertEqual(response.content_type, kind)
            self.assertIn("frame-ancestors 'none'", response.headers["Content-Security-Policy"])
        response = await client.get("/api/v1/lights")
        self.assertEqual(response.status, 401)

    async def test_same_origin_loopback_browser_requests_are_allowed(self):
        client = await self.client()
        auth = {"Authorization": "Bearer " + TOKEN}
        origin = f"http://{client.host}:{client.port}"
        response = await client.patch("/api/v1/lights/desk/state", json={"power": False},
                                      headers={**auth, "Origin": origin, "Host": f"{client.host}:{client.port}"})
        self.assertEqual(response.status, 202)
        for foreign in ["http://evil.example", f"http://localhost:{client.port + 1}", "null"]:
            response = await client.get("/api/v1/lights", headers={**auth, "Origin": foreign})
            self.assertEqual(response.status, 403, foreign)
        rebound = await client.get("/api/v1/lights", headers={**auth, "Origin": "http://evil.example:80", "Host": "evil.example:80"})
        self.assertEqual(rebound.status, 403)

    async def test_dashboard_can_be_disabled(self):
        client = await self.client(dashboard=False)
        self.assertEqual((await client.get("/")).status, 404)
        response = await client.get("/api/v1/lights", headers={"Authorization": "Bearer " + TOKEN,
                                                               "Origin": f"http://{client.host}:{client.port}"})
        self.assertEqual(response.status, 403)

    async def test_capabilities_list_native_effects(self):
        client = await self.client()
        response = await client.get("/api/v1/capabilities", headers={"Authorization": "Bearer " + TOKEN})
        effects = (await response.json())["native_effects"]
        self.assertEqual(len(effects), 9)
        self.assertIn({"id": 137, "name": "Purple breathing"}, effects)
