"""Shared validation errors for HTTP and MQTT entry points."""
class APIError(Exception):
    def __init__(self, status, code):
        self.status, self.code = status, code


def integer(value, low, high):
    return type(value) is int and low <= value <= high
