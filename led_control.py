#!/usr/bin/env python3
import asyncio
import argparse
from typing import Optional

try:
    from bleak import BleakClient, BleakScanner
except Exception as e:
    raise SystemExit("Please install bleak: pip install bleak")

# UUID template used in the original app: 0000%s-0000-1000-8000-00805f9b34fb
UUID_TEMPLATE = "0000%s-0000-1000-8000-00805f9b34fb"

# Optional defaults for convenience
DEFAULT_PREFIX = "KS03~"
DEFAULT_ADDRESS = "BE:60:4D:00:58:37"  # KS03~370058

# Mappings derived from UUIDBeanList.smali
# Each entry maps a device name prefix to its GATT service and characteristic short UUIDs
DEVICE_UUIDS = {
    # KS03/KS04 classic (FFF0/FFF3)
    "KS03-": {"service": "FFF0", "write": "FFF3"},
    "KS04-": {"service": "FFF0", "write": "FFF3"},
    # KS03 tilde variant (AFD0..AFD3)
    # AFD1 = write-without-response, AFD2 = notify, AFD3 = read
    "KS03~": {"service": "AFD0", "write": "AFD1"},
    # AE00/AE01/AE02 family
    "KS01-": {"service": "AE00", "write": "AE01"},
    "KS02-": {"service": "AE00", "write": "AE01"},
    "KS04~": {"service": "AE00", "write": "AE10"},
    "KS05-": {"service": "AE00", "write": "AE02"},
    "KS07-": {"service": "AE00", "write": "AE10"},
    "KS08-": {"service": "AE00", "write": "AE10"},
    "KS09-": {"service": "AE00", "write": "AE10"},
    "KS10-": {"service": "AE00", "write": "AE10"},
    "KS11-": {"service": "AE00", "write": "AE10"},
    "KS12-": {"service": "AE00", "write": "AE10"},
    "KS13-": {"service": "AE00", "write": "AE10"},
    # KS15 tilde variant (AFD0..AFD3)
    "KS15~": {"service": "AFD0", "write": "AFD3"},
}

# Command builders based on CmdFloor.getTopOn(Z):
# On:  "5B" + "F0" + "01B5"
# Off: "5B" + "0F" + "01B5"
# Many fragments use this for top/strip toggles. You may need other Cmd* for specific models,
# but this is a good starting point observed across UI toggles.

def build_on_off_cmd(is_on: bool) -> bytes:
    hex_str = ("5B" + ("F0" if is_on else "0F") + "01B5")
    return bytes.fromhex(hex_str)

async def find_device_by_prefix(prefix: str, timeout: float = 8.0) -> Optional[str]:
    devices = await BleakScanner.discover(timeout=timeout)
    for d in devices:
        if d.name and d.name.startswith(prefix):
            return d.address
    return None

async def find_all_ks03(timeout: float = 8.0):
    devices = await BleakScanner.discover(timeout=timeout)
    results = []
    for d in devices:
        if d.name and (d.name.startswith("KS03-") or d.name.startswith("KS03~")):
            results.append((d.address, d.name))
    return results

