import asyncio
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from aiohttp.test_utils import TestClient, TestServer
from ks_light.hub import Hub, create_app
from ks_light.hub_state import StateStore

LIGHTS=[{"id":"desk","name":"Desk","address":"fake","prefix":"KS03~"}]
STATE={"power":True,"rgb":[200,100,20],"brightness":40}
TOKEN="state-test-token-only-00000000000000000"


class SnapshotTests(unittest.TestCase):
    def test_mode_and_device_identity_never_cross_restore(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/"state.json"
            store=StateStore(path,{"desk":LIGHTS[0]},True)
            store.save({"desk":STATE},set())
            self.assertEqual(store.load(),{"desk":STATE})
            self.assertEqual(StateStore(path,{"desk":LIGHTS[0]},False).load(),{})
            self.assertEqual(StateStore(path,{"desk":{**LIGHTS[0],"address":"different"}},True).load(),{})
            self.assertEqual(StateStore(path,{},True).load(),{})
            self.assertEqual(list(Path(folder).glob("*.tmp")),[])
    def test_corrupt_and_oversized_files_fail_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/"state.json";store=StateStore(path,{"desk":LIGHTS[0]},True)
            self.assertEqual(store.load(),{});self.assertFalse(path.exists())
            for raw in ["broken", "x"*65537, json.dumps({"version":True,"mode":"simulation","lights":{}}),
                json.dumps({"version":1,"mode":"simulation","lights":{"desk":{"address":"fake","prefix":"KS03~","state":{"power":"on"}}}})]:
                path.write_text(raw)
                with self.assertRaises(ValueError):store.load()


class PersistenceTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp=tempfile.TemporaryDirectory();self.path=Path(self.temp.name)/"state.json";self.writes=[]
        async def sender(light,packets):self.writes.append(packets)
        self.sender=sender
        self.hubs=[]
    def hub(self, **kwargs):
        hub=Hub(LIGHTS,state_file=self.path,sender=kwargs.pop("sender",self.sender),**kwargs)
        self.hubs.append(hub);return hub
    async def asyncTearDown(self):
        for hub in self.hubs:await hub.close()
        self.temp.cleanup()
    async def test_restart_restores_metadata_without_commands_or_operation_replay(self):
        first=self.hub();await first._deliver("desk",("state",STATE))
        second=self.hub()
        self.assertEqual(len(self.writes),1)
        self.assertEqual(second.light("desk")["last_sent"],STATE)
        self.assertTrue(second.light("desk")["restored"])
        self.assertEqual(second.light("desk")["confirmation"],"simulated")
        self.assertEqual(second.operations,{})
        self.assertNotEqual(first.instance,second.instance)
        await second._deliver("desk",("state",{"power":True,"brightness":55}))
        self.assertEqual(second.last_sent["desk"]["brightness"],55)
        self.assertFalse(second.light("desk")["restored"])
    async def test_native_effect_survives_restart_as_unconfirmed_last_sent(self):
        first=self.hub(simulation=False)
        await first._deliver("desk",("native",{"effect":137,"speed":35,"brightness":40}))
        second=self.hub(simulation=False)
        self.assertEqual(second.light("desk")["confirmation"],"unconfirmed")
        self.assertEqual(second.last_sent["desk"]["native_effect"],137)
        await second._deliver("desk",("state",{"power":True,"brightness":60}))
        self.assertEqual(self.writes[-1][-1][4],60)
        self.assertEqual(second.last_sent["desk"]["native_effect"],137)

    async def test_snapshot_is_unknown_during_write_and_after_failed_delivery(self):
        first=self.hub();await first._deliver("desk",("state",STATE))
        async def failed(light,packets):
            self.assertEqual(first.state_store.load(),{})
            raise OSError("private transport error")
        first.sender=failed
        with self.assertRaises(OSError):await first._deliver("desk",("state",{"power":False}))
        self.assertEqual(first.last_sent,{})
        self.assertEqual(self.hub().last_sent,{})
    async def test_storage_failure_before_send_prevents_command(self):
        hub=self.hub()
        with patch.object(hub.state_store,"save",side_effect=OSError("private path")):
            with self.assertRaises(OSError):await hub._deliver("desk",("state",STATE))
        self.assertEqual(self.writes,[]);self.assertTrue(hub.persistence_error)
        self.assertEqual(hub.pending_state,set())
    async def test_storage_failure_after_send_does_not_retry_or_restore_stale_state(self):
        hub=self.hub();original=hub.state_store.save;calls=0
        def failing_save(states,pending):
            nonlocal calls
            calls+=1
            if calls==2:raise OSError("disk full")
            original(states,pending)
        with patch.object(hub.state_store,"save",side_effect=failing_save):
            await hub._deliver("desk",("state",STATE))
        self.assertEqual(len(self.writes),1)
        self.assertEqual(hub.last_sent["desk"],STATE)
        self.assertTrue(hub.persistence_error)
        self.assertEqual(self.hub().last_sent,{})
        await hub._deliver("desk",("state",{"power":False}))
        self.assertFalse(hub.persistence_error)
    async def test_other_light_completion_does_not_restore_an_inflight_target(self):
        lights=LIGHTS+[{"id":"other","name":"Other","address":"other-fake","prefix":"KS03~"}]
        hub=Hub(lights,state_file=self.path,sender=self.sender);self.hubs.append(hub)
        await hub._deliver("desk",("state",STATE));await hub._deliver("other",("state",STATE))
        started,release=asyncio.Event(),asyncio.Event()
        async def sender(light,packets):
            if light["id"]=="other":
                started.set();await release.wait()
        hub.sender=sender
        pending=asyncio.create_task(hub._deliver("other",("state",{"power":False})))
        try:
            await started.wait()
            await hub._deliver("desk",("state",{"power":True,"brightness":80}))
            self.assertEqual(set(hub.state_store.load()),{"desk"})
        finally:
            release.set();await pending
        self.assertEqual(set(hub.state_store.load()),{"desk","other"})

    async def test_health_and_capabilities_expose_optional_persistence(self):
        client=TestClient(TestServer(create_app(LIGHTS,TOKEN,state_file=self.path)))
        await client.start_server()
        try:
            headers={"Authorization":"Bearer "+TOKEN}
            response=await client.get("/api/v1/health",headers=headers)
            self.assertEqual((await response.json())["persistence"],{"enabled":True,"status":"ok"})
            response=await client.get("/api/v1/capabilities",headers=headers)
            self.assertTrue((await response.json())["durable_last_sent"])
        finally:await client.close()
