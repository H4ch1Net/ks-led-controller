"""Validated local JSON storage. Invalid files are never silently overwritten."""
import json
import os
from pathlib import Path
import tempfile

from .protocol import byte


def validate_presets(data):
    if not isinstance(data, dict):
        raise ValueError("Presets must be an object")
    for name, rgb in data.items():
        if not isinstance(name, str) or not name.strip() or not isinstance(rgb, dict):
            raise ValueError("Each preset needs a name and RGB object")
        if set(rgb) != {"r", "g", "b"}:
            raise ValueError("Each preset must contain r, g and b only")
        for value in rgb.values():
            byte(value)
    return data


def validate_states(data):
    if not isinstance(data, dict):
        raise ValueError("State must be an object")
    for address, state in data.items():
        if not isinstance(address, str) or not address or not isinstance(state, dict):
            raise ValueError("Invalid device state")
        if set(state) != {"prefix", "rgb", "brightness", "confirmation"}:
            raise ValueError("Invalid state fields")
        if not isinstance(state["prefix"], str) or state["confirmation"] != "unconfirmed":
            raise ValueError("Invalid state metadata")
        if not isinstance(state["rgb"], list) or len(state["rgb"]) != 3:
            raise ValueError("Invalid RGB state")
        for value in state["rgb"]:
            byte(value)
        byte(state["brightness"])
    return data


def read_json(path, validator, default):
    path = Path(path)
    if not path.exists():
        return json.loads(json.dumps(default))
    try:
        return validator(json.loads(path.read_text(encoding="utf-8")))
    except (ValueError, TypeError) as error:
        raise ValueError(f"Invalid data in {path}: {error}") from error


def write_json(path, data, validator):
    validator(data)
    path = Path(path)
    # Preserve malformed existing data until the user explicitly repairs it.
    if path.exists():
        read_json(path, validator, {})
    path.parent.mkdir(parents=True, exist_ok=True)
    name = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         delete=False, suffix=".tmp") as file:
            name = file.name
            json.dump(data, file, indent=2)
            file.write("\n")
            file.flush()
            os.fsync(file.fileno())
        os.replace(name, path)
    finally:
        if name and os.path.exists(name):
            os.unlink(name)


class StateStore:
    """Last successfully sent RGB settings, not measured physical light state."""
    def __init__(self, path):
        self.path = Path(path)

    def get(self, address, prefix):
        state = read_json(self.path, validate_states, {}).get(address)
        return state if state and state["prefix"] == prefix else None

    def put(self, address, prefix, rgb, brightness):
        data = read_json(self.path, validate_states, {})
        data[address] = {"prefix": prefix, "rgb": list(rgb), "brightness": brightness,
                         "confirmation": "unconfirmed"}
        write_json(self.path, data, validate_states)
