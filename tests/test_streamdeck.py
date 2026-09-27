import json
from pathlib import Path
import tempfile
import unittest
from aiohttp.test_utils import TestServer
from ks_light.hub import create_app
from ks_light.streamdeck import run, command
from ks_light.controller import ControllerError


class StreamDeckTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.writes=[]
        async def sender(light, packets):self.writes.append(packets)
        self.server=TestServer(create_app([{'id':'desk','name':'Desk','prefix':'KS03~','address':'private'}],
            'streamdeck-test-token-000000000000',sender=sender,
            library={'version':1,'groups':[],'scenes':[{'id':'night','name':'Night','actions':[{'light':'desk','type':'state','body':{'power':False}}]}]}))
        await self.server.start_server()
        self.folder=tempfile.TemporaryDirectory();root=Path(self.folder.name)
        (root/'token').write_text('streamdeck-test-token-000000000000')
        self.config=root/'controller.json'
        self.config.write_text(json.dumps({'hub_url':str(self.server.make_url('/api/v1')),'token_file':'token',
            'actions':{'on':{'light':'desk','type':'state','body':{'power':True}}}}))
    async def asyncTearDown(self):
        await self.server.close();self.folder.cleanup()
    async def test_catalog_is_read_only_and_omits_private_fields(self):
        result=await run(self.config)
        self.assertEqual(result['lights'][0]['name'],'Desk')
        self.assertEqual(result['scenes'],[{'id':'night','name':'Night'}])
        self.assertNotIn('private',json.dumps(result));self.assertNotIn('token',json.dumps(result))
        self.assertEqual(self.writes,[])
    async def test_unknown_toggle_rejects_then_scene_seeds_explicit_power(self):
        with self.assertRaises(ControllerError):await run(self.config,{'type':'power','light':'desk','power':'toggle'})
        self.assertEqual(self.writes,[])
        await run(self.config,{'type':'scene','scene':'night'})
        await run(self.config,{'type':'power','light':'desk','power':'toggle'})
        self.assertEqual(self.writes[-1],[bytes.fromhex('5bf001b5')])
    async def test_invalid_control_values_do_not_write(self):
        for spec in [
            {'type':'color','light':'desk','rgb':[256,0,0],'brightness':50},
            {'type':'effect','light':'desk','effect':139,'speed':35,'brightness':50},
            {'type':'brightness','light':'../desk','brightness':50},
            {'type':'power','light':'desk','power':'toggle','extra':True},
        ]:
            with self.assertRaises(ValueError):await run(self.config,spec)
        self.assertEqual(self.writes,[])
