"""Actual service processes: simulator state survives a forced stop without replay."""
import asyncio
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest
import aiohttp
from ks_light.controller import execute


class ServicePersistenceTests(unittest.IsolatedAsyncioTestCase):
    async def test_process_restart_restores_last_sent_without_replaying(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            token="private-persistence-smoke-token-000000000"
            (root/"token.txt").write_text(token)
            (root/"lights.json").write_text(json.dumps({"lights":[
                {"id":"desk","name":"Desk","prefix":"KS03~","address":"simulated-only"}]}))
            with socket.socket() as reservation:
                reservation.bind(("127.0.0.1",0));port=reservation.getsockname()[1]
            (root/"hub.json").write_text(json.dumps({"version":1,"mode":"simulation","port":port,
                "lights_file":"lights.json","token_file":"token.txt","runtime_dir":"runtime","persist_state":True}))
            base=f"http://127.0.0.1:{port}/api/v1"
            process=None
            async with aiohttp.ClientSession(headers={"Authorization":"Bearer "+token},
                    timeout=aiohttp.ClientTimeout(total=1)) as client:
                async def request(path):
                    async with client.get(base+path) as response:
                        self.assertEqual(response.status,200)
                        return await response.json()
                async def start():
                    nonlocal process
                    process=await asyncio.create_subprocess_exec(sys.executable,"-m","ks_light.service",
                        "--config",str(root/"hub.json"),stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.PIPE,
                        creationflags=subprocess.CREATE_NO_WINDOW if sys.platform=="win32" else 0)
                    for _ in range(100):
                        if process.returncode is not None:self.fail("Test service stopped during startup")
                        try:return await request("/health")
                        except (aiohttp.ClientError,asyncio.TimeoutError):await asyncio.sleep(.05)
                    self.fail("Test service did not start")
                async def stop():
                    if process and process.returncode is None:
                        process.terminate()
                        try:await asyncio.wait_for(process.communicate(),5)
                        except asyncio.TimeoutError:
                            process.kill();await process.communicate()
                try:
                    before=await start()
                    result=await execute(base,token,{"light":"desk","type":"state",
                        "body":{"power":True,"rgb":[123,45,67],"brightness":42}})
                    self.assertEqual(result["status"],"succeeded")
                    await stop()
                    after=await start()
                    self.assertNotEqual(before["instance"],after["instance"])
                    light=await request("/lights/desk")
                    self.assertTrue(light["restored"])
                    self.assertEqual(light["last_sent"]["brightness"],42)
                    self.assertEqual(light["confirmation"],"simulated")
                    snapshot=await request("/lights")
                    self.assertEqual(snapshot["cursor"],0)
                    self.assertNotIn(token,(root/"runtime"/"hub.log").read_text())
                finally:await stop()
