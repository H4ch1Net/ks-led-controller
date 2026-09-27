"""Named hub actions for keyboard macros and external controllers."""
import argparse
import asyncio
import ipaddress
import json
import math
import re
from pathlib import Path
import ssl
import sys
import uuid
from urllib.parse import urlsplit, quote

import aiohttp


class ControllerError(Exception):
    pass


def load_config(path):
    path = Path(path).resolve()
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict) or not isinstance(data.get("hub_url"), str):
        raise ValueError("Expected controller configuration object")
    url = data["hub_url"].rstrip("/")
    parts = urlsplit(url)
    if parts.username or parts.password or parts.query or parts.fragment or not parts.hostname:
        raise ValueError("Invalid hub URL")
    try:
        local = ipaddress.ip_address(parts.hostname).is_loopback
    except ValueError:
        local = parts.hostname == "localhost"
    if parts.scheme != "https" and not (parts.scheme == "http" and local):
        raise ValueError("Remote hubs require HTTPS")
    if parts.path != "/api/v1":
        raise ValueError("Hub URL must end in /api/v1")
    token = (path.parent / data["token_file"]).read_text(encoding="utf-8").strip()
    if not token or any(c.isspace() for c in token):
        raise ValueError("Invalid token file")
    timeout = data.get("timeout_seconds", 20)
    if type(timeout) not in (int, float) or not math.isfinite(timeout) or not 1 <= timeout <= 120:
        raise ValueError("Timeout must be 1..120 seconds")
    actions = data["actions"]
    if not isinstance(actions, dict) or not actions:
        raise ValueError("At least one action is required")
    for name, action in actions.items():
        if not isinstance(name, str) or not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", name) or not isinstance(action, dict):
            raise ValueError("Invalid named action")
        targets = [kind for kind in ("light", "group", "scene") if kind in action]
        if len(targets) != 1:
            raise ValueError("Action needs exactly one light, group or scene ID")
        target = action[targets[0]]
        if not isinstance(target, str) or not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", target):
            raise ValueError("Invalid action target ID")
        if not isinstance(action.get("body"), dict):
            raise ValueError("Action needs a JSON body")
        if targets[0] == "scene":
            if action.get("type") != "apply" or action["body"] != {}:
                raise ValueError("Scene actions need apply type and an empty body")
        elif action.get("type") not in ("state", "native"):
            raise ValueError("Light/group action needs state/native type")
    context = ssl.create_default_context()
    if data.get("ca_file"):
        context.load_verify_locations(str(path.parent / data["ca_file"]))
    return url, token, timeout, actions, context


async def execute(url, token, action, timeout=20, context=None):
    """Submit once, then poll. Never replay an uncertain physical command."""
    async def run():
        headers = {"Authorization": "Bearer " + token}
        async with aiohttp.ClientSession(headers=headers, trust_env=False,
                timeout=aiohttp.ClientTimeout(total=timeout),
                connector=aiohttp.TCPConnector(ssl=context or ssl.create_default_context())) as session:
            async def request(method, endpoint, **kwargs):
                async with session.request(method, url + endpoint, allow_redirects=False, **kwargs) as response:
                    if response.status >= 300:
                        raise ControllerError(f"Hub rejected request (HTTP {response.status})")
                    raw = bytearray()
                    async for chunk in response.content.iter_chunked(4096):
                        raw.extend(chunk)
                        if len(raw) > 65536:
                            raise ControllerError("Hub response too large")
                    return json.loads(raw)
            kind = next(kind for kind in ("light", "group", "scene") if kind in action)
            target = quote(action[kind], safe="")
            native = action["type"] == "native"
            suffix = "apply" if kind == "scene" else "effects/native" if native else "state"
            submitted = await request("POST" if native or kind == "scene" else "PATCH",
                f"/{kind}s/{target}/" + suffix,
                json=action["body"], headers={"Idempotency-Key": str(uuid.uuid4())})
            operation = submitted["operation_id"]
            if not isinstance(operation, str) or not re.fullmatch(r"[a-zA-Z0-9_-]{1,128}", operation):
                raise ControllerError("Invalid operation ID from hub; command was not retried")
            while True:
                result = await request("GET", "/operations/" + quote(operation, safe=""))
                if result.get("operation_id") != operation:
                    raise ControllerError("Mismatched operation response; command was not retried")
                if result["status"] in ("succeeded", "failed", "cancelled"):
                    return result
                if result["status"] not in ("queued", "running"):
                    raise ControllerError("Unknown operation status; command was not retried")
                await asyncio.sleep(0.15)
    try:
        return await asyncio.wait_for(run(), timeout)
    except asyncio.TimeoutError:
        raise ControllerError("Timed out; delivery may have occurred. Command was not retried.") from None
    except (aiohttp.ClientError, OSError, ValueError, KeyError, TypeError):
        raise ControllerError("Connection or response failed; delivery may have occurred. Command was not retried.") from None


def with_brightness(action, brightness):
    """Apply an explicit level to a configured color/effect without editing its file."""
    if type(brightness) is not int or not 1 <= brightness <= 100:
        raise ControllerError("Brightness must be an integer from 1 to 100")
    if "scene" in action:
        raise ControllerError("A saved scene cannot accept a brightness override")
    body = action["body"]
    if action["type"] == "state" and (body.get("power") is not True or "rgb" not in body):
        raise ControllerError("Brightness dial needs a color action with power=true and rgb, or a native effect")
    return {**action, "body": {**body, "brightness": brightness}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True, help="Controller JSON; credentials stay in a separate file")
    parser.add_argument("action", nargs="?", help="Named action; omit to list actions")
    parser.add_argument("--brightness", type=int, help="Override a named color/effect action at 1..100 percent")
    args = parser.parse_args()
    try:
        url, token, timeout, actions, context = load_config(args.config)
        if args.action is None:
            if args.brightness is not None:
                raise ControllerError("Choose an action for the brightness override")
            print("\n".join(sorted(actions)))
            return 0
        if args.action not in actions:
            raise ControllerError("Unknown action; omit action name to list available actions")
        action = actions[args.action] if args.brightness is None else with_brightness(actions[args.action], args.brightness)
        result = asyncio.run(execute(url, token, action, timeout, context))
        print(json.dumps({k: result[k] for k in ("operation_id", "status", "confirmation", "error", "members") if k in result}))
        return 0 if result["status"] == "succeeded" else 1
    except (ControllerError, ValueError, KeyError, TypeError, OSError):
        # Do not echo configuration contents, credentials, network bodies or private paths.
        error = sys.exc_info()[1]
        print(str(error) if isinstance(error, ControllerError) else "Invalid controller configuration or credential file", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
