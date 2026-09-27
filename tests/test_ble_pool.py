import asyncio
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, Mock
from ks_light.ble_pool import BleSessionPool


class PoolTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.clients=[]
        def factory(address):
            char=SimpleNamespace(properties=['write-without-response','write'])
            client=SimpleNamespace(is_connected=True,connect=AsyncMock(),disconnect=AsyncMock(),write_gatt_char=AsyncMock(),services=Mock())
            client.services.get_service.return_value.get_characteristic.return_value=char
            self.clients.append(client);return client
        self.pool=BleSessionPool(client_factory=factory,idle_seconds=.02,settle_delay=0,command_delay=0,final_delay=0)
    async def asyncTearDown(self):await self.pool.close()
    async def test_reuses_live_session_then_releases_on_idle(self):
        await self.pool.write('one','afd0','afd1',[b'on',b'color'])
        await self.pool.write('one','afd0','afd1',[b'off'])
        self.assertEqual(len(self.clients),1)
        self.clients[0].connect.assert_awaited_once()
        self.assertEqual(self.clients[0].write_gatt_char.await_count,3)
        await asyncio.wait_for(self.pool.sessions['one'].idle_task,1)
        self.clients[0].disconnect.assert_awaited_once()
        self.assertEqual(self.pool.sessions,{})
    async def test_write_error_discards_session_without_mode_fallback_or_retry(self):
        await self.pool.write('one','afd0','afd1',[b'on'])
        client=self.clients[0];client.write_gatt_char.reset_mock()
        client.write_gatt_char.side_effect=OSError('uncertain delivery')
        with self.assertRaises(OSError):await self.pool.write('one','afd0','afd1',[b'color'])
        client.write_gatt_char.assert_awaited_once();client.disconnect.assert_awaited_once()
        self.assertEqual(self.pool.sessions,{})
        await self.pool.write('one','afd0','afd1',[b'new deliberate command'])
        self.assertEqual(len(self.clients),2)
    async def test_idle_eviction_limits_connections(self):
        self.pool.idle_seconds=30
        for target in ['one','two','three']:await self.pool.write(target,'afd0','afd1',[b'on'])
        self.assertEqual(len(self.pool.sessions),2)
        self.clients[0].disconnect.assert_awaited_once()
    async def test_cancel_cleans_up_without_replay(self):
        entered=asyncio.Event()
        await self.pool.write('one','afd0','afd1',[b'on'])
        async def blocked(*args,**kwargs):entered.set();await asyncio.sleep(10)
        client=self.clients[0];client.write_gatt_char.reset_mock();client.write_gatt_char.side_effect=blocked
        task=asyncio.create_task(self.pool.write('one','afd0','afd1',[b'color']))
        await entered.wait();task.cancel()
        with self.assertRaises(asyncio.CancelledError):await task
        client.write_gatt_char.assert_awaited_once();client.disconnect.assert_awaited_once()
