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
