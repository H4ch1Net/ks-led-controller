import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import contextlib
import io
import asyncio

from aiohttp.test_utils import TestClient, TestServer
from ks_light.credentials import load_credentials
from ks_light.credentials import main, authenticate
from ks_light.hub import create_app


class CredentialTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'credentials.json'
        self.admin, self.control, self.read = ('test-only-' + c * 40 for c in 'acr')
        self.records = [
            {'id': 'controller', 'sha256': hashlib.sha256(self.control.encode()).hexdigest(), 'scope': 'control', 'lights': ['desk']},
            {'id': 'viewer', 'sha256': hashlib.sha256(self.read.encode()).hexdigest(), 'scope': 'read', 'lights': ['desk']},
        ]
        self.save(self.records)
        self.writes = []
        async def sender(light, packets): self.writes.append(light['id'])
        lights = [{'id': target, 'name': target, 'prefix': 'KS03~', 'address': target} for target in ['desk', 'sofa']]
        library = {'version': 1, 'groups': [{'id': 'room', 'name': 'Room', 'members': ['desk', 'sofa']}],
                   'scenes': [{'id': 'night', 'name': 'Night', 'actions': [
                       {'light': target, 'type': 'state', 'body': {'power': False}} for target in ['desk', 'sofa']]}]}
        self.client = TestClient(TestServer(create_app(lights, self.admin, sender=sender, library=library, credentials_file=self.path)))
        await self.client.start_server()

    async def asyncTearDown(self):
        await self.client.close()
        self.temp.cleanup()

    def save(self, records):
        self.path.write_text(json.dumps({'version': 1, 'credentials': records}), encoding='utf-8')

    async def request(self, method, path, token, **kwargs):
        return await self.client.request(method, '/api/v1/' + path, headers={'Authorization': 'Bearer ' + token}, **kwargs)

    async def test_filter_catalog_and_block_unauthorized_commands_before_delivery(self):
        response = await self.request('GET', 'lights', self.control)
        self.assertEqual([light['id'] for light in (await response.json())['lights']], ['desk'])
        for path in ['groups', 'scenes']:
            response = await self.request('GET', path, self.control)
            self.assertEqual((await response.json())[path], [])
        for method, path in [('PATCH', 'lights/sofa/state'), ('PATCH', 'groups/room/state'), ('POST', 'scenes/night/apply')]:
            response = await self.request(method, path, self.control, json={'power': False})
            self.assertEqual(response.status, 403)
        response = await self.request('PATCH', 'lights/desk/state', self.read, json={'power': True})
        self.assertEqual(response.status, 403)
        self.assertEqual(self.writes, [])
        response = await self.request('PATCH', 'lights/desk/state', self.control, json={'power': True})
        self.assertEqual(response.status, 202)

    async def test_operation_and_events_do_not_expose_other_lights(self):
        response = await self.request('PATCH', 'lights/sofa/state', self.admin, json={'power': True})
        operation = (await response.json())['operation_id']
        response = await self.request('GET', 'operations/' + operation, self.read)
        self.assertEqual(response.status, 403)
        response = await self.request('GET', 'events', self.read)
        self.assertEqual((await response.json())['events'], [])
        response = await self.request('PATCH', 'groups/room/state', self.admin, json={'power': False})
        operation = (await response.json())['operation_id']
        response = await self.request('GET', 'operations/' + operation, self.control)
        self.assertEqual(response.status, 403)

    async def test_revocation_reload_and_fail_closed_do_not_disable_operator(self):
        self.save([])
        response = await self.request('GET', 'health', self.control)
        self.assertEqual(response.status, 401)
        self.path.write_text('broken', encoding='utf-8')
        response = await self.request('GET', 'health', self.control)
        self.assertEqual(response.status, 503)
        response = await self.request('GET', 'health', self.admin)
        self.assertEqual(response.status, 200)
        self.assertEqual(self.writes, [])

    async def test_schema_rejects_duplicate_or_unknown_targets(self):
        for records in [self.records * 2, [{**self.records[0], 'lights': ['missing']}],
                        [{**self.records[0], 'scope': 'admin'}], [{**self.records[0], 'sha256': self.control}]]:
            self.save(records)
            with self.assertRaises(ValueError): load_credentials(self.path, ['desk', 'sofa'])

    async def test_cli_creates_private_token_without_printing_and_revokes(self):
        catalog = Path(self.temp.name) / 'lights.json'
        catalog.write_text(json.dumps({'lights': [{'id': 'desk', 'name': 'Desk', 'prefix': 'KS03~', 'address': 'fake'}]}))
        token_file = Path(self.temp.name) / 'new-token'
        base = ['credentials', '--file', str(self.path), '--catalog', str(catalog), '--id', 'new']
        self.save([])
        output = io.StringIO()
        with patch('sys.argv', base + ['--lights', 'desk', '--token-out', str(token_file)]), contextlib.redirect_stdout(output):
            main()
        token = token_file.read_text().strip()
        self.assertNotIn(token, output.getvalue())
        self.assertNotIn(token, self.path.read_text())
        self.assertEqual(authenticate(self.path, token, ['desk'])['id'], 'new')
        with patch('sys.argv', base + ['--revoke']), contextlib.redirect_stdout(output):
            main()
        self.assertIsNone(authenticate(self.path, token, ['desk']))

    async def test_event_long_poll_wakes_on_delivery_and_rejects_unbounded_wait(self):
        pending = asyncio.create_task(self.request('GET', 'events?after=0&wait=2', self.read))
        await asyncio.sleep(.05)
        self.assertFalse(pending.done())
        response = await self.request('PATCH', 'lights/desk/state', self.control, json={'power': True})
        self.assertEqual(response.status, 202)
        response = await asyncio.wait_for(pending, 1)
        self.assertTrue((await response.json())['events'])
        response = await self.request('GET', 'events?wait=26', self.read)
        self.assertEqual(response.status, 400)
