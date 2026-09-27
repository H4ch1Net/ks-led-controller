"""Configure an already-flashed KS Light ESP32 through an explicitly selected USB port."""
import argparse
import json
from pathlib import Path
import re
import time
from urllib.parse import urlsplit


FIELDS = {"wifi_ssid", "wifi_password", "hub_origin", "hub_token", "light_id", "hub_ca", "ntp_host"}


def setup_packet(command, settings=None):
    if command not in {"status", "configure", "forget"}:
        raise ValueError("Invalid setup command")
    data = {"command": command}
    if command == "configure":
        if not isinstance(settings, dict) or set(settings) != FIELDS or any(
                not isinstance(value, str) or "\0" in value for value in settings.values()):
            raise ValueError("Configuration needs exactly the documented string fields")
        origin = settings["hub_origin"]
        url = urlsplit(origin)
        if url.scheme != "https" or not url.hostname or url.path or url.query or url.fragment or url.username or url.password:
            raise ValueError("Hub origin must be HTTPS without a path or credentials")
        limits = {"wifi_ssid": (1, 32), "wifi_password": (0, 63), "hub_origin": (9, 256),
                  "hub_token": (32, 512), "hub_ca": (1, 4096), "ntp_host": (1, 253)}
        if any(not low <= len(settings[key].encode("utf-8")) <= high for key, (low, high) in limits.items()):
            raise ValueError("Configuration field exceeds its size limit")
        if any(any(ord(c) <= 32 or ord(c) >= 127 for c in settings[key]) for key in ("hub_token", "hub_origin", "ntp_host")):
            raise ValueError("Origin, token and time server must use non-space ASCII")
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", settings["light_id"]):
            raise ValueError("Invalid light ID")
        if not settings["hub_ca"].startswith("-----BEGIN CERTIFICATE-----") or "-----END CERTIFICATE-----" not in settings["hub_ca"] or "REPLACE_" in settings["hub_ca"]:
            raise ValueError("Supply the hub's trusted PEM CA certificate")
        if settings["wifi_ssid"] == "CHANGE_ME":
            raise ValueError("Replace placeholder settings")
        data["settings"] = settings
    packet = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8") + b"\n"
    if len(packet) > 8193:
        raise ValueError("Setup request exceeds 8192 bytes")
    return packet


def exchange(port, packet, timeout=12):
    """Send once. Unknown completion is inspected with status, never auto-replayed."""
    if port.write(packet) != len(packet):
        raise OSError("Incomplete setup write")
    port.flush()
    deadline = time.monotonic() + timeout
    # Only emit known status labels; no serial logs or credentials are relayed.
    allowed = {"saved", "forgotten", "dry-run", "unconfigured", "busy", "connected", "offline",
               "invalid", "invalid-or-unsaved", "storage-failed", "expired"}
    while time.monotonic() < deadline:
        raw = port.read_until(b"\n", 256)
        if not raw.endswith(b"\n"):
            continue
        text = raw.decode("ascii", errors="replace").strip()
        if text.startswith("KS_SETUP ") and text[9:] in allowed:
            return text[9:]
    raise TimeoutError("No setup acknowledgment; check status before trying again")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="Explicit serial port, such as COM7; never auto-detected")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--config", help="Private UTF-8 JSON settings file")
    mode.add_argument("--status", action="store_true")
    mode.add_argument("--forget", action="store_true", help="Disable and erase the active stored connection")
    args = parser.parse_args()
    try:
        settings = None
        if args.config:
            with Path(args.config).open("rb") as source:
                raw = source.read(8193)
            if len(raw) > 8192:
                raise ValueError("Configuration file exceeds 8192 bytes")
            settings = json.loads(raw.decode("utf-8-sig"))
        packet = setup_packet("configure" if args.config else "forget" if args.forget else "status", settings)
        import serial  # Optional dependency; already included with PlatformIO.
        port = serial.Serial(port=None, baudrate=115200, timeout=0.5, write_timeout=3)
        port.dtr = False
        port.rts = False
        port.port = args.port
        with port:
            time.sleep(2)  # Boards may reset when their USB port opens.
            port.reset_input_buffer()
            result = exchange(port, packet)
        print("ESP32 setup: " + result)
        return 0 if result in {"saved", "forgotten", "dry-run", "unconfigured", "connected", "offline"} else 1
    except ImportError:
        print("Install pyserial or use the PlatformIO Python environment.")
    except (OSError, ValueError, TimeoutError):
        print("Setup unavailable or not acknowledged. Check the file/port and request status; no automatic retry was made.")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
