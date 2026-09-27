"""Typed Stream Deck commands using the existing authenticated hub controller."""
import argparse
import asyncio
import json
import re
import sys

import aiohttp

from .controller import ControllerError, execute, load_config
from .controller_status import read_json


def command(spec):
    if not isinstance(spec, dict):
        raise ValueError("Invalid action")
    kind = spec.get("type")
    fields = {
        "power": {"type", "light", "power"},
        "color": {"type", "light", "rgb", "brightness"},
        "effect": {"type", "light", "effect", "speed", "brightness"},
        "brightness": {"type", "light", "brightness"},
        "scene": {"type", "scene"},
    }
    if kind not in fields or set(spec) != fields[kind]:
        raise ValueError("Invalid action fields")
    target = "scene" if kind == "scene" else "light"
    if not isinstance(spec[target], str) or not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", spec[target]):
        raise ValueError("Invalid target")
    for key, low, high in [("brightness", 1, 100), ("speed", 0, 100), ("effect", 130, 138)]:
        if key in spec and (type(spec[key]) is not int or not low <= spec[key] <= high):
            raise ValueError("Invalid level")
    body = {}
    if kind == "power":
        if spec["power"] not in ("on", "off", "toggle"):
            raise ValueError("Invalid power choice")
        body = {"power": spec["power"] == "on"}
    elif kind == "color":
        rgb = spec["rgb"]
        if not isinstance(rgb, list) or len(rgb) != 3 or any(type(v) is not int or not 0 <= v <= 255 for v in rgb):
            raise ValueError("Invalid RGB")
        body = {"power": True, "rgb": rgb, "brightness": spec["brightness"]}
    elif kind == "brightness":
        body = {"power": True, "brightness": spec["brightness"]}
    elif kind == "effect":
        body = {k: spec[k] for k in ("effect", "speed", "brightness")}
    return {target: spec[target], "type": "apply" if kind == "scene" else "native" if kind == "effect" else "state", "body": body}


async def run(config, spec=None):
    url, token, timeout, _, context = load_config(config)
    action = command(spec) if spec is not None else None
    async with aiohttp.ClientSession(trust_env=False, timeout=aiohttp.ClientTimeout(total=timeout)) as session:
        if spec is None:
            lights = await read_json(session, url + "/lights", token, context)
            scenes = await read_json(session, url + "/scenes", token, context)
            return {"lights": [{k: item[k] for k in ("id", "name", "capabilities")} for item in lights["lights"]],
                    "scenes": [{k: item[k] for k in ("id", "name")} for item in scenes["scenes"]]}
        if spec["type"] == "power" and spec["power"] == "toggle":
            light = await read_json(session, url + "/lights/" + spec["light"], token, context)
            state = light.get("last_sent") or {}
            if type(state.get("power")) is not bool or light.get("restored"):
                raise ControllerError("Power unknown; use On or Off first")
            action["body"]["power"] = not state["power"]
    return await execute(url, token, action, timeout, context)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--request", help="Typed action JSON; omit for read-only light/scene choices")
    args = parser.parse_args()
    try:
        spec = json.loads(args.request) if args.request is not None else None
        if args.request is not None and spec is None:
            raise ValueError("Invalid request")
        result = asyncio.run(run(args.config, spec))
        if spec is not None:
            result = {k: result[k] for k in ("operation_id", "status", "confirmation", "error") if k in result}
        print(json.dumps(result))
        return 0 if spec is None or result["status"] == "succeeded" else 1
    except (ControllerError, ValueError, KeyError, TypeError, OSError, aiohttp.ClientError, asyncio.TimeoutError):
        print("Check hub connection and action settings; command was not retried.", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
