"""Optional atomic last-sent snapshots. Never store pending commands or credentials."""
import json
import os
from pathlib import Path
import tempfile
from .api_errors import integer
from .profiles import DEVICE_MAPPINGS
from .calibration import gains, valid_gains, NEUTRAL


def valid_state(state, prefix):
    if not isinstance(state, dict) or not state or set(state) - {"power", "rgb", "brightness", "native_effect", "speed"}:
        return False
    if "power" in state and type(state["power"]) is not bool:
        return False
    if "native_effect" in state:
        return (prefix == "KS03~" and "rgb" not in state and integer(state["native_effect"], 0x82, 0x8a)
                and integer(state.get("speed"), 0, 100) and integer(state.get("brightness"), 1, 100))
    if "speed" in state:
        return False
    if "rgb" in state:
        rgb = state["rgb"]
        return (prefix in DEVICE_MAPPINGS and isinstance(rgb, list) and len(rgb) == 3
                and all(integer(v, 0, 255) for v in rgb) and integer(state.get("brightness"), 0, 100)
                and (prefix == "KS03~" or state["brightness"] == 100))
    return set(state) == {"power"}


class StateStore:
    def __init__(self, path, lights, simulation):
        self.path, self.lights = Path(path), lights
        self.mode = "simulation" if simulation else "ble"

    def load(self):
        if not self.path.exists():
            return {}
        with self.path.open("rb") as stream:
            raw = stream.read(65537)
        if len(raw) > 65536:
            raise ValueError("State snapshot too large")
        data = json.loads(raw)
        if (not isinstance(data, dict) or set(data) != {"version", "mode", "lights"}
                or type(data["version"]) is not int or data["version"] != 1
                or data["mode"] not in ("simulation", "ble") or not isinstance(data["lights"], dict)
                or len(data["lights"]) > 64):
            raise ValueError("Invalid state snapshot")
        if data["mode"] != self.mode:
            return {}
        restored = {}
        for key, entry in data["lights"].items():
            light = self.lights.get(key)
            if not light:
                continue
            if (not isinstance(entry, dict) or not {"address", "prefix", "state"} <= set(entry)
                    or set(entry) - {"address", "prefix", "state", "rgb_gains"}
                    or not valid_gains(entry.get("rgb_gains", NEUTRAL))):
                raise ValueError("Invalid saved light state")
            if (entry["address"] != light["address"] or entry["prefix"] != light["prefix"]
                    or entry.get("rgb_gains", NEUTRAL) != gains(light)):
                continue
            if not valid_state(entry["state"], light["prefix"]):
                raise ValueError("Invalid saved light state")
            restored[key] = entry["state"]
        return restored

    def save(self, states, pending):
        data = {"version": 1, "mode": self.mode, "lights": {
            key: {"address": self.lights[key]["address"], "prefix": self.lights[key]["prefix"], "state": state,
                  **({"rgb_gains": list(gains(self.lights[key]))} if gains(self.lights[key]) != NEUTRAL else {})}
            for key, state in states.items() if key not in pending}}
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=self.path.parent,
                    prefix=self.path.name + ".", suffix=".tmp", delete=False) as stream:
                temporary = Path(stream.name)
                json.dump(data, stream, separators=(",", ":"))
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, self.path)
            if os.name != "nt":
                directory = os.open(self.path.parent, os.O_RDONLY | os.O_DIRECTORY)
                try:
                    os.fsync(directory)
                finally:
                    os.close(directory)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
