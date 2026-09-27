"""Local, authenticated hub API. Simulation is the command-line default."""
import argparse
import asyncio
from collections import deque
import hmac
import json
import os
import re
import secrets
import sys
import time

from aiohttp import web

from .api_errors import APIError, integer
from .profiles import DEVICE_UUIDS, DEVICE_MAPPINGS
from .protocol import color, power
from .queue import CommandQueue
from .transport import write_sequence
from .hub_state import StateStore
from .calibration import apply as calibrate_rgb, gains, valid_calibration, PRESETS
from .hub_library import load_library, validate_library
import copy
from .credentials import authenticate, load_credentials
from .config_io import revision, save_json, load_json


def validate_lights(lights):
    if not isinstance(lights, list) or not 1 <= len(lights) <= 64:
        raise ValueError("Configure 1-64 lights")
    result = {}
    addresses = set()
    for item in lights:
        required = {"id", "name", "prefix", "address"}
        if (not isinstance(item, dict) or not required <= set(item) or set(item) - required - {"calibration"}
                or not all(isinstance(item[k], str) for k in required)
                or not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", item["id"])
                or not 1 <= len(item["name"]) <= 80 or not 1 <= len(item["address"]) <= 128
                or item["prefix"] not in DEVICE_UUIDS
                or item["id"] in result or item["address"].casefold() in addresses):
            raise ValueError("Invalid or duplicate light configuration")
        if "calibration" in item:
            balance = item["calibration"]
            if not valid_calibration(balance) or item["prefix"] not in DEVICE_MAPPINGS:
                raise ValueError("Calibration requires supported RGB and three gains from 0 to 1")
        result[item["id"]] = copy.deepcopy(item)
        addresses.add(item["address"].casefold())
    return result