async def write_command(address: str, service_short: str, char_short: str, payload: bytes, verbose=False):
    service_uuid = UUID_TEMPLATE % service_short
    char_uuid = UUID_TEMPLATE % char_short
    
    client = BleakClient(address)
    try:
        await client.connect()
        if not client.is_connected:
            raise RuntimeError("Failed to connect to device")
        
        # Small settle delay after connecting
        await asyncio.sleep(0.3)
        
        if verbose:
            print(f"Connected to {address}")
            print(f"Target service: {service_uuid}, char: {char_uuid}")
            print(f"Payload: {payload.hex().upper()}")
            # List available services and characteristics
            for service in client.services:
                if service_short.upper() in str(service.uuid).upper():
                    print(f"  Found service: {service.uuid}")
                    for char in service.characteristics:
                        print(f"    Char: {char.uuid}, props: {char.properties}")
        
        # Some stacks ignore service when writing characteristic by UUID; Bleak uses characteristic UUID
        # Many KS devices do not permit 'Write With Response'. Try without response first.
        write_success = False
        last_error = None
        try:
            await client.write_gatt_char(char_uuid, payload, response=False)
            write_success = True
            if verbose:
                print(f"  ✓ Wrote to {char_uuid} (no response)")
        except Exception as e1:
            last_error = e1
            if verbose:
                print(f"  ✗ Write without response failed: {e1}")
            try:
                # Fallback to write with response if supported
                await client.write_gatt_char(char_uuid, payload, response=True)
                write_success = True
                if verbose:
                    print(f"  ✓ Wrote to {char_uuid} (with response)")
            except Exception as e2:
                last_error = e2
                if verbose:
                    print(f"  ✗ Write with response failed: {e2}")
                # Last resort: for KS03 variants, some firmwares expose classic FFF3 alongside AFD3.
                # Try alternate write characteristic if primary fails.
                alt_char_short = None
                if char_short.upper() == "AFD3":
                    alt_char_short = "FFF3"
                elif char_short.upper() == "FFF3":
                    alt_char_short = "AFD3"
                if alt_char_short:
                    alt_char_uuid = UUID_TEMPLATE % alt_char_short
                    try:
                        await client.write_gatt_char(alt_char_uuid, payload, response=False)
                        write_success = True
                        if verbose:
                            print(f"  ✓ Wrote to alternate {alt_char_uuid} (no response)")
                    except Exception:
                        try:
                            await client.write_gatt_char(alt_char_uuid, payload, response=True)
                            write_success = True
                            if verbose:
                                print(f"  ✓ Wrote to alternate {alt_char_uuid} (with response)")
                        except Exception as e3:
                            raise RuntimeError(f"All write attempts failed: {e1}, {e2}, {e3}")
                else:
                    raise RuntimeError(f"Write failed: {e1}, {e2}")
        
        # Give device time to process command before disconnecting
        if write_success:
            await asyncio.sleep(0.2)
        else:
            raise RuntimeError(f"Write failed: {last_error}")
    finally:
        try:
            if client.is_connected:
                await client.disconnect()
        except Exception:
            pass  # Ignore disconnect errors

async def main():
    parser = argparse.ArgumentParser(description="Control KS smart LED lights over BLE")
    parser.add_argument("action", choices=["on", "off"], help="Turn lights on or off")
    parser.add_argument("model_prefix", nargs="?", default=DEFAULT_PREFIX, help="Device name prefix (e.g., KS03-, KS04-, KS03~)")
    parser.add_argument("--address", dest="address", default=DEFAULT_ADDRESS, help="BLE MAC/address (skip scan if provided)")
    parser.add_argument("--all-ks03", dest="all_ks03", action="store_true", help="Send to all KS03-/KS03~ devices found")
    parser.add_argument("--timeout", type=float, default=8.0, help="Scan timeout seconds")
    parser.add_argument("--verbose", "-v", dest="verbose", action="store_true", help="Verbose output (show services/characteristics)")
    args = parser.parse_args()

    if args.model_prefix not in DEVICE_UUIDS:
        known = ", ".join(sorted(DEVICE_UUIDS.keys()))
        raise SystemExit(f"Unknown model_prefix. Known: {known}")

    payload = build_on_off_cmd(args.action == "on")

    if args.all_ks03:
        targets = await find_all_ks03(timeout=args.timeout)
        if not targets:
            raise SystemExit("No KS03 devices found")
        # Send to each, picking correct UUID mapping by name prefix
        for addr, name in targets:
            prefix = "KS03~" if name.startswith("KS03~") else "KS03-"
            mapping = DEVICE_UUIDS[prefix]
            try:
                await write_command(addr, mapping["service"], mapping["write"], payload, verbose=args.verbose)
                print(f"Sent {args.action.upper()} to {addr} ({name})")
            except Exception as e:
                print(f"Failed to send to {addr} ({name}): {e}")
        return

    # Single-target behavior
    mapping = DEVICE_UUIDS[args.model_prefix]
    address = args.address
    if not address:
        address = await find_device_by_prefix(args.model_prefix, timeout=args.timeout)
        if not address:
            raise SystemExit(f"No device found with name starting '{args.model_prefix}'")

    await write_command(address, mapping["service"], mapping["write"], payload, verbose=args.verbose)
    print(f"Sent {args.action.upper()} to {address} ({args.model_prefix})")

if __name__ == "__main__":
    asyncio.run(main())
