"""Launch the packaged backend against a simulated Stream Deck host and real hub/client."""
import asyncio
import json
from pathlib import Path
import shutil
import sys
import tempfile
from aiohttp import web
from aiohttp.test_utils import TestServer
from ks_light.hub import create_app

async def main():
    repo=Path.cwd()
    plugin=repo/"apps/streamdeck/dev.kslight.controller.sdPlugin"
    writes=[]
    broken=set()
    async def sender(light, packets):
        writes.append(packets)
        if light["id"] in broken: raise OSError("simulated offline member")
    app=create_app([{"id":"desk","name":"Desk","prefix":"KS03~","address":"simulation"},
        {"id":"sofa","name":"Sofa","prefix":"KS03~","address":"simulation-sofa"}],
        "simulated-streamdeck-token-000000000000",sender=sender,library={"version":1,
            "groups":[{"id":"room","name":"Room","members":["desk","sofa"]}],
            "scenes":[{"id":"night","name":"Night","actions":[
                {"light":"desk","type":"state","body":{"power":False}},
                {"light":"sofa","type":"state","body":{"power":False}}]}]})
    connected=asyncio.get_running_loop().create_future()
    received=asyncio.Queue()
    shared_settings={}
    async def websocket(request):
        ws=web.WebSocketResponse();await ws.prepare(request);connected.set_result(ws)
        async for msg in ws:
            if msg.type==web.WSMsgType.TEXT:
                data=json.loads(msg.data)
                if data["event"]=="getGlobalSettings":
                    await ws.send_json({"event":"didReceiveGlobalSettings","context":"test-plugin",
                        "id":data.get("id"),"payload":{"settings":shared_settings}})
                await received.put(data)
        return ws
    host=web.Application();host.router.add_get("/",websocket)
    host_server=TestServer(host);await host_server.start_server()
    server=TestServer(app);await server.start_server()
    process=None
    try:
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            (root/"token.txt").write_text("simulated-streamdeck-token-000000000000")
            config=root/"controller.json"
            config.write_text(json.dumps({"hub_url":str(server.make_url("/api/v1")),"token_file":"token.txt",
                "actions":{"desk-on":{"light":"desk","type":"state","body":{"power":True}},"reading":{"light":"desk","type":"state","body":{"power":True,"rgb":[255,190,120],"brightness":20}}}}))
            config_data=json.loads(config.read_text())
            config_data["actions"].update({"room-on":{"group":"room","type":"state","body":{"power":True}},
                "night":{"scene":"night","type":"apply","body":{}}})
            config.write_text(json.dumps(config_data),encoding="utf-8")
            shared_settings["connection"]={"python":sys.executable,"repository":str(repo),"config":str(config)}
            info={"application":{"version":"7.1.0","platform":"windows","platformVersion":"10","language":"en"},
                "devices":[{"id":"test-device","name":"Test","size":{"columns":3,"rows":2},"type":0}],"plugin":{"version":"0.1.0.0","uuid":"dev.kslight.controller"}}
            process=await asyncio.create_subprocess_exec(shutil.which("node"),str(plugin/"bin/plugin.js"),
                "-port",str(host_server.port),"-pluginUUID","test-plugin","-registerEvent","registerPlugin","-info",json.dumps(info),
                cwd=plugin,stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.PIPE)
            ws=await asyncio.wait_for(connected,10)
            async def until(event):
                while True:
                    msg=await asyncio.wait_for(received.get(),15)
                    if msg["event"]==event:return msg
            assert (await until("registerPlugin"))["uuid"]=="test-plugin"
            settings={"python":sys.executable,"repository":str(repo),"config":str(config),"action":"desk-on"}
            async def send(event):
                await ws.send_json({"action":"dev.kslight.controller.run","event":event,"context":"test-key","device":"test-device",
                    "payload":{"settings":settings,"coordinates":{"column":0,"row":0},"controller":"Keypad","state":0,"isInMultiAction":False}})
            await send("willAppear");await until("setTitle")
            await send("keyDown");await until("showOk")
            assert len(writes)==1
            settings["action"]="missing"
            await send("didReceiveSettings");await until("setTitle")
            await send("keyDown");await until("showAlert")
            assert len(writes)==1
            settings={"useShared":True,"action":"desk-on"}
            await send("didReceiveSettings");await until("setTitle")
            await send("keyDown");await until("showOk")
            assert len(writes)==2
            await ws.send_json({"event":"didReceiveGlobalSettings","context":"test-plugin",
                "payload":{"settings":{"connection":{}}}})
            assert (await until("setTitle"))["payload"]["title"]=="Set up"
            await send("keyDown");await until("showAlert")
            assert len(writes)==2
            settings={"python":sys.executable,"repository":str(repo),"config":str(config),"action":"desk-on"}
            await send("didReceiveSettings");await until("setTitle")
            await send("keyDown");await until("showOk")
            assert len(writes)==3
            dial_settings={**settings,"actions":["desk-on","missing"]}
            async def dial_event(event, **payload):
                await ws.send_json({"action":"dev.kslight.controller.dial","event":event,"context":"test-dial","device":"test-device",
                    "payload":{"settings":dial_settings,"coordinates":{"column":0,"row":0},"controller":"Encoder",**payload}})
            await dial_event("willAppear");await until("setFeedback")
            await dial_event("dialRotate",ticks=1,pressed=False)
            assert (await until("setFeedback"))["payload"]["value"]=="missing"
            assert len(writes)==3
            await dial_event("dialDown");await until("showAlert");assert len(writes)==3
            await dial_event("dialRotate",ticks=-1,pressed=False);await until("setFeedback")
            await dial_event("dialDown")
            while (await until("setFeedback"))["payload"]["title"]!="Simulated":pass
            assert len(writes)==4
            continuous = False
            async def brightness_event(event, **payload):
                await ws.send_json({"action":"dev.kslight.controller.brightness","event":event,"context":"brightness-dial","device":"test-device",
                    "payload":{"settings":{**settings,"action":"reading","continuous":continuous},"coordinates":{"column":1,"row":0},"controller":"Encoder",**payload}})
            await brightness_event("willAppear");await until("setFeedback")
            await brightness_event("dialRotate",ticks=1,pressed=False)
            assert (await until("setFeedback"))["payload"]["value"]=="55%"
            assert len(writes)==4
            await brightness_event("dialDown")
            while (await until("setFeedback"))["payload"]["title"]!="Simulated":pass
            assert len(writes)==5
            import aiohttp
            async with aiohttp.ClientSession() as client:
                async with client.get(server.make_url("/api/v1/lights/desk"),headers={"Authorization":"Bearer simulated-streamdeck-token-000000000000"}) as response:
                    assert (await response.json())["last_sent"]["brightness"]==55
            assert json.loads(config.read_text())["actions"]["reading"]["body"]["brightness"]==20
            continuous = True
            await brightness_event('didReceiveSettings');await until('setFeedback')
            await brightness_event('dialRotate', ticks=2, pressed=False)
            while (await until('setFeedback'))['payload']['title'] != 'Simulated': pass
            assert len(writes) == 6
            settings={**settings,"action":"room-on"}
            await send("didReceiveSettings");await until("setTitle")
            await send("keyDown");await until("showOk")
            assert len(writes)==8
            broken.add("sofa")
            settings={**settings,"action":"night"}
            await send("didReceiveSettings");await until("setTitle")
            await send("keyDown");await until("showAlert")
            assert len(writes)==10
            print("PASS: group key, partial scene failure, SDK keys/shared setup, action dial, press brightness and continuous brightness; saved config unchanged; no physical BLE.")
    finally:
        if process and process.returncode is None:
            process.terminate();await process.communicate()
        await server.close()
        await host_server.close()

if __name__=="__main__": asyncio.run(main())
