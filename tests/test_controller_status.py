import asyncio
import json
from pathlib import Path
import tempfile
import unittest

from aiohttp.test_utils import TestServer
from ks_light.controller import execute
from ks_light.controller_status import action_labels, light_label, watch
from ks_light.hub import create_app


class StatusTests(unittest.IsolatedAsyncioTestCase):
    def test_state_evidence_and_collection_summaries(self):
        first = {"id": "desk", "last_sent": {"power": True, "rgb": [255, 0, 128], "brightness": 50}}
        self.assertEqual(light_label(first), "Sent #FF0080 50%")
        self.assertEqual(light_label({**first, "restored": True}), "Saved #FF0080 50%")
        self.assertEqual(light_label({**first, "confirmation": "simulated"}), "Sim #FF0080 50%")
        self.assertEqual(light_label({"last_sent": None}), "Unknown")
        second = {"id": "other", "last_sent": {"power": False}}
        actions = {"room": {"group": "room"}, "scene": {"scene": "reading"}, "missing": {"light": "lost"}}
        labels = action_labels(actions, [first, second], [{"id": "room", "members": ["desk", "other"]}],
                               [{"id": "reading", "actions": [{"light": "desk"}]}])
        self.assertEqual(labels, {"room": "Mixed", "scene": "Sent #FF0080 50%", "missing": "Unavailable"})

    async def test_watch_observes_external_commands_without_submitting(self):
        token = "test-status-monitor-token-00000000000"
        writes = []
        async def sender(light, packets): writes.append(packets)
        server = TestServer(create_app([{"id": "desk", "name": "Desk", "prefix": "KS03~", "address": "fake"}], token, sender=sender))
        await server.start_server()
        queue = asyncio.Queue()
        try:
            with tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                (root / "token").write_text(token, encoding="utf-8")
                action = {"light": "desk", "type": "state", "body": {"power": True}}
                config = root / "controller.json"
                config.write_text(json.dumps({"hub_url": str(server.make_url("/api/v1")), "token_file": "token", "actions": {"on": action}}), encoding="utf-8")
                task = asyncio.create_task(watch(config, queue.put_nowait))
                try:
                    initial = await asyncio.wait_for(queue.get(), 3)
                    self.assertEqual(initial["states"], {"on": "Unknown"})
                    self.assertEqual(writes, [])
                    await execute(str(server.make_url("/api/v1")), token, action)
                    changed = await asyncio.wait_for(queue.get(), 4)
                    self.assertEqual(changed["states"], {"on": "Sim On"})
                    self.assertEqual(len(writes), 1)
                finally:
                    task.cancel()
                    with self.assertRaises(asyncio.CancelledError): await task
        finally:
            await server.close()
