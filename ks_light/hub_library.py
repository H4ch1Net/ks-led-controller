"""Static hub groups and scenes, validated before accepting any commands."""
import copy
import json
from pathlib import Path
import re


def load_library(path):
    with Path(path).open("rb") as handle:
        raw = handle.read(262145)
    if len(raw) > 262144:
        raise ValueError("Hub library exceeds 256 KiB")
    return json.loads(raw.decode("utf-8-sig"))


def validate_library(data, lights, validate_command):
    if data is None:
        return {}, {}
    if (not isinstance(data, dict) or set(data) != {"version", "groups", "scenes"}
            or type(data["version"]) is not int or data["version"] != 1):
        raise ValueError("Invalid hub library")

    def entries(kind, fields):
        values = data[kind]
        if not isinstance(values, list) or len(values) > 32:
            raise ValueError("Library permits at most 32 groups and 32 scenes")
        result = {}
        for item in values:
            if (not isinstance(item, dict) or set(item) != fields
                    or not isinstance(item["id"], str) or not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", item["id"])
                    or not isinstance(item["name"], str) or not item["name"].strip() or len(item["name"]) > 80
                    or item["id"] in result):
                raise ValueError("Invalid or duplicate library entry")
            result[item["id"]] = copy.deepcopy(item)
        return result

    groups = entries("groups", {"id", "name", "members"})
    scenes = entries("scenes", {"id", "name", "actions"})
    for group in groups.values():
        members = group["members"]
        if (not isinstance(members, list) or not 1 <= len(members) <= 64
                or any(not isinstance(m, str) or m not in lights for m in members)
                or len(set(members)) != len(members)):
            raise ValueError("Group needs unique configured light IDs")
    for scene in scenes.values():
        actions = scene["actions"]
        if not isinstance(actions, list) or not 1 <= len(actions) <= 64:
            raise ValueError("Scene needs 1-64 actions")
        targets = set()
        for action in actions:
            if (not isinstance(action, dict) or set(action) != {"light", "type", "body"}
                    or not isinstance(action["light"], str) or action["light"] not in lights
                    or action["light"] in targets or action["type"] not in ("state", "native")
                    or not isinstance(action["body"], dict)):
                raise ValueError("Scene needs one valid action per configured light")
            # Scene meaning must not depend on an earlier remembered color.
            body = action["body"]
            if action["type"] == "state" and "brightness" in body and "rgb" not in body:
                raise ValueError("Scene brightness requires explicit RGB")
            validate_command(action["light"], action["type"], body)
            targets.add(action["light"])
    return groups, scenes
