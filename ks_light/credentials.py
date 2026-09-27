"""Additional controller credentials: hashes on disk, reloaded per request."""
import hashlib
import hmac
import json
from pathlib import Path
import re
import argparse
import os
import secrets
import tempfile


def load_credentials(path, lights):
    with Path(path).open('rb') as handle:
        raw = handle.read(65537)
    if len(raw) > 65536:
        raise ValueError('Credentials file too large')
    data = json.loads(raw.decode('utf-8-sig'))
    if (not isinstance(data, dict) or set(data) != {'version', 'credentials'} or
            type(data['version']) is not int or data['version'] != 1 or
            not isinstance(data['credentials'], list) or len(data['credentials']) > 64):
        raise ValueError('Invalid credentials file')
    ids, hashes = set(), set()
    for item in data['credentials']:
        if (not isinstance(item, dict) or set(item) != {'id', 'sha256', 'scope', 'lights'} or
                not isinstance(item['id'], str) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,64}', item['id']) or
                item['id'] in ids or not isinstance(item['sha256'], str) or
                not re.fullmatch(r'[a-f0-9]{64}', item['sha256']) or item['sha256'] in hashes or
                item['scope'] not in ('read', 'control') or not isinstance(item['lights'], list) or
                not 1 <= len(item['lights']) <= 64 or
                any(not isinstance(light, str) or light not in lights for light in item['lights']) or
                len(set(item['lights'])) != len(item['lights'])):
            raise ValueError('Invalid controller credential')
        ids.add(item['id']); hashes.add(item['sha256'])
    return data['credentials']


def authenticate(path, token, lights):
    if not isinstance(token, str) or not 32 <= len(token) <= 4096 or not token.isascii() or any(c.isspace() for c in token):
        return None
    digest = hashlib.sha256(token.encode('ascii')).hexdigest()
    for item in load_credentials(path, lights):
        if hmac.compare_digest(digest, item['sha256']):
            return item
    return None


def update_file(path, records):
    path = Path(path)
    descriptor, temporary = tempfile.mkstemp(prefix='.credentials-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8') as handle:
            json.dump({'version': 1, 'credentials': records}, handle, indent=2)
            handle.flush(); os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description='Create or revoke scoped hub credentials without printing secrets. Use one configuration writer at a time.')
    parser.add_argument('--file', required=True, help='Private credential-hash JSON file')
    parser.add_argument('--catalog', required=True, help='Hub light catalog JSON')
    parser.add_argument('--id', required=True)
    parser.add_argument('--revoke', action='store_true')
    parser.add_argument('--scope', choices=['read', 'control'], default='control')
    parser.add_argument('--lights', nargs='+')
    parser.add_argument('--token-out', help='New private token file; existing files are never overwritten')
    args = parser.parse_args()
    try:
        from .hub import validate_lights
        lights = validate_lights(json.loads(Path(args.catalog).read_text(encoding='utf-8-sig'))['lights'])
        records = load_credentials(args.file, lights) if Path(args.file).exists() else []
        if args.revoke:
            if args.token_out or args.lights or not any(record['id'] == args.id for record in records):
                raise ValueError('Invalid revocation')
            records = [record for record in records if record['id'] != args.id]
        else:
            if (not args.token_out or not args.lights or len(records) >= 64 or
                    not re.fullmatch(r'[a-zA-Z0-9_-]{1,64}', args.id) or any(record['id'] == args.id for record in records) or
                    len(set(args.lights)) != len(args.lights) or any(light not in lights for light in args.lights)):
                raise ValueError('Invalid credential configuration')
            token = secrets.token_urlsafe(32)
            records.append({'id': args.id, 'sha256': hashlib.sha256(token.encode()).hexdigest(), 'scope': args.scope, 'lights': args.lights})
            if len(json.dumps({'version': 1, 'credentials': records}, indent=2).encode('utf-8')) > 65536:
                raise ValueError('Credentials file too large')
            descriptor = os.open(args.token_out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, 'w', encoding='utf-8') as handle:
                handle.write(token + '\n')
        update_file(args.file, records)
    except (ValueError, OSError, KeyError, TypeError):
        parser.exit(2, 'Credential update failed. Check paths, unique ID, scope and light IDs. An existing token file is never overwritten.\n')
    print('Credential revoked for future requests.' if args.revoke else 'Credential created. The token is in the selected private file; it was not printed.')


if __name__ == '__main__':
    main()