class Hub:
    def __init__(self, lights, *, simulation=True, sender=None, limit=256, retention=600, state_file=None, library=None):
        self.lights = validate_lights(lights)
        self.simulation = simulation
        self.sender = sender or self._transport
        self.operations, self.keys, self.last_sent = {}, {}, {}
        self.state_store = StateStore(state_file, self.lights, simulation) if state_file else None
        if self.state_store:
            self.last_sent = self.state_store.load()
        self.restored = set(self.last_sent)
        self.pending_state = set()
        self.persistence_error = False
        self.events = deque(maxlen=512)
        self.sequence = 0
        self.config_changing = False
        self.changed = asyncio.Event()
        self.instance = secrets.token_hex(12)
        self.tasks = set()
        self.limit, self.retention = limit, retention
        self.queue = CommandQueue(self._deliver)
        try:
            self.groups, self.scenes = validate_library(library, self.lights, self.validate)
        except APIError as error:
            raise ValueError("Invalid scene command: " + error.code) from None

    async def _transport(self, light, packets):
        if self.simulation:
            await asyncio.sleep(0.01)
        else:
            profile = DEVICE_UUIDS[light["prefix"]]
            await write_sequence(light["address"], profile["service"], profile["write"], packets)

    def event(self, kind, target, operation):
        self.sequence += 1
        self.events.append({"version": 1, "sequence": self.sequence, "type": kind,
                            "target_id": target, "operation_id": operation, "timestamp": time.time()})
        self.changed.set()
        self.changed = asyncio.Event()

    def validate(self, target, action, body):
        if target not in self.lights:
            raise APIError(404, "light_not_found")
        prefix = self.lights[target]["prefix"]
        if not isinstance(body, dict) or not body:
            raise APIError(422, "invalid_command")
        if action == "native":
            if (set(body) != {"effect", "speed", "brightness"}
                    or not integer(body.get("effect"), 0x82, 0x8a)
                    or not integer(body.get("speed"), 0, 100)
                    or not integer(body.get("brightness"), 1, 100)):
                raise APIError(422, "invalid_native_effect")
            if prefix != "KS03~":
                raise APIError(422, "unsupported_capability")
            return
        if set(body) - {"power", "rgb", "brightness", "transition_ms"}:
            raise APIError(422, "unknown_fields")
        if "power" in body and type(body["power"]) is not bool:
            raise APIError(422, "invalid_power")
        if "rgb" in body and (not isinstance(body["rgb"], list) or len(body["rgb"]) != 3
                               or not all(integer(v, 0, 255) for v in body["rgb"])):
            raise APIError(422, "invalid_rgb")
        if "brightness" in body and not integer(body["brightness"], 0, 100):
            raise APIError(422, "invalid_brightness")
        if "transition_ms" in body and not integer(body["transition_ms"], 0, 0):
            raise APIError(422, "unsupported_transition")
        if not set(body) & {"power", "rgb", "brightness"}:
            raise APIError(422, "empty_command")
        if set(body) & {"rgb", "brightness"}:
            # Known color commands may implicitly turn on a light: require explicit consent in the request.
            if body.get("power") is not True:
                raise APIError(422, "color_requires_explicit_power_on")
            if prefix not in DEVICE_MAPPINGS:
                raise APIError(422, "unsupported_capability")
            if prefix != "KS03~" and body.get("brightness", 100) != 100:
                raise APIError(422, "unsupported_brightness")
            remembered = self.last_sent.get(target, {})
            if "rgb" not in body and "rgb" not in remembered:
                if prefix != "KS03~" or "native_effect" not in remembered:
                    raise APIError(422, "remembered_color_required")
                if body.get("brightness") == 0:
                    raise APIError(422, "native_brightness_requires_positive_value")

    async def _deliver(self, target, command):
        action, body = command
        self.validate(target, action, body)
        light = self.lights[target]
        if action == "native":
            packets = [power(True), bytes([0x5c, 0, body["effect"], body["speed"], body["brightness"], 0, 0xc5])]
            state = {"power": True, "native_effect": body["effect"], "speed": body["speed"], "brightness": body["brightness"]}
        else:
            state = dict(self.last_sent.get(target, {}))
            packets = [power(body["power"])] if "power" in body else []
            if "rgb" not in body and "brightness" in body and "native_effect" in state:
                # Resolve partial updates at delivery time, behind preceding commands.
                packets.append(bytes([0x5c, 0, state["native_effect"], state["speed"], body["brightness"], 0, 0xc5]))
                state["brightness"] = body["brightness"]
            elif "rgb" in body or "brightness" in body:
                rgb = body.get("rgb", state.get("rgb"))
                brightness = body.get("brightness", state.get("brightness", 100))
                kind = DEVICE_MAPPINGS[light["prefix"]]["type"]
                wire_brightness = brightness if light["prefix"] == "KS03~" else 255
                packets.append(color(*calibrate_rgb(rgb, gains(light)), device_type=kind, brightness=wire_brightness))
                state = {"rgb": rgb, "brightness": brightness}
            state.update({k: v for k, v in body.items() if k == "power"})
        if self.state_store:
            # Persist uncertainty BEFORE sending, so a crash cannot resurrect stale state.
            self.pending_state.add(target)
            try:
                self.state_store.save(self.last_sent, self.pending_state)
                self.persistence_error = False
            except OSError:
                self.pending_state.discard(target)
                self.persistence_error = True
                raise
        try:
            await self.sender(light, packets)
        except BaseException:
            self.last_sent.pop(target, None)
            self.restored.discard(target)
            self.pending_state.discard(target)
            raise
        self.last_sent[target] = state
        self.restored.discard(target)
        self.pending_state.discard(target)
        if self.state_store:
            try:
                self.state_store.save(self.last_sent, self.pending_state)
                self.persistence_error = False
            except OSError:
                # Delivery happened; report storage degradation without retrying the command.
                self.persistence_error = True

    def prune(self):
        now = time.monotonic()
        expired = [key for key, op in self.operations.items()
                   if op.get("completed") is not None and now - op["completed"] >= self.retention]
        for key in expired:
            del self.operations[key]
        self.keys = {key: entry for key, entry in self.keys.items() if entry[1] in self.operations}

    def previous_operation(self, target, action, body, key):
        self.prune()
        fingerprint = json.dumps([target, action, body], sort_keys=True, separators=(",", ":"))
        if key is not None:
            if not re.fullmatch(r"[a-zA-Z0-9_.:-]{1,128}", key):
                raise APIError(400, "invalid_idempotency_key")
            if key in self.keys:
                previous, op_id = self.keys[key]
                if previous != fingerprint:
                    raise APIError(409, "idempotency_conflict")
                return fingerprint, op_id
        return fingerprint, None

    def submit(self, target, action, body, key):
        if self.config_changing:
            raise APIError(409, 'configuration_changing')
        fingerprint, previous = self.previous_operation(target, action, body, key)
        if previous is not None:
            return previous
        self.validate(target, action, body)
        if len(self.operations) >= self.limit:
            raise APIError(429, "operation_capacity")
        future = self.queue.submit(target, (action, body))
        if future.done() and future.result().status == "rejected":
            raise APIError(429, "queue_full")
        op_id = "op_" + secrets.token_hex(12)
        self.operations[op_id] = {"operation_id": op_id, "target_id": target, "status": "queued",
                                  "confirmation": "simulated" if self.simulation else "unconfirmed"}
        if key is not None:
            self.keys[key] = fingerprint, op_id
        self.event("operation.updated", target, op_id)
        task = asyncio.create_task(self._observe(op_id, future))
        self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)
        return op_id

    def submit_collection(self, kind, target, action, body, key):
        if self.config_changing:
            raise APIError(409, 'configuration_changing')
        # Namespace the intent so keys cannot collide with single-light commands.
        fingerprint, previous = self.previous_operation([kind, target], action, body, key)
        if previous is not None:
            return previous
        if kind == "group":
            if target not in self.groups:
                raise APIError(404, "group_not_found")
            actions = [{"light": member, "type": action, "body": copy.deepcopy(body)}
                       for member in self.groups[target]["members"]]
        else:
            if target not in self.scenes:
                raise APIError(404, "scene_not_found")
            if body != {}:
                raise APIError(422, "scene_apply_requires_empty_object")
            actions = copy.deepcopy(self.scenes[target]["actions"])
        # Validate every member before admitting any work.
        for item in actions:
            self.validate(item["light"], item["type"], item["body"])
        if len(self.operations) >= self.limit:
            raise APIError(429, "operation_capacity")
        futures = self.queue.submit_batch([(item["light"], (item["type"], item["body"])) for item in actions])
        if futures is None:
            raise APIError(429, "queue_full")
        op_id = "op_" + secrets.token_hex(12)
        self.operations[op_id] = {
            "operation_id": op_id, "target_id": target, "target_type": kind,
            "status": "queued", "confirmation": "simulated" if self.simulation else "unconfirmed",
            "members": [{"target_id": item["light"], "status": "queued"} for item in actions]}
        if key is not None:
            self.keys[key] = fingerprint, op_id
        self.event("operation.updated", target, op_id)
        task = asyncio.create_task(self._observe_collection(op_id, futures))
        self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)
        return op_id

    async def _observe_collection(self, op_id, futures):
        op = self.operations[op_id]

        async def member_result(member, future):
            result = await future
            member["status"] = result.status
            member["confirmation"] = op["confirmation"]
            if result.status != "succeeded":
                member["error"] = "cancelled" if result.status == "cancelled" else "write_failed"
            self.event("operation.updated", op["target_id"], op_id)
            if result.status == "succeeded":
                self.event("light.updated", member["target_id"], op_id)

        await asyncio.gather(*(member_result(member, future) for member, future in zip(op["members"], futures)))
        statuses = {member["status"] for member in op["members"]}
        op["status"] = "succeeded" if statuses == {"succeeded"} else "cancelled" if statuses == {"cancelled"} else "failed"
        if op["status"] != "succeeded":
            op["error"] = "partial_failure" if "succeeded" in statuses else "members_failed"
        op["completed"] = time.monotonic()
        self.event("operation.updated", op["target_id"], op_id)

    async def _observe(self, op_id, future):
        result = await future
        op = self.operations[op_id]
        op["status"] = result.status
        op["completed"] = time.monotonic()
        if result.status != "succeeded":
            op["error"] = "cancelled" if result.status == "cancelled" else "write_failed"
        self.event("operation.updated", op["target_id"], op_id)
        if result.status == "succeeded":
            self.event("light.updated", op["target_id"], op_id)

    def light(self, target):
        if target not in self.lights:
            raise APIError(404, "light_not_found")
        light = self.lights[target]
        return {"id": target, "name": light["name"], "prefix": light["prefix"],
                "calibration": {"rgb_gains": list(gains(light))},
                "last_sent": self.last_sent.get(target), "restored": target in self.restored, "confirmation": "simulated" if self.simulation else "unconfirmed",
                "capabilities": {"rgb": light["prefix"] in DEVICE_MAPPINGS,
                                 "brightness": light["prefix"] == "KS03~", "native_effects": light["prefix"] == "KS03~"}}

    async def close(self):
        self.changed.set()
        await self.queue.close()
        await asyncio.gather(*list(self.tasks))


