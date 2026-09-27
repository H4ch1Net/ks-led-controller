"""Atomic JSON configuration replacement; callers validate before writing."""
import hashlib
import json
import os
from pathlib import Path
import tempfile


def load_json(path):
    with Path(path).open('rb') as handle:
        raw = handle.read(262145)
    if len(raw) > 262144:
        raise ValueError('Configuration exceeds 256 KiB')
    return json.loads(raw.decode('utf-8-sig'))


def revision(value):
    return '"' + hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest() + '"'


def save_json(path, value):
    path = Path(path)
    fd, temporary = tempfile.mkstemp(prefix='.ks-config-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            json.dump(value, handle, indent=2)
            handle.flush(); os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)
