import asyncio
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from aiohttp.test_utils import TestClient, TestServer
from ks_light.hub import create_app


class LibraryEditTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.path = Path(self.folder.name) / 'library.json'
        self.original = {'version': 1, 'groups': [], 'scenes': []}
        self.path.write_text(json.dumps(self.original))
        self.updated = {'version': 1, 'groups': [{'id': 'room', 'name': 'Room', 'members': ['desk']}], 'scenes': []}
        self.token = 'test-library-edit-token-' + 'x' * 32
        self.release = asyncio.Event(); self.started = asyncio.Event()
        self.writes = []
        async def sender(light, packets):
            self.writes.append(light['id']); self.started.set(); await self.release.wait()
        self.client = TestClient(TestServer(create_app(
            [{'id': 'desk', 'name': 'Desk', 'prefix': 'KS03~', 'address': 'fake'}], self.token,
            sender=sender, library_file=self.path)))
        await self.client.start_server()

    async def asyncTearDown(self):
        self.release.set(); await self.client.close(); self.folder.cleanup()

    async def request(self, method='GET', body=None, etag=None, path='library'):
        headers = {'Authorization': 'Bearer ' + self.token}
        if etag: headers['If-Match'] = etag
        return await self.client.request(method, '/api/v1/' + path, headers=headers, json=body)

    async def test_edit_persists_without_delivery_and_stale_editor_is_rejected(self):
        before = await self.request(); etag = before.headers['ETag']
        response = await self.request('PUT', self.updated, etag)
        self.assertEqual(response.status, 200)
        self.assertNotEqual(response.headers['ETag'], etag)
        self.assertEqual(json.loads(self.path.read_text()), self.updated)
        self.assertEqual(self.writes, [])
        response = await self.request('PUT', self.original, etag)
        self.assertEqual(response.status, 412)
        response = await self.request(path='groups')
        self.assertEqual(len((await response.json())['groups']), 1)

    async def test_invalid_or_failed_write_keeps_previous_library(self):
        etag = (await self.request()).headers['ETag']
        for body in [None, {'version': 1, 'groups': [{'id': 'room', 'name': 'Room', 'members': ['missing']}], 'scenes': []}]:
            response = await self.request('PUT', body, etag)
            self.assertIn(response.status, [415, 422])
        with patch('ks_light.hub.save_json', side_effect=OSError('disk unavailable')):
            response = await self.request('PUT', self.updated, etag)
            self.assertEqual(response.status, 503)
        self.assertEqual(json.loads(self.path.read_text()), self.original)
        self.assertEqual(await (await self.request()).json(), self.original)
        self.assertEqual(self.writes, [])

    async def test_inflight_commands_and_external_file_changes_block_edits(self):
        etag = (await self.request()).headers['ETag']
        response = await self.request('PATCH', {'power': True}, path='lights/desk/state')
        self.assertEqual(response.status, 202)
        await asyncio.wait_for(self.started.wait(), 1)
        response = await self.request('PUT', self.updated, etag)
        self.assertEqual(response.status, 409)
        self.release.set()
        await asyncio.sleep(.03)
        self.path.write_text(json.dumps(self.updated))
        response = await self.request('PUT', self.original, etag)
        self.assertEqual(response.status, 409)
        self.assertEqual(await (await self.request()).json(), self.original)
