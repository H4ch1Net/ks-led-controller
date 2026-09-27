"""Read-only last-sent status stream for external controller displays."""
import argparse
import asyncio
import json
from pathlib import Path

import aiohttp

from .controller import load_config


def light_label(light):
    state = light.get("last_sent")
    if not isinstance(state, dict) or not state:
        return "Unknown"
    prefix = "Sim" if light.get("confirmation") == "simulated" else "Saved" if light.get("restored") else "Sent"
    if state.get("power") is False:
        return prefix + " Off"
    rgb = state.get("rgb")
    if isinstance(rgb, list) and len(rgb) == 3 and all(type(v) is int and 0 <= v <= 255 for v in rgb):
        value = "#" + "".join(f"{v:02X}" for v in rgb)
    elif type(state.get("native_effect")) is int:
        value = "Effect " + str(state["native_effect"])
    else:
        value = "On" if state.get("power") is True else "Unknown"
    brightness = state.get("brightness")
    if type(brightness) is int and 0 <= brightness <= 100:
        value += f" {brightness}%"
    return prefix + " " + value


def action_labels(actions, lights, groups=(), scenes=()):
    by_id = {light["id"]: light for light in lights}
    memberships = {"group": {g["id"]: g["members"] for g in groups},
                   "scene": {s["id"]: [a["light"] for a in s["actions"]] for s in scenes}}
    labels = {}
    for name, action in actions.items():
        if "light" in action:
            members = [action["light"]]
        else:
            kind = "group" if "group" in action else "scene"
            members = memberships[kind].get(action[kind], [])
        states = [light_label(by_id[member]) if member in by_id else "Unavailable" for member in members]
        # Scene keys describe members' last-sent state, never whether a scene is active.
        labels[name] = states[0] if states and len(set(states)) == 1 else "Mixed" if states else "Unavailable"
    return labels


async def read_json(session, url, token, context, params=None):
    async with session.get(url, headers={"Authorization": "Bearer " + token}, ssl=context,
                           params=params, allow_redirects=False) as response:
        if response.status != 200:
            raise ValueError("Status unavailable")
        raw = bytearray()
        async for chunk in response.content.iter_chunked(4096):
            raw.extend(chunk)
            if len(raw) > 262144:
                raise ValueError("Response too large")
        return json.loads(raw)


async def watch(config, emit):
    delay = 1
    path = Path(config).resolve()
    cached_signature = None
    async with aiohttp.ClientSession(trust_env=False, timeout=aiohttp.ClientTimeout(total=32)) as session:
        while True:
            try:
                # Notice file edits without rebuilding TLS contexts/connections on every poll.
                raw = path.read_text(encoding="utf-8-sig")
                definition = json.loads(raw)
                dependencies = [path.parent / definition["token_file"]]
                if definition.get("ca_file"):
                    dependencies.append(path.parent / definition["ca_file"])
                signature = (raw, tuple((p.stat().st_mtime_ns, p.stat().st_size) for p in dependencies))
                if signature != cached_signature:
                    url, token, _, actions, context = load_config(config)
                    cached_signature = signature
                snapshot = await read_json(session, url + "/lights", token, context)
                groups = (await read_json(session, url + "/groups", token, context))["groups"] if any("group" in a for a in actions.values()) else []
                scenes = (await read_json(session, url + "/scenes", token, context))["scenes"] if any("scene" in a for a in actions.values()) else []
                emit({"status": "online", "states": action_labels(actions, snapshot["lights"], groups, scenes),
                      "lights": {item["id"]: light_label(item) for item in snapshot["lights"]},
                      "powers": {item["id"]: (item.get("last_sent") or {}).get("power") for item in snapshot["lights"]
                                 if not item.get("restored")}})
                delay = 1
                await read_json(session, url + "/events", token, context,
                                {"after": snapshot["cursor"], "instance": snapshot["instance"], "wait": 25})
                await asyncio.sleep(1)  # Coalesce bursts and bound refresh work to one snapshot/second.
            except (aiohttp.ClientError, OSError, ValueError, KeyError, TypeError, asyncio.TimeoutError):
                emit({"status": "offline"})
                await asyncio.sleep(delay)
                delay = min(delay * 2, 30)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    args = parser.parse_args()
    try:
        asyncio.run(watch(args.config, lambda value: print(json.dumps(value, separators=(",", ":")), flush=True)))
    except (KeyboardInterrupt, BrokenPipeError):
        pass


if __name__ == "__main__":
    main()
