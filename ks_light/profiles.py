"""Single profile registry; mappings are inherited, not hardware-certified."""
import json
from pathlib import Path

PROFILES = json.loads(Path(__file__).with_name("profiles.json").read_text(encoding="utf-8"))
DEVICE_UUIDS = {p["prefix"]: {"service": p["service"], "write": p["write"]} for p in PROFILES}
DEVICE_MAPPINGS = {p["prefix"]: {**DEVICE_UUIDS[p["prefix"]], "type": p["color_type"]}
                   for p in PROFILES if p["color_type"] is not None}
