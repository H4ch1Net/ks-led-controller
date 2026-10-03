# Development

Read [ARCHITECTURE.md](ARCHITECTURE.md) and [PROTOCOL_AND_TESTING.md](PROTOCOL_AND_TESTING.md) before changing behavior.

## Python

Python 3.10 or newer. Direct dependencies are in `requirements.txt` (bleak, aiohttp, aiomqtt), `requirements-gpio.txt` (adds gpiozero) and `requirements-controllers.txt` (adds pyserial). The `.lock` files pin all transitive packages with hashes.

```sh
python -m venv .venv
.venv/bin/python -m pip install --require-hashes -r requirements-controllers.lock   # or requirements.lock for hub/CLI only
.venv/bin/python -m pip check
.venv/bin/python -m unittest discover -s tests -v
.venv/bin/python -m ks_light.simulator
```

On Windows use `.venv\Scripts\python.exe`. Tests never touch Bluetooth.

Run a hub for client development with `python -m ks_light.hub` (simulation by default; see [HUB_API.md](HUB_API.md)).

### Updating locks

Locks were generated with uv for Python 3.10+:

```sh
uv pip compile requirements.txt --universal --python-version 3.10 --generate-hashes --output-file requirements.lock
uv pip compile requirements-controllers.txt --universal --python-version 3.10 --generate-hashes --output-file requirements-controllers.lock
```

Review the diff before installing.

## Other components

| Component | Guide |
| --- | --- |
| Android | [apps/android/README.md](../apps/android/README.md) |
| Stream Deck | [STREAM_DECK.md](STREAM_DECK.md#build) |
| ESP32 | [apps/esp32/README.md](../apps/esp32/README.md) |

## Continuous integration

Workflows in `.github/workflows` run on pull requests and pushes to `main`:

| Workflow | Checks |
| --- | --- |
| `tests.yml` | Python 3.10 and 3.12 on Ubuntu and Windows: locked install, `pip check`, unit tests, simulator |
| `android.yml` | Pinned Flutter: lockfile, analyze, tests, Dart-to-Python hub smoke, debug APK, native unit tests, release assembly with a throwaway key |
| `streamdeck.yml` | Windows: npm tests, build, manifest validation, end-to-end smoke, pack |
| `esp32.yml` | Portable C++ tests and all PlatformIO environments |
| `source-package.yml` | Builds the source archive on Ubuntu and Windows and compares the bytes |

## Conventions

- Do not add device commands without recorded evidence ([PROTOCOL_AND_TESTING.md](PROTOCOL_AND_TESTING.md#evidence-policy)).
- Keep physical tests separate from unit and simulator results; record hardware results in [HARDWARE_TESTING.md](HARDWARE_TESTING.md) only when observed.
- New user-visible behavior that sends commands must not resend on failure, on restart or on configuration changes.
- Never put tokens, keys, Wi-Fi credentials or device addresses in tracked files. Private configuration belongs in ignored paths such as `.hub-local/`.
- New tracked files must be added to `release/source-files.json` (see [release/README.md](../release/README.md)).