def create_app(lights, token, *, simulation=True, sender=None, limit=256, retention=600, mqtt=None, state_file=None, library=None, credentials_file=None, library_file=None, lights_file=None):
    if not isinstance(token, str) or len(token) < 32 or not token.isascii() or any(c.isspace() for c in token):
        raise ValueError("Set a non-whitespace ASCII bearer token of at least 32 characters")
    if library_file:
        library = load_library(library_file)
    if lights_file:
        catalog = load_json(lights_file)
        if not isinstance(catalog, dict) or set(catalog) != {'lights'}:
            raise ValueError('Invalid light catalog')
        lights = catalog['lights']
    hub = Hub(lights, simulation=simulation, sender=sender, limit=limit, retention=retention, state_file=state_file, library=library)
    if credentials_file:
        load_credentials(credentials_file, hub.lights)

    def allowed(request, targets):
        principal = request.get('credential')
        return principal is None or set(targets) <= set(principal['lights'])

    def require_targets(request, targets):
        if not allowed(request, targets):
            raise APIError(403, 'target_not_allowed')

    def members(kind, item):
        return item['members'] if kind == 'groups' else [entry['light'] for entry in item['actions']]

    def operation_targets(op):
        return [member['target_id'] for member in op['members']] if 'members' in op else [op['target_id']]

    @web.middleware
    async def security(request, handler):
        try:
            supplied = request.headers.get("Authorization", "")
            if not hmac.compare_digest(supplied.encode(), ("Bearer " + token).encode()):
                principal = None
                if credentials_file and supplied.startswith('Bearer '):
                    try:
                        principal = await asyncio.to_thread(authenticate, credentials_file, supplied[7:], hub.lights)
                    except (ValueError, OSError, UnicodeError):
                        raise APIError(503, 'credentials_unavailable') from None
                if principal is None:
                    raise APIError(401, "unauthorized")
                request['credential'] = principal
                if request.method not in {'GET', 'HEAD'} and principal['scope'] != 'control':
                    raise APIError(403, 'read_only_credential')
            if request.headers.get("Origin"):
                raise APIError(403, "browser_origin_not_allowed")
            return await handler(request)
        except APIError as error:
            return web.json_response({"error": error.code}, status=error.status)
        except web.HTTPException as error:
            return web.json_response({"error": error.reason}, status=error.status)

    app = web.Application(middlewares=[security], client_max_size=16384)
    bridge = None
    if mqtt is not None:
        from .mqtt_bridge import MQTTBridge
        bridge = MQTTBridge(hub, **mqtt)
        async def mqtt_context(app):
            task = asyncio.create_task(bridge.run())
            try:
                yield
            finally:
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)
        app.cleanup_ctx.append(mqtt_context)


    async def health(request):
        return web.json_response({"status": "degraded" if hub.persistence_error or (bridge and bridge.status()["state"] != "online") else "ok",
                                  "mode": "simulation" if simulation else "ble", "instance": hub.instance,
                                  "persistence": {"enabled": hub.state_store is not None, "status": "error" if hub.persistence_error else "ok"},
                                  "mqtt": bridge.status() if bridge else {"state": "disabled"}})

    async def capabilities(request):
        return web.json_response({"api_version": 1, "authentication": "scoped_bearer" if credentials_file else "single_operator_bearer",
                                 "groups": True, "scenes": True, "websocket": False,
                                 "events": "polling", "device_readback": False,
                                 "event_wait_seconds": 25,
                                 "library_edit": library_file is not None and request.get('credential') is None,
                                 "calibration_edit": lights_file is not None and request.get('credential') is None,
                                 "operation_retention_seconds": retention, "operation_limit": limit,
                                 "calibration": True, "calibration_model": "static_rgb_gains", "durable_last_sent": hub.state_store is not None})

    async def lights_list(request):
        return web.json_response({"lights": [hub.light(target) for target in hub.lights if allowed(request, [target])], "cursor": hub.sequence, "instance": hub.instance})

    async def light_get(request):
        require_targets(request, [request.match_info['target']])
        return web.json_response(hub.light(request.match_info["target"]))

    async def edit_calibration(request):
        target = request.match_info['target']
        require_targets(request, [target])
        if target not in hub.lights:
            raise APIError(404, 'light_not_found')
        light = hub.lights[target]
        if light['prefix'] not in DEVICE_MAPPINGS:
            raise APIError(422, 'unsupported_calibration')
        current = copy.deepcopy(light.get('calibration', {'rgb_gains': [1, 1, 1]}))
        current.setdefault('presets', {})
        etag = revision(current)
        if request.method == 'GET':
            return web.json_response({'calibration': current, 'built_in_presets': PRESETS}, headers={'ETag': etag})
        if request.get('credential') is not None:
            raise APIError(403, 'operator_required')
        if not lights_file:
            raise APIError(409, 'lights_file_required')
        if request.headers.get('If-Match') != etag:
            raise APIError(412, 'calibration_version_changed')
        if request.content_type != 'application/json':
            raise APIError(415, 'json_required')
        try:
            updated = await request.json()
        except (ValueError, UnicodeError):
            raise APIError(422, 'invalid_calibration') from None
        if not valid_calibration(updated):
            raise APIError(422, 'invalid_calibration')
        updated.setdefault('presets', {})
        if hub.config_changing or any(op['status'] in {'queued', 'running'} for op in hub.operations.values()):
            raise APIError(409, 'commands_in_progress')
        latest = copy.deepcopy(light.get('calibration', {'rgb_gains': [1, 1, 1]}))
        latest.setdefault('presets', {})
        if revision(latest) != etag:
            raise APIError(412, 'calibration_version_changed')
        hub.config_changing = True
        try:
            original_catalog = {'lights': list(hub.lights.values())}
            if revision(await asyncio.to_thread(load_json, lights_file)) != revision(original_catalog):
                raise APIError(409, 'lights_file_changed_restart_required')
            next_catalog = copy.deepcopy(original_catalog)
            for entry in next_catalog['lights']:
                if entry['id'] == target:
                    entry['calibration'] = updated
            if len(json.dumps(next_catalog, indent=2).encode('utf-8')) > 262144:
                raise APIError(422, 'catalog_too_large')
            # Publish config and memory together, without a cancellable gap.
            save_json(lights_file, next_catalog)
            changed = gains(light) != updated['rgb_gains']
            light['calibration'] = copy.deepcopy(updated)
            if changed:
                hub.last_sent.pop(target, None)
                hub.restored.discard(target)
                if hub.state_store:
                    try:
                        hub.state_store.save(hub.last_sent, hub.pending_state)
                    except (OSError, ValueError):
                        hub.persistence_error = True
        except (OSError, ValueError, UnicodeError):
            raise APIError(503, 'calibration_save_failed') from None
        finally:
            hub.config_changing = False
        return web.json_response({'calibration': updated, 'built_in_presets': PRESETS}, headers={'ETag': revision(updated)})

    async def command(request):
        require_targets(request, [request.match_info['target']])
        if request.content_type != "application/json":
            raise APIError(415, "json_required")
        try:
            body = await request.json()
        except (ValueError, UnicodeError):
            raise APIError(400, "invalid_json")
        action = "native" if request.path.endswith("/effects/native") else "state"
        op_id = hub.submit(request.match_info["target"], action, body, request.headers.get("Idempotency-Key"))
        return web.json_response({"operation_id": op_id, "status": hub.operations[op_id]["status"]}, status=202)

    async def collections(request):
        kind = request.match_info["kind"]
        items = (hub.groups if kind == "groups" else hub.scenes).values()
        return web.json_response({kind: [item for item in items if allowed(request, members(kind, item))]})

    async def edit_library(request):
        if request.get('credential') is not None:
            raise APIError(403, 'operator_required')
        current = {'version': 1, 'groups': list(hub.groups.values()), 'scenes': list(hub.scenes.values())}
        etag = revision(current)
        if request.method == 'GET':
            return web.json_response(current, headers={'ETag': etag})
        if not library_file:
            raise APIError(409, 'library_file_required')
        if request.headers.get('If-Match') != etag:
            raise APIError(412, 'library_version_changed')
        if request.content_type != 'application/json':
            raise APIError(415, 'json_required')
        try:
            updated = await request.json()
            groups, scenes = validate_library(updated, hub.lights, hub.validate)
            if updated is None:
                raise ValueError('Library must be an object')
        except (ValueError, TypeError, UnicodeError):
            raise APIError(422, 'invalid_library') from None
        if hub.config_changing or any(op['status'] in {'queued', 'running'} for op in hub.operations.values()):
            raise APIError(409, 'commands_in_progress')
        # Recheck after reading the body: another editor may have completed meanwhile.
        if revision({'version': 1, 'groups': list(hub.groups.values()), 'scenes': list(hub.scenes.values())}) != etag:
            raise APIError(412, 'library_version_changed')
        hub.config_changing = True
        try:
            if revision(await asyncio.to_thread(load_library, library_file)) != etag:
                raise APIError(409, 'library_file_changed_restart_required')
            # Bounded 16 KiB configuration commit: keep disk replacement and
            # in-memory publication in one cancellation-free step.
            save_json(library_file, updated)
            hub.groups, hub.scenes = groups, scenes
        except (OSError, ValueError, UnicodeError):
            raise APIError(503, 'library_save_failed') from None
        finally:
            hub.config_changing = False
        return web.json_response(updated, headers={'ETag': revision(updated)})

    async def collection_command(request):
        collection_kind = request.match_info['kind']
        item = (hub.groups if collection_kind == 'groups' else hub.scenes).get(request.match_info['target'])
        if item is None:
            raise APIError(404, 'collection_not_found')
        require_targets(request, members(collection_kind, item))
        if request.content_type != "application/json":
            raise APIError(415, "json_required")
        try:
            body = await request.json()
        except (ValueError, UnicodeError):
            raise APIError(400, "invalid_json")
        kind = "group" if request.match_info["kind"] == "groups" else "scene"
        action = "apply" if kind == "scene" else "native" if request.path.endswith("/effects/native") else "state"
        op_id = hub.submit_collection(kind, request.match_info["target"], action, body, request.headers.get("Idempotency-Key"))
        return web.json_response({"operation_id": op_id, "status": hub.operations[op_id]["status"]}, status=202)

    async def operation(request):
        hub.prune()
        op = hub.operations.get(request.match_info["operation"])
        if op is None:
            raise APIError(404, "operation_not_found")
        require_targets(request, operation_targets(op))
        return web.json_response({k: v for k, v in op.items() if k != "completed"})

    async def events(request):
        if request.query.get("instance", hub.instance) != hub.instance:
            raise APIError(409, "resync_required")
        try:
            after = int(request.query.get("after", "0"))
            wait = int(request.query.get('wait', '0'))
            if after < 0 or not 0 <= wait <= 25:
                raise ValueError()
        except ValueError:
            raise APIError(400, "invalid_cursor")
        if after > hub.sequence or (hub.events and after < hub.events[0]["sequence"] - 1):
            raise APIError(409, "resync_required")
        if wait and after == hub.sequence:
            try:
                await asyncio.wait_for(hub.changed.wait(), wait)
            except asyncio.TimeoutError:
                pass
        if hub.events and after < hub.events[0]['sequence'] - 1:
            raise APIError(409, 'resync_required')
        visible = []
        for event in hub.events:
            if event['sequence'] <= after:
                continue
            op = hub.operations.get(event['operation_id'])
            if request.get('credential') is None or (op is not None and allowed(request, operation_targets(op))):
                visible.append(event)
        return web.json_response({"events": visible, "cursor": hub.sequence, "instance": hub.instance})

    async def cleanup(app):
        await hub.close()
    app.on_cleanup.append(cleanup)
    app.router.add_get("/api/v1/health", health)
    app.router.add_get("/api/v1/capabilities", capabilities)
    app.router.add_get("/api/v1/lights", lights_list)
    app.router.add_get("/api/v1/lights/{target}", light_get)
    app.router.add_get('/api/v1/lights/{target}/calibration', edit_calibration)
    app.router.add_put('/api/v1/lights/{target}/calibration', edit_calibration)
    app.router.add_patch("/api/v1/lights/{target}/state", command)
    app.router.add_post("/api/v1/lights/{target}/effects/native", command)
    app.router.add_get("/api/v1/{kind:groups|scenes}", collections)
    app.router.add_get('/api/v1/library', edit_library)
    app.router.add_put('/api/v1/library', edit_library)
    app.router.add_patch("/api/v1/{kind:groups}/{target}/state", collection_command)
    app.router.add_post("/api/v1/{kind:groups}/{target}/effects/native", collection_command)
    app.router.add_post("/api/v1/{kind:scenes}/{target}/apply", collection_command)
    app.router.add_get("/api/v1/operations/{operation}", operation)
    app.router.add_get("/api/v1/events", events)
    return app


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ble", action="store_true", help="Enable physical BLE writes (default: simulation)")
    parser.add_argument("--config", help="JSON file containing a lights array")
    parser.add_argument("--library", help="Optional versioned group/scene JSON file")
    parser.add_argument("--credentials", help="Optional scoped controller credential hashes; reloaded on each request")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--mqtt-host")
    parser.add_argument("--mqtt-port", type=int, default=1883)
    parser.add_argument("--mqtt-id", default="local")
    parser.add_argument("--mqtt-tls", action="store_true")
    parser.add_argument("--mqtt-ca-file")
    parser.add_argument("--mqtt-manifest")
    args = parser.parse_args()
    try:
        if args.ble and not args.config:
            raise ValueError("BLE mode requires --config")
        if not 1 <= args.port <= 65535:
            raise ValueError("Invalid port")
        if args.config:
            with open(args.config, encoding="utf-8") as handle:
                lights = json.load(handle)["lights"]
        else:
            lights = [{"id": "desk", "name": "Demo desk light", "prefix": "KS03~", "address": "simulation"}]
        mqtt = None
        if args.mqtt_host:
            mqtt = dict(hostname=args.mqtt_host, port=args.mqtt_port, hub_id=args.mqtt_id,
                        tls=args.mqtt_tls, ca_file=args.mqtt_ca_file, manifest=args.mqtt_manifest,
                        username=os.environ.get("KS_MQTT_USERNAME"), password=os.environ.get("KS_MQTT_PASSWORD"))
            if sys.platform == "win32":
                asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
        app = create_app(lights, os.environ.get("KS_LIGHT_TOKEN"), simulation=not args.ble, mqtt=mqtt,
                         library_file=args.library, credentials_file=args.credentials, lights_file=args.config)
    except (ValueError, KeyError, TypeError, OSError) as error:
        parser.error(str(error))
    # Loopback only in this first release. Never log authorization headers or a token.
    web.run_app(app, host="127.0.0.1", port=args.port, access_log=None)


if __name__ == "__main__":
    main()
