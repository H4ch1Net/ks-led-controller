#!/usr/bin/env python3
"""Control KS Bluetooth lights directly from a computer, without the hub."""
import argparse
import asyncio
import json
import math
import re
from pathlib import Path
from typing import Optional

from ks_light.controls import prepare_color
from ks_light.profiles import DEVICE_MAPPINGS, DEVICE_UUIDS, PROFILES
from ks_light.protocol import NATIVE_EFFECT_IDS, NATIVE_EFFECTS, native_effect
from ks_light.protocol import power as build_on_off_cmd
from ks_light.storage import StateStore

try:
    from bleak import BleakScanner
    from ks_light.transport import write_sequence
except ImportError:
    raise SystemExit("Bleak is missing. Install dependencies: python -m pip install --require-hashes -r requirements.lock")

DEFAULT_PREFIX = "KS03~"
EFFECT_SLUGS = {name.lower().replace(" ", "-"): effect for name, effect in NATIVE_EFFECT_IDS.items()}


def hex_color(value):
    match = re.fullmatch(r"#?([0-9a-fA-F]{6})", value)
    if not match:
        raise argparse.ArgumentTypeError("use six hex digits, for example ff8800")
    return [int(match.group(1)[i:i + 2], 16) for i in (0, 2, 4)]


async def find_device_by_prefix(prefix: str, timeout: float = 8.0) -> Optional[str]:
    devices = await BleakScanner.discover(timeout=timeout)
    matches = sorted({d.address for d in devices if d.name and d.name.startswith(prefix)})
    if len(matches) > 1:
        raise SystemExit(
            f"Multiple devices match '{prefix}'. Select one with --address: "
            + ", ".join(matches)
        )
    return matches[0] if matches else None

async def find_all_ks03(timeout: float = 8.0):
    devices = await BleakScanner.discover(timeout=timeout)
    results = []
    for d in devices:
        if d.name and (d.name.startswith("KS03-") or d.name.startswith("KS03~")):
            results.append((d.address, d.name))
    return results

async def write_command(address, service_short, char_short, payload, verbose=False):
    if verbose:
        print(f"Writing {payload.hex().upper()} to {address} ({service_short}/{char_short})")
    await write_sequence(address, service_short, char_short, [payload])

