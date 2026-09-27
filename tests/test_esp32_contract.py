"""Validate the firmware's actual example payloads against the hub API."""
import asyncio
import json
from pathlib import Path
import re
import unittest

import aiohttp
from aiohttp.test_utils import TestServer
from ks_light.hub import create_app


class ESP32ContractTests(unittest.IsolatedAsyncioTestCase):
    async def test_firmware_actions_and_bounded_http10_operation_responses(self):
        source = (Path(__file__).resolve().parents[1] / "apps/esp32/src/main.cpp").read_text(encoding="utf-8")
        actions = re.findall(r'\{"([a-z-]+)", "(PATCH|POST)", "([^"]+)", R"\((.*?)\)"\}', source)
        self.assertEqual(len(actions), 4)
        token = "esp32-contract-test-token-0000000000"
        writes = []
        async def sender(light, packets):
            writes.append(packets)
        server = TestServer(create_app(
            [{"id": "desk", "name": "Desk", "prefix": "KS03~", "address": "fake"}],
            token, sender=sender))
        await server.start_server()
        async def body(response, expected):
            self.assertEqual(response.status, expected)
            self.assertIsNotNone(response.content_length)
            self.assertTrue(0 < response.content_length <= 2048)
            return await response.json()
        try:
            async with aiohttp.ClientSession(version=aiohttp.HttpVersion10,
                    headers={"Authorization": "Bearer " + token}) as client:
                for name, method, suffix, payload in actions:
                    with self.subTest(action=name):
                        async with client.request(method, server.make_url("/api/v1/lights/desk" + suffix),
                                json=json.loads(payload), headers={"Idempotency-Key": name}) as response:
                            submitted = await body(response, 202)
                        operation = submitted["operation_id"]
                        self.assertRegex(operation, r"^[a-zA-Z0-9_-]{1,128}$")
                        for _ in range(30):
                            async with client.get(server.make_url("/api/v1/operations/" + operation)) as response:
                                result = await body(response, 200)
                            self.assertEqual(result["operation_id"], operation)
                            if result["status"] != "queued":
                                break
                            await asyncio.sleep(.01)
                        self.assertEqual(result["status"], "succeeded")
                        self.assertEqual(result["confirmation"], "simulated")
                self.assertEqual(len(writes), 4)
        finally:
            await server.close()
