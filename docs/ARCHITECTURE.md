# Architecture

## Components

```text
Android app ──────────── direct BLE ──────────────┐
                                                   ├──> KS lights
Android hub mode ─┐                                │
Stream Deck ──────┤                                │
Keyboard launchers┼── HTTP(S) API ──> KS Light hub ┘
Raspberry Pi GPIO ┤                     ▲
ESP32 firmware ───┘                     │
Home Assistant ──── MQTT broker ────────┘
```

- **Android app** (Flutter/Dart, `apps/android`): direct BLE control, or a client of the hub. Native Kotlin code provides widgets, the Quick Settings tile and Device Controls.
- **Hub** (Python, `ks_light/hub.py`, `ks_light/service.py`): owns BLE for its configured lights and exposes the HTTP API and MQTT bridge. Runs on Windows, Linux or a Raspberry Pi.
- **Controller clients** (`ks_light/controller.py`, `streamdeck.py`, `gpio_controller.py`, `apps/streamdeck`, `apps/esp32`): send named or typed actions to the hub.
- **Direct CLI** (`led_control.py`, `led_menu.py`): standalone BLE tools for a computer.

Python and Dart share protocol data (`ks_light/profiles.json`, `protocol/golden_packets.json`); Python is not embedded in Android.

## Repository layout

| Path | Contents |
| --- | --- |
| `ks_light/` | Protocol encoders, profiles, BLE transport and session pool, command queue, hub, MQTT bridge, service runner, controllers, packaging tools |
| `led_control.py`, `led_menu.py` | Direct Bluetooth CLI and menu |
| `apps/android/` | Flutter app |
| `apps/streamdeck/` | Stream Deck plugin (JavaScript/TypeScript) |
| `apps/esp32/` | ESP32 firmware (PlatformIO) |
| `protocol/` | Language-neutral packet fixtures |
| `examples/` | Hub catalogs, library, controller and GPIO configurations |
| `deploy/` | Service example configs, systemd unit, Windows scripts |
| `release/` | Source package inventory and Android toolchain pins |
| `tests/` | Python tests |

## Principles

- **One Bluetooth owner per lamp.** A lamp is controlled either by the phone directly or by one hub. Hub clients never open their own BLE connections. This is a convention: nothing can stop the vendor app or another integration from connecting.
- **No readback.** The firmware does not report state, so every surface shows last-sent state and labels it as such (`unconfirmed`, `simulated`, `restored`). A failed write clears the remembered state because a partial write may have landed.
- **No automatic replay.** A command whose outcome is uncertain is reported, never retried. Restarts never resend commands or resume effects. Retained MQTT commands are rejected.
- **Explicit consent for output.** Color commands that can turn a lamp on require `power: true` in the API. Previews, configuration changes, imports and startup send nothing.
- **Best-effort groups.** Group and scene delivery reports per-light results and is never atomic or synchronized.
- **Local only.** No cloud service or account. The hub binds loopback by default; LAN access requires TLS. Secrets live in files or Android Keystore, never in command arguments or logs.

## Command execution

`ks_light/queue.py` provides `CommandQueue(sender)`, used by the hub:

- Each target runs commands in order; different targets run concurrently up to a global limit (default 2).
- Each target holds up to 8 pending commands; a running command is extra. Up to 64 targets.
- `submit(target, command, key=None)` returns a future resolving to `Result(status, error)`, where status is `succeeded`, `failed`, `cancelled`, `superseded` or `rejected`. `succeeded` describes delivery only.
- A `key` marks replaceable absolute values (slider positions, effect frames): a newer submission with the same key replaces the pending one. Never use keys for toggles, relative steps or distinct transactions. The hub does not coalesce API commands.
- A failure discards the target's pending work and advances its generation. `invalidate(target)` does the same on demand and cancels the active send, so late frames from an old producer are rejected.
- `submit_batch` admits all commands of a group or scene or none of them.
- `close()` rejects new work, cancels pending work and waits for sender cleanup.

The hub's BLE sender (`ks_light/ble_pool.py`) keeps at most two sessions open, reuses an idle session for 30 seconds, spaces packets by 100 ms, and discards a session after any failure without replaying the command.

`SimulatedTransport` in `ks_light/simulator.py` models offline and hanging targets for tests. It does not model the radio, firmware or color output.

## State and persistence

| Where | What | Storage |
| --- | --- | --- |
| Hub | Operations, idempotency keys, events | Memory, bounded |
| Hub | Last-sent state per light | Memory; optional atomic JSON snapshot |
| Hub | Catalog, library, credentials | JSON files, atomic replace, ETag-checked API edits |
| Android | Catalog, names, calibration, rooms, scenes, presets, effects, theme | SharedPreferences, separate keys per feature; corrupt data is preserved, not overwritten |
| Android | Hub pairing | Keystore-encrypted file in the no-backup directory |
| CLI | Last-sent color, presets, nicknames | JSON files in the home directory |

## Scope

Supported: Android direct control and shortcuts, rooms, scenes and effects; the hub with HTTP API, MQTT and Home Assistant discovery; Stream Deck; keyboard launchers; experimental Raspberry Pi and ESP32 controllers. Distribution is through GitHub Releases.

Not provided: iOS, Google Play builds, cloud or remote access, device readback, firmware updates, synchronized multi-light effects, schedules, WebSocket events, music-reactive effects, or a native (non-MQTT) Home Assistant integration.
