"""RGB gains matching Android's positive half-up rounding; no transport work."""
import math

NEUTRAL = [1, 1, 1]
PRESETS = {'Neutral': [1, 1, 1], 'Less blue': [1, 1, .75],
           'Less red': [.75, 1, 1], 'Less green': [1, .75, 1], 'Purple trial': [1, .3, .75]}


def valid_gains(value):
    return (isinstance(value, list) and len(value) == 3
            and all(type(v) in (int, float) and math.isfinite(v) and 0 <= v <= 1 for v in value))


def gains(light):
    return light.get("calibration", {}).get("rgb_gains", NEUTRAL)


def valid_calibration(value):
    if (not isinstance(value, dict) or 'rgb_gains' not in value or
            set(value) - {'rgb_gains', 'presets'} or not valid_gains(value['rgb_gains'])):
        return False
    presets = value.get('presets', {})
    return (isinstance(presets, dict) and len(presets) <= 20 and
            all(isinstance(name, str) and name.strip() and 1 <= len(name) <= 40 and valid_gains(balance)
                for name, balance in presets.items()))


def apply(rgb, balance):
    # Inputs were validated at the configuration and command boundaries.
    # Python round() uses ties-to-even; Dart round() uses half-up here.
    return [min(255, max(0, int(channel * gain + 0.5))) for channel, gain in zip(rgb, balance)]
