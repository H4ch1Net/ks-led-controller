import asyncio
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from ks_light.hub import Hub, APIError
from ks_light.mqtt_bridge import MQTTBridge

LIGHTS = [{"id":"desk", "name":"Desk", "prefix":"KS03~", "address":"fake"}]
class Client:
    def __init__(self): self.sent=[]; self.subscriptions=[]
    async def publish(self, topic, payload, **options): self.sent.append((topic,payload,options))
    async def subscribe(self, topic, **options): self.subscriptions.append((topic,options))
    def last(self, suffix):
        return json.loads(next(p for t,p,o in reversed(self.sent) if t.endswith(suffix)))

class MQTTTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp=TemporaryDirectory(); self.writes=[]
        async def sender(light, packets): self.writes.append(packets)
        self.hub=Hub(LIGHTS,sender=sender)
        self.bridge=MQTTBridge(self.hub,hostname='localhost',manifest=Path(self.tmp.name)/'manifest.json')
        self.client=Client()
    async def asyncTearDown(self):
        await self.hub.close(); self.tmp.cleanup()
    async def send(self, body, retain=False):
        payload=body if isinstance(body,bytes) else json.dumps(body).encode()
        await self.bridge.handle(self.client,SimpleNamespace(topic='ks_light/local/devices/desk/set',payload=payload,retain=retain))
        await asyncio.gather(*self.hub.tasks)
        return self.client.last('/result')
    async def test_reconnect_backoff_and_status_do_not_expose_secrets(self):
        from unittest.mock import patch
        import aiomqtt
        delays=[]
        snapshots=[]
        class BrokenConnection:
            async def __aenter__(self): raise aiomqtt.MqttError('secret password')
            async def __aexit__(self,*args): pass
        self.bridge.client_factory=lambda **kwargs: BrokenConnection()
        async def sleep(delay):
            delays.append(delay); snapshots.append(self.bridge.status())
            if len(delays)==3: raise asyncio.CancelledError()
        with patch('ks_light.mqtt_bridge.asyncio.sleep',sleep):
            with self.assertRaises(asyncio.CancelledError): await self.bridge.run()
        self.assertEqual(delays,[2,4,8])
        self.assertEqual([s['attempts'] for s in snapshots],[1,2,3])
        self.assertTrue(all(s['state']=='retrying' for s in snapshots))
        self.assertNotIn('secret',str(snapshots))
        self.assertEqual(self.bridge.status()['state'],'stopped')

    async def test_short_lived_connections_keep_backoff(self):
        from unittest.mock import patch
        import aiomqtt
        delays=[]
        class BriefConnection:
            async def __aenter__(self): return self
            async def __aexit__(self,*args): pass
        self.bridge.client_factory=lambda **kwargs: BriefConnection()
        async def disconnected(client): raise aiomqtt.MqttError('dropped after connect')
        self.bridge.serve=disconnected
        async def sleep(delay):
            delays.append(delay)
            if len(delays)==3: raise asyncio.CancelledError()
        with patch('ks_light.mqtt_bridge.asyncio.sleep',sleep):
            with self.assertRaises(asyncio.CancelledError): await self.bridge.run()
        self.assertEqual(delays,[2,4,8])

    async def test_unexpected_failure_is_visible(self):
        class BrokenConnection:
            async def __aenter__(self): raise RuntimeError('private detail')
            async def __aexit__(self,*args): pass
        self.bridge.client_factory=lambda **kwargs: BrokenConnection()
        with self.assertRaises(RuntimeError): await self.bridge.run()
        self.assertEqual(self.bridge.status()['state'],'failed')
        self.assertEqual(self.bridge.status()['last_error'],'internal_error')
        self.assertNotIn('private',str(self.bridge.status()))

    async def test_discovery_unknown_and_simulation(self):
        await self.bridge.announce(self.client)
        self.assertEqual(self.bridge.status()['state'],'online')
        config=self.client.last('/config')
        self.assertIn('Simulation',config['name']); self.assertTrue(config['optimistic'])
        self.assertEqual(config['brightness_scale'],100)
        self.assertIsNone(self.client.last('/state')['state'])
        self.assertEqual(self.client.last('/attributes')['confirmation'],'simulated')
    async def test_color_delivery_and_state(self):
        result=await self.send({'state':'ON','color':{'r':239,'g':66,'b':255},'brightness':35})
        self.assertIn('operation_id',result)
        await self.bridge.sync(self.client)
        self.assertEqual(self.client.last('/state')['color'],{'r':239,'g':66,'b':255})
        self.assertEqual(self.writes[0][-1].hex(),'5a0001ef42ff002300a5')
    async def test_native_and_off(self):
        await self.send({'effect':'Purple breathing','speed':35,'brightness':50})
        self.assertEqual(self.writes[0][-1].hex(),'5c0089233200c5')
        await self.bridge.sync(self.client)
        self.assertEqual(self.client.last('/state')['effect'],'Purple breathing')
        await self.send({'state':'OFF'})
        await self.bridge.sync(self.client)
        self.assertEqual(self.client.last('/state')['state'],'OFF')
    async def test_brightness_preserves_native_effect_and_retry(self):
        await self.send({'effect':'Purple breathing','speed':42,'brightness':50})
        body={'brightness':30,'request_id':'dim-1'}
        first=await self.send(body)
        second=await self.send(body)
        self.assertEqual(first['operation_id'],second['operation_id'])
        self.assertEqual(len(self.writes),2)
        self.assertEqual(self.writes[-1][-1].hex(),'5c00892a1e00c5')
        self.assertEqual(self.hub.last_sent['desk']['native_effect'],137)
        self.assertEqual(self.hub.last_sent['desk']['speed'],42)
        await self.bridge.sync(self.client)
        self.assertEqual(self.client.last('/state')['brightness'],30)
        self.assertEqual(self.client.last('/state')['effect'],'Purple breathing')
        zero=await self.send({'brightness':0})
        self.assertEqual(zero['status'],'rejected')

    async def test_retained_and_invalid_commands_do_not_write(self):
        result=await self.send({'state':'ON'},retain=True)
        self.assertEqual(result['error'],'retained_command_rejected')
        for body in [b'bad',b'X'*16385,{'state':None},{'brightness':True},{'transition':1,'state':'ON'}, {'state':'OFF','brightness':10}, {'effect':'strobe'}, {'color':{'r':256,'g':0,'b':0}}]:
            result=await self.send(body)
            self.assertEqual(result['status'],'rejected')
        self.assertEqual(self.writes,[])
    async def test_hub_errors_are_caught(self):
        result=await self.send({'brightness':40})
        self.assertEqual(result['status'],'rejected')
        self.assertEqual(self.writes,[])
    async def test_idempotent_commands_and_conflict(self):
        a=await self.send({'state':'ON','request_id':'press-1'})
        b=await self.send({'state':'ON','request_id':'press-1'})
        self.assertEqual(a['operation_id'],b['operation_id']); self.assertEqual(len(self.writes),1)
        c=await self.send({'state':'OFF','request_id':'press-1'})
        self.assertEqual(c['status'],'rejected')
    async def test_cleanup_only_previously_owned_discovery(self):
        self.bridge.manifest.write_text('["old"]')
        await self.bridge.announce(self.client)
        removed=[t for t,p,o in self.client.sent if p==b'']
        self.assertEqual(len(removed),3)
        self.assertIn('homeassistant/light/kslight_local_old/config',removed)
        self.assertEqual(json.loads(self.bridge.manifest.read_text()),['desk'])
    async def test_birth_and_no_redundant_state(self):
        await self.bridge.announce(self.client); count=len(self.client.sent)
        await self.bridge.sync(self.client); self.assertEqual(count,len(self.client.sent))
        await self.bridge.handle(self.client,SimpleNamespace(topic='homeassistant/status',payload=b'online',retain=False))
        self.assertTrue(self.bridge.force_refresh)
    async def test_manifest_validation_before_connection(self):
        self.bridge.manifest.write_text('["bad/topic"]')
        with self.assertRaises(ValueError):
            MQTTBridge(self.hub,hostname='localhost',manifest=self.bridge.manifest)
    async def test_subscription_retention_and_shutdown(self):
        async def messages():
            await asyncio.Event().wait()
            yield None
        self.client.messages=messages()
        task=asyncio.create_task(self.bridge.serve(self.client))
        await asyncio.sleep(.02); task.cancel()
        with self.assertRaises(asyncio.CancelledError): await task
        opts=self.client.subscriptions[0][1]['options']
        self.assertTrue(opts.retainAsPublished); self.assertEqual(opts.retainHandling,2)
        self.assertEqual(self.client.sent[-1][1],'offline')
    async def test_failed_delivery_invalidates_state(self):
        await self.send({'color':{'r':10,'g':20,'b':30}})
        async def fail(light,packets): raise OSError('test failure')
        self.hub.sender=fail
        await self.send({'state':'OFF'})
        await self.bridge.sync(self.client)
        self.assertIsNone(self.client.last('/state')['state'])

if __name__=='__main__': unittest.main()
