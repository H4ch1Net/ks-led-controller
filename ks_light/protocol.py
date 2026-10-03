"""Validated encoders for inherited packet formats; no Bluetooth dependency."""


def byte(value):
    if type(value) is not int or not 0 <= value <= 255:
        raise ValueError("Channel values must be integers from 0 to 255")
    return value


def power(is_on):
    if type(is_on) is not bool:
        raise ValueError("Power must be a boolean")
    return bytes.fromhex("5BF001B5" if is_on else "5B0F01B5")


def color(r, g, b, device_type="ceiling", brightness=255):
    channels = bytes([byte(r), byte(g), byte(b)])
    byte(brightness)
    if device_type == "floor":
        return bytes.fromhex("5A0001") + channels + bytes([0, brightness, 0, 165])
    if device_type != "ceiling":
        raise ValueError("Unknown color protocol")
    if brightness != 255:
        raise ValueError("Independent brightness is unsupported by the standard RGB packet")
    return bytes.fromhex("7E070503") + channels + bytes.fromhex("00EF")


def white_brightness(value):
    return bytes.fromhex("5A000200000000") + bytes([byte(value), 0, 165])


# KS03~ firmware effects: the lamp animates these itself and keeps running after disconnect.
NATIVE_EFFECTS = {
    0x82: "Seven-color fade",
    0x83: "RGB fade",
    0x84: "Red breathing",
    0x85: "Green breathing",
    0x86: "Blue breathing",
    0x87: "Yellow breathing",
    0x88: "Cyan breathing",
    0x89: "Purple breathing",
    0x8A: "White breathing",
}
NATIVE_EFFECT_IDS = {name: effect for effect, name in NATIVE_EFFECTS.items()}


def native_effect(effect, speed, brightness):
    if effect not in NATIVE_EFFECTS or type(effect) is not int:
        raise ValueError("Unknown native effect")
    if type(speed) is not int or not 0 <= speed <= 100 or type(brightness) is not int or not 1 <= brightness <= 100:
        raise ValueError("Effect speed must be 0..100 and brightness 1..100")
    return bytes([0x5C, 0, effect, speed, brightness, 0, 0xC5])
