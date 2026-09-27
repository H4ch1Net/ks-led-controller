import asyncio
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from aiohttp.test_utils import TestClient, TestServer
from ks_light.hub import create_app
from ks_light.hub_state import StateStore
from ks_light.protocol import color
from tests.test_hub import LIGHTS, TOKEN


class CalibrationEditTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.catalog = Path(self.folder.name) / 'lights.json'
        self.state = Path(self.folder.name) / 'state.json'
        self.catalog.write_text(json.dumps({'lights': LIGHTS}), encoding='utf-8')
        self.writes = []
        async def sender(light, packets): self.writes.append(packets)
        self.client = TestClient(TestServer(create_app(LIGHTS, TOKEN, lights_file=self.catalog, state_file=self.state, sender=sender)))
        await self.client.start_server()

    async def asyncTearDown(self):
        await self.client.close(); self.folder.cleanup()

    async def request(self, method='GET', body=None, etag=None, suffix='calibration'):
        headers = {'Authorization': 'Bearer ' + TOKEN}
        if etag: headers['If-Match'] = etag
        return await self.client.request(method, '/api/v1/lights/desk' + ('/' + suffix if suffix else ''), json=body, headers=headers)

    async def test_save_invalidates_old_snapshot_and_next_color_uses_gains_once(self):
        await self.request('PATCH', {'power': True, 'rgb': [100, 100, 100], 'brightness': 50}, suffix='state')
        await asyncio.sleep(.03)
        old = await self.request(); etag = old.headers['ETag']
        updated = {'rgb_gains': [1, .3, .75], 'presets': {'My purple': [1, .3, .75]}}
        response = await self.request('PUT', updated, etag)
        self.assertEqual(response.status, 200)
        self.assertEqual(len(self.writes), 1)  # Saving sent nothing.
        light = await (await self.request(suffix='')).json()
        self.assertIsNone(light['last_sent'])
        saved = json.loads(self.catalog.read_text())['lights']
        self.assertEqual(saved[0]['calibration'], updated)
        self.assertEqual(StateStore(self.state, {x['id']: x for x in saved}, True).load(), {})
        self.assertEqual((await self.request('PUT', updated, etag)).status, 412)
        await self.request('PATCH', {'power': True, 'rgb': [100, 100, 100], 'brightness': 50}, suffix='state')
        await asyncio.sleep(.03)
        self.assertEqual(self.writes[-1][-1], color(100, 30, 75, 'floor', 50))

    async def test_invalid_import_or_failed_storage_keeps_previous_config(self):
        etag = (await self.request()).headers['ETag']
        before = self.catalog.read_bytes()
        for value in [{'rgb_gains': [True, 1, 1]}, {'rgb_gains': [1, 1, 1], 'presets': {'bad': [2, 1, 1]}}, {'rgb_gains': [1, 1, 1], 'order': 'BGR'}]:
            self.assertEqual((await self.request('PUT', value, etag)).status, 422)
        with patch('ks_light.hub.save_json', side_effect=OSError('disk full')):
            self.assertEqual((await self.request('PUT', {'rgb_gains': [.5, 1, 1]}, etag)).status, 503)
        self.assertEqual(self.catalog.read_bytes(), before)
        self.assertEqual(self.writes, [])
        self.assertEqual((await self.request()).headers['ETag'], etag)
