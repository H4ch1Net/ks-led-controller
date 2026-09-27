"""Home Assistant JSON MQTT bridge, sharing the hub's command queues."""
import asyncio
import json
import logging
import re
import ssl
import time
from pathlib import Path

import aiomqtt
from paho.mqtt.subscribeoptions import SubscribeOptions

from .api_errors import APIError, integer

LOG = logging.getLogger(__name__)


def topic_id(value):
    if not isinstance(value, str) or not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", value):
        raise ValueError("MQTT hub ID must use letters, numbers, underscores or hyphens")
    return value


class MQTTBridge:
    def __init__(self, hub, *, hostname, hub_id="local", port=1883, username=None,
                 password=None, tls=False, ca_file=None, manifest=None, client_factory=None):
        self.hub = hub
        self.hub_id = topic_id(hub_id)
        if not hostname or not integer(port, 1, 65535):
            raise ValueError("Invalid MQTT broker settings")
        if ca_file and not tls:
            raise ValueError("MQTT CA file requires TLS")
        self.root = f"ks_light/{self.hub_id}"
        self.manifest = Path(manifest or f".ks_light_mqtt_{self.hub_id}.json")
        self.client_factory = client_factory or aiomqtt.Client
        self.options = dict(hostname=hostname, port=port, username=username, password=password,
                            identifier=f"kslight-{self.hub_id}", protocol=aiomqtt.ProtocolVersion.V5,
                            will=aiomqtt.Will(self.root + "/availability", "offline", qos=1, retain=True),
                            timeout=10, max_queued_incoming_messages=64,
                            max_queued_outgoing_messages=64, max_concurrent_outgoing_calls=8)
        if tls:
            self.options["tls_context"] = ssl.create_default_context(cafile=ca_file)
        self.states, self.operations = {}, {}
        self.force_refresh = False
        self.read_manifest()
        self.connection = {"state": "starting", "attempts": 0, "last_error": None, "retry_in_seconds": None}

    def status(self):
        return dict(self.connection)

    def targets(self):
        # Do not promote inherited/untested profiles through discovery.
        return {key: value for key, value in self.hub.lights.items() if value["prefix"] == "KS03~"}

    def config_topic(self, target):
        return f"homeassistant/light/kslight_{self.hub_id}_{target}/config"

    def discovery(self, target):
        light = self.hub.lights[target]
        device_id = f"kslight_{self.hub_id}_{target}"
        return {"name": light["name"] + (" (Simulation)" if self.hub.simulation else ""),
                "unique_id": device_id, "schema": "json", "supported_color_modes": ["rgb"],
                "brightness": True, "brightness_scale": 100, "effect": True,
                "effect_list": ["Purple breathing"], "optimistic": True, "qos": 0, "retain": False,
                "command_topic": f"{self.root}/devices/{target}/set",
                "state_topic": f"{self.root}/devices/{target}/state",
                "json_attributes_topic": f"{self.root}/devices/{target}/attributes",
                "availability_topic": self.root + "/availability",
                "device": {"identifiers": [device_id], "name": light["name"],
                           "manufacturer": "KS Light community controller", "model": light["prefix"]}}

    @staticmethod
    def command(body):
        if not isinstance(body, dict) or not body or set(body) - {"state", "color", "brightness", "effect", "speed", "request_id", "transition"}:
            raise APIError(422, "invalid_mqtt_command")
        key = body.get("request_id")
        if key is not None and (not isinstance(key, str) or not re.fullmatch(r"[a-zA-Z0-9_.:-]{1,96}", key)):
            raise APIError(422, "invalid_request_id")
        state = body.get("state")
        if "state" in body and state not in ("ON", "OFF"):
            raise APIError(422, "invalid_state")
        if "transition" in body and (type(body["transition"]) not in (int, float) or body["transition"] != 0):
            raise APIError(422, "unsupported_transition")
        if "brightness" in body and not integer(body["brightness"], 0, 100):
            raise APIError(422, "invalid_brightness")
        if state == "OFF":
            if set(body) - {"state", "request_id", "transition"}:
                raise APIError(422, "off_with_settings_not_supported")
            return "state", {"power": False}, key
        if "effect" in body:
            if body["effect"] != "Purple breathing" or "color" in body:
                raise APIError(422, "unsupported_effect")
            speed, brightness = body.get("speed", 35), body.get("brightness", 50)
            if not integer(speed, 0, 100) or not integer(brightness, 1, 100):
                raise APIError(422, "invalid_effect_settings")
            return "native", {"effect": 137, "speed": speed, "brightness": brightness}, key
        if "speed" in body:
            raise APIError(422, "speed_requires_effect")
        result = {"power": True}
        if "color" in body:
            color = body["color"]
            if not isinstance(color, dict) or set(color) != {"r", "g", "b"} or not all(integer(v, 0, 255) for v in color.values()):
                raise APIError(422, "invalid_color")
            result["rgb"] = [color[c] for c in "rgb"]
        if "brightness" in body:
            result["brightness"] = body["brightness"]
        if state != "ON" and not set(body) & {"color", "brightness"}:
            raise APIError(422, "empty_command")
        # HA color/brightness actions explicitly mean turn on, unlike raw HTTP PATCH.
        return "state", result, key

    async def publish_json(self, client, topic, value, *, retain=False):
        await client.publish(topic, json.dumps(value, separators=(",", ":")), qos=1, retain=retain)

    def read_manifest(self):
        if not self.manifest.exists():
            return set()
        previous = json.loads(self.manifest.read_text(encoding="utf-8"))
        if (not isinstance(previous, list) or len(previous) > 64
                or any(not isinstance(v, str) or not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", v) for v in previous)):
            raise ValueError("Invalid MQTT discovery manifest; preserve and inspect the file")
        return set(previous)

    async def announce(self, client):
        current = set(self.targets())
        for target in self.read_manifest() - current:
            await client.publish(self.config_topic(target), b"", qos=1, retain=True)
            for suffix in ("state", "attributes"):
                await client.publish(f"{self.root}/devices/{target}/{suffix}", b"", qos=1, retain=True)
        for target in current:
            await self.publish_json(client, self.config_topic(target), self.discovery(target), retain=True)
        self.manifest.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.manifest.with_suffix(".tmp")
        temporary.write_text(json.dumps(sorted(current)), encoding="utf-8")
        temporary.replace(self.manifest)
        self.states.clear()
        self.operations.clear()
        await self.sync(client)
        await client.publish(self.root + "/availability", "online", qos=1, retain=True)
        self.connection.update(state="online", last_error=None, retry_in_seconds=None)

    async def handle(self, client, message):
        topic = str(message.topic)
        if topic == "homeassistant/status":
            if message.payload == b"online":
                self.force_refresh = True
            return
        parts = topic.split("/")
        if len(parts) != 5 or topic != f"{self.root}/devices/{parts[3]}/set":
            return
        target = parts[3]
        if target not in self.targets():
            return
        try:
            if message.retain:
                raise APIError(422, "retained_command_rejected")
            if len(message.payload) > 16384:
                raise APIError(413, "command_too_large")
            try:
                body = json.loads(message.payload)
            except (ValueError, UnicodeError):
                raise APIError(400, "invalid_json")
            action, value, request_id = self.command(body)
            # Reserve a namespace distinct from ordinary HTTP retry keys.
            key = None if request_id is None else "mqtt:" + request_id
            op_id = self.hub.submit(target, action, value, key)
            result = {"operation_id": op_id, "status": self.hub.operations[op_id]["status"], "request_id": request_id}
        except APIError as error:
            result = {"status": "rejected", "error": error.code}
        await self.publish_json(client, f"{self.root}/devices/{target}/result", result)

    async def sync(self, client):
        self.hub.prune()
        for target in self.targets():
            state = self.hub.last_sent.get(target, {})
            rendered = {"state": None if "power" not in state else ("ON" if state["power"] else "OFF"), "color_mode": "rgb"}
            if "rgb" in state:
                rendered["color"] = dict(zip("rgb", state["rgb"]))
            if "brightness" in state:
                rendered["brightness"] = state["brightness"]
            rendered["effect"] = "Purple breathing" if state.get("native_effect") == 137 else None
            signature = json.dumps(rendered, sort_keys=True)
            if self.states.get(target) != signature:
                await self.publish_json(client, f"{self.root}/devices/{target}/state", rendered, retain=True)
                await self.publish_json(client, f"{self.root}/devices/{target}/attributes",
                    {"confirmation": "simulated" if self.hub.simulation else "unconfirmed", "state_source": "last_sent",
                     "availability_scope": "hub_bridge", "hub_instance": self.hub.instance}, retain=True)
                self.states[target] = signature
        self.operations = {key: value for key, value in self.operations.items() if key in self.hub.operations}
        for op_id, op in list(self.hub.operations.items()):
            if self.operations.get(op_id) != op["status"]:
                await self.publish_json(client, f"{self.root}/operations/{op_id}", {k: v for k, v in op.items() if k != "completed"})
                self.operations[op_id] = op["status"]

    async def serve(self, client):
        # MQTT 5 preserves live RETAIN flags and skips stale retained deliveries on subscription.
        await client.subscribe(self.root + "/devices/+/set", options=SubscribeOptions(qos=0, retainAsPublished=True, retainHandling=2))
        await client.subscribe("homeassistant/status", qos=0)
        async def read():
            async for message in client.messages:
                await self.handle(client, message)
        async def sync():
            while True:
                if self.force_refresh:
                    self.force_refresh = False
                    await self.announce(client)
                else:
                    await self.sync(client)
                await asyncio.sleep(.5)
        tasks = []
        try:
            await self.announce(client)
            tasks = [asyncio.create_task(read()), asyncio.create_task(sync())]
            done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                task.result()
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            try:
                await asyncio.wait_for(client.publish(self.root + "/availability", "offline", qos=1, retain=True), 2)
            except (aiomqtt.MqttError, asyncio.TimeoutError):
                pass

    async def run(self):
        delay = 2
        try:
            while True:
                self.connection.update(state="connecting", retry_in_seconds=None)
                self.connection["attempts"] += 1
                started = time.monotonic()
                try:
                    async with self.client_factory(**self.options) as client:
                        await self.serve(client)
                    error_code = "connection_closed"
                except (aiomqtt.MqttError, OSError, ValueError) as error:
                    # Expose categories only: exception text may include broker details.
                    error_code = "invalid_manifest" if isinstance(error, ValueError) else "connection_failed"
                if time.monotonic() - started >= 30:
                    delay = 2
                self.connection.update(state="retrying", last_error=error_code, retry_in_seconds=delay)
                LOG.warning("MQTT unavailable; reconnecting in %s seconds", delay)
                await asyncio.sleep(delay)
                delay = min(delay * 2, 60)
        except asyncio.CancelledError:
            self.connection.update(state="stopped", retry_in_seconds=None)
            raise
        except Exception:
            self.connection.update(state="failed", last_error="internal_error", retry_in_seconds=None)
            LOG.error("MQTT bridge stopped after an unexpected internal error")
            raise
