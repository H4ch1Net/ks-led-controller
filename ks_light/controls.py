"""Prepare RGB controls without guessing the current physical light state."""
from .profiles import DEVICE_MAPPINGS
from .protocol import color


def prepare_color(prefix, previous, rgb=None, brightness=None):
    if prefix not in DEVICE_MAPPINGS:
        raise ValueError("RGB controls are unavailable for this inherited profile")
    kind = DEVICE_MAPPINGS[prefix]["type"]
    if rgb is None:
        if previous is None:
            raise ValueError("No remembered color. Set an RGB color before adjusting brightness.")
        rgb = previous["rgb"]
    if brightness is None:
        brightness = previous["brightness"] if previous else 255
    payload = color(*rgb, device_type=kind, brightness=brightness)
    return payload, list(rgb), brightness