async def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, epilog="Effects (KS03~ only): " + ", ".join(EFFECT_SLUGS))
    parser.add_argument("action", choices=["on", "off", "scan", "list", "rgb", "brightness", "effect"],
                        help="Power, discover, list profiles, set RGB/brightness, or start a built-in effect")
    parser.add_argument("model_prefix", nargs="?", default=DEFAULT_PREFIX, help="Device name prefix (e.g., KS03-, KS04-, KS03~)")
    parser.add_argument("--address", dest="address", help="BLE MAC/address (skip scan if provided)")
    parser.add_argument("--all-ks03", dest="all_ks03", action="store_true", help="Send to all KS03-/KS03~ devices found")
    parser.add_argument("--timeout", type=float, default=8.0, help="Scan timeout seconds")
    parser.add_argument("--verbose", "-v", dest="verbose", action="store_true", help="Verbose output (show target and payload)")
    color_group = parser.add_mutually_exclusive_group()
    color_group.add_argument("--rgb", type=int, nargs=3, metavar=("R", "G", "B"), help="Color channels 0..255")
    color_group.add_argument("--hex", type=hex_color, dest="rgb", metavar="RRGGBB", help="Color as hex, e.g. ff8800")
    parser.add_argument("--name", dest="effect", choices=sorted(EFFECT_SLUGS), metavar="EFFECT", help="Built-in effect for the effect action")
    parser.add_argument("--speed", type=int, default=35, help="Effect speed 0..100 (default 35)")
    parser.add_argument("--brightness", type=int, help="Brightness byte (0-255), RGB profiles only")
    parser.add_argument("--json", action="store_true", help="JSON output for scan/list and RGB/effect controls")
    parser.add_argument("--state-file", type=Path, default=Path.home() / ".ks_led_state.json")
    args = parser.parse_args(argv)
    if args.action == "rgb" and args.rgb is None:
        parser.error("rgb requires --rgb R G B or --hex RRGGBB")
    if args.action == "effect":
        if args.effect is None:
            parser.error("effect requires --name, one of: " + ", ".join(EFFECT_SLUGS))
        if args.model_prefix != "KS03~":
            parser.error("Built-in effects are available on KS03~ only")
        if not 0 <= args.speed <= 100:
            parser.error("--speed must be between 0 and 100")
    elif args.effect is not None:
        parser.error("--name requires the effect action")
    if args.action == "brightness" and args.brightness is None:
        parser.error("brightness requires --brightness 0..255")
    if args.rgb is not None and args.action != "rgb":
        parser.error("--rgb requires the rgb action")
    if args.brightness is not None and args.action not in ("rgb", "brightness", "effect"):
        parser.error("--brightness requires rgb, brightness or effect")
    if args.all_ks03 and args.action not in ("on", "off"):
        parser.error("--all-ks03 currently supports on/off only")
    if args.json and args.action in ("on", "off"):
        parser.error("--json supports scan, list, rgb, brightness and effect")
    if args.rgb is not None and any(not 0 <= v <= 255 for v in args.rgb):
        parser.error("RGB values must be between 0 and 255")
    if args.brightness is not None and not 0 <= args.brightness <= 255:
        parser.error("Brightness must be between 0 and 255")
    if args.timeout <= 0 or not math.isfinite(args.timeout):
        parser.error("--timeout must be a finite positive number")

    if args.model_prefix not in DEVICE_UUIDS:
        known = ", ".join(sorted(DEVICE_UUIDS.keys()))
        raise SystemExit(f"Unknown model_prefix. Known: {known}")

    if args.action == "list":
        print(json.dumps(PROFILES, indent=2) if args.json else "\n".join(
            f"{p['prefix']}: {p['color_type'] or 'power only'} (inherited, unverified)" for p in PROFILES))
        return
    if args.action == "scan":
        found = await BleakScanner.discover(timeout=args.timeout)
        devices = {}
        for device in found:
            prefix = next((p for p in DEVICE_UUIDS if (device.name or "").startswith(p)), None)
            if prefix:
                devices[device.address] = {"address": device.address, "name": device.name, "prefix": prefix}
        rows = list(devices.values())
        print(json.dumps(rows, indent=2) if args.json else "\n".join(
            f"{d['name']} {d['address']}" for d in rows) or "No KS devices found")
        return
    if args.action in ("rgb", "brightness"):
        if args.model_prefix not in DEVICE_MAPPINGS:
            parser.error("RGB controls unavailable for this profile")
        if DEVICE_MAPPINGS[args.model_prefix]["type"] == "ceiling" and args.brightness not in (None, 255):
            parser.error("Independent brightness unsupported for this profile")
    payload = build_on_off_cmd(args.action == "on")

    if args.all_ks03:
        targets = await find_all_ks03(timeout=args.timeout)
        if not targets:
            raise SystemExit("No KS03 devices found")
        # Send to each, picking correct UUID mapping by name prefix
        failures = 0
        for addr, name in targets:
            prefix = "KS03~" if name.startswith("KS03~") else "KS03-"
            mapping = DEVICE_UUIDS[prefix]
            try:
                await write_command(addr, mapping["service"], mapping["write"], payload, verbose=args.verbose)
                print(f"Sent {args.action.upper()} to {addr} ({name})")
            except Exception as e:
                failures += 1
                print(f"Failed to send to {addr} ({name}): {e}")
        if failures:
            raise SystemExit(1)
        return

    # Single-target behavior
    mapping = DEVICE_UUIDS[args.model_prefix]
    address = args.address
    if not address:
        address = await find_device_by_prefix(args.model_prefix, timeout=args.timeout)
        if not address:
            raise SystemExit(f"No device found with name starting '{args.model_prefix}'")

    if args.action == "effect":
        effect = EFFECT_SLUGS[args.effect]
        brightness = 100 if args.brightness is None else round(args.brightness * 100 / 255)
        try:
            payload = native_effect(effect, args.speed, max(1, brightness))
        except ValueError as error:
            parser.error(str(error))
        await write_sequence(address, mapping["service"], mapping["write"], [build_on_off_cmd(True), payload])
        result = {"address": address, "effect": NATIVE_EFFECTS[effect], "speed": args.speed,
                  "brightness": max(1, brightness), "confirmation": "unconfirmed"}
        print(json.dumps(result) if args.json else f"Started {NATIVE_EFFECTS[effect]} on {address} (device state unconfirmed).")
        return

    if args.action in ("rgb", "brightness"):
        store = StateStore(args.state_file)
        try:
            payload, rgb, brightness = prepare_color(args.model_prefix,
                store.get(address, args.model_prefix), args.rgb, args.brightness)
        except (ValueError, OSError) as error:
            raise SystemExit(str(error))
        # Explicit CLI color actions turn the light on, matching the menu.
        await write_sequence(address, mapping["service"], mapping["write"],
                             [build_on_off_cmd(True), payload])
        warning = None
        try:
            store.put(address, args.model_prefix, rgb, brightness)
        except (ValueError, OSError) as error:
            warning = f"Command sent, but settings could not be saved: {error}"
        result = {"address": address, "rgb": rgb, "brightness": brightness,
                  "confirmation": "unconfirmed", "persistence_warning": warning}
        print(json.dumps(result) if args.json else warning or "RGB settings sent (device state unconfirmed).")
        return
    await write_command(address, mapping["service"], mapping["write"], payload, verbose=args.verbose)
    print(f"Sent {args.action.upper()} to {address} ({args.model_prefix})")

if __name__ == "__main__":
    asyncio.run(main())
