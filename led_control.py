#!/usr/bin/env python3
import asyncio
import argparse
import math
import json
from pathlib import Path
from ks_light.controls import prepare_color
from ks_light.storage import StateStore
from typing import Optional

try:
    from bleak import BleakScanner
    from ks_light.transport import write_sequence
except ImportError:
    raise SystemExit("Please install bleak: pip install bleak")

# UUID template used in the original app: 0000%s-0000-1000-8000-00805f9b34fb
UUID_TEMPLATE = "0000%s-0000-1000-8000-00805f9b34fb"

# Optional defaults for convenience
DEFAULT_PREFIX = "KS03~"
DEFAULT_ADDRESS = None  # Discover a device unless the caller selects an address.

# Mappings derived from UUIDBeanList.smali
# Each entry maps a device name prefix to its GATT service and characteristic short UUIDs
from ks_light.profiles import DEVICE_UUIDS

# Command builders based on CmdFloor.getTopOn(Z):
# On:  "5B" + "F0" + "01B5"
# Off: "5B" + "0F" + "01B5"
# Many fragments use this for top/strip toggles. You may need other Cmd* for specific models,
# but this is a good starting point observed across UI toggles.

from ks_light.protocol import power as build_on_off_cmd

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
    parser = argparse.ArgumentParser(description="Control KS smart LED lights over BLE")
    parser.add_argument("action", choices=["on", "off", "scan", "list", "rgb", "brightness"], help="Power, discover, list profiles, or set RGB/brightness")
    parser.add_argument("model_prefix", nargs="?", default=DEFAULT_PREFIX, help="Device name prefix (e.g., KS03-, KS04-, KS03~)")
    parser.add_argument("--address", dest="address", default=DEFAULT_ADDRESS, help="BLE MAC/address (skip scan if provided)")
    parser.add_argument("--all-ks03", dest="all_ks03", action="store_true", help="Send to all KS03-/KS03~ devices found")
    parser.add_argument("--timeout", type=float, default=8.0, help="Scan timeout seconds")
    parser.add_argument("--verbose", "-v", dest="verbose", action="store_true", help="Verbose output (show target and payload)")
    parser.add_argument("--rgb", type=int, nargs=3, metavar=("R", "G", "B"))
    parser.add_argument("--brightness", type=int, help="Brightness byte (0-255), RGB profiles only")
    parser.add_argument("--json", action="store_true", help="JSON output for scan/list and RGB controls")
    parser.add_argument("--state-file", type=Path, default=Path.home() / ".ks_led_state.json")
    args = parser.parse_args(argv)
    if args.action == "rgb" and args.rgb is None:
        parser.error("rgb requires --rgb R G B")
    if args.action == "brightness" and args.brightness is None:
        parser.error("brightness requires --brightness 0..255")
    if args.rgb is not None and args.action != "rgb":
        parser.error("--rgb requires the rgb action")
    if args.brightness is not None and args.action not in ("rgb", "brightness"):
        parser.error("--brightness requires rgb or brightness")
    if args.all_ks03 and args.action not in ("on", "off"):
        parser.error("--all-ks03 currently supports on/off only")
    if args.json and args.action in ("on", "off"):
        parser.error("--json currently supports scan/list/rgb/brightness")
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
        from ks_light.profiles import PROFILES
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
        from ks_light.profiles import DEVICE_MAPPINGS
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
