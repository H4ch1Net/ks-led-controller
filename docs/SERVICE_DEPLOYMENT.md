# Running the hub as a service

`python -m ks_light.service` runs a hub from a configuration file, with secrets in files, an instance lock, rotating logs and optional HTTPS, MQTT, persistence, library and scoped credentials. Use it for unattended operation on Windows, Linux or a Raspberry Pi. The API itself is described in [HUB_API.md](HUB_API.md).

## Configure

1. Create a private directory outside the repository, readable only by the account that runs the hub.
2. Copy `deploy/hub.example.json` to `hub.json` and `deploy/lights.example.json` to `lights.json` in that directory.
3. Create `api-token.txt` with one line: a random token of at least 32 non-whitespace ASCII characters. For example `python -c "import secrets; print(secrets.token_urlsafe(32))" > api-token.txt`.
4. Start in `simulation` mode, then switch to `ble` with real addresses once everything works.

All paths are resolved relative to `hub.json`. Unknown fields are rejected.

| Field | Required | Meaning |
| --- | --- | --- |
| `version` | yes | `1` |
| `mode` | yes | `simulation` or `ble` |
| `port` | yes | TCP port, for example 8765 |
| `lights_file` | yes | Light catalog ([format](HUB_API.md#light-catalog)) |
| `token_file` | yes | Operator token file |
| `runtime_dir` | yes | Log, lock, MQTT manifest and persisted state |
| `listen_host` | no | IP address to bind; default `127.0.0.1`. A non-loopback address requires `tls`. |
| `tls` | no | `{"cert_file": "...", "key_file": "..."}` |
| `mqtt` | no | MQTT bridge, see below |
| `persist_state` | no | `true` to save last-sent state; default `false` |
| `dashboard` | no | `false` to stop serving the browser dashboard; default `true` ([HUB_API.md](HUB_API.md#dashboard)) |
| `library_file` | no | Group and scene library ([HUB_LIBRARY.md](HUB_LIBRARY.md)) |
| `credentials_file` | no | Scoped controller credentials ([HUB_API.md](HUB_API.md#scoped-credentials)) |

Validate, then run:

```sh
python -m ks_light.service --config /path/to/hub.json --check
python -m ks_light.service --config /path/to/hub.json
```

`--check` loads and validates the configuration, catalog, secrets, TLS files, library, credentials and any existing state snapshot. It makes no network or Bluetooth connections and writes nothing. It does not test broker connectivity, directory permissions or Bluetooth availability. Setup errors name the cause (a file, a JSON position or a validation message) without echoing file contents or secrets.

Restart the service after changing configuration or secret files. The light catalog and library can also be changed through the API (see [HUB_API.md](HUB_API.md#calibration) and [HUB_LIBRARY.md](HUB_LIBRARY.md#editing-through-the-api)).

### MQTT

```json
"mqtt": {"hostname": "broker.local", "hub_id": "ks-light", "port": 1883, "tls": false}
```

Optional keys: `username`, `password_file` (requires `username`), `ca_file` (requires `tls: true`). Set `port` explicitly when using TLS. The discovery manifest is kept at `runtime_dir/discovery.json`. See [HOME_ASSISTANT.md](HOME_ASSISTANT.md).

### HTTPS listener

To accept connections from other devices, set `listen_host` to the host's IP address and add `tls` (example: `deploy/hub-https.example.json`). The server requires TLS 1.2 or newer and never falls back to plain HTTP. The private key must be unencrypted and protected by file permissions.

Clients (Android, controllers, ESP32) validate the certificate chain and hostname. Use a certificate trusted by those devices and matching the name or IP they connect to; a self-signed certificate on the server alone is not enough. The hub does not configure firewalls, DNS or port forwarding. Do not expose it to the internet.

The foreground `python -m ks_light.hub` command always binds loopback and has no TLS option.

## Windows

```powershell
./deploy/install-windows-task.ps1 -Config C:\path\to\hub.json [-TaskName "KS Light Hub"]
```

The script requires the repository `.venv`, runs `--check`, refuses to replace an existing task, and registers a current-user logon task that runs `pythonw.exe -m ks_light.service`. It does not start the task, store a password or request elevation. The task restarts a failed process up to five times at one-minute intervals and never runs two instances.

This is a logon task, not a machine service: it stops at logoff. Start, stop and disable it in Task Scheduler. Stopping the hub does not turn lamps off.

## Linux and Raspberry Pi (systemd)

`deploy/ks-light.service` assumes:

- repository and virtual environment at `/opt/ks-light`
- configuration at `/etc/ks-light/hub.json`
- a dedicated `kslight` account with access to the configuration, secrets, `runtime_dir` (for example `/var/lib/ks-light`) and the Bluetooth adapter (BlueZ permissions vary by distribution)

The unit runs `--check` before start, restarts on failure after 15 seconds (at most five starts in five minutes), allows 30 seconds to stop, and sets `UMask=0077` and `NoNewPrivileges`. Adapt paths, then install and enable it with systemd. Setup failures appear in the journal; runtime messages go to the hub log.

## Runtime directory

| File | Purpose |
| --- | --- |
| `hub.log` | Log, rotated at 1 MiB with three backups. May contain device addresses; keep private. HTTP access logging is off. |
| `hub.lock` | OS-held lock preventing two hubs on one runtime directory. Released automatically on exit or crash. Do not delete it while the hub runs. |
| `discovery.json` | MQTT discovery manifest. Preserve it so removed lights can be cleaned up. |
| `last-sent.json` | Persisted state, only with `persist_state`. |

The lock does not coordinate with Android, Home Assistant integrations or another runtime directory. Keep one Bluetooth owner per lamp by configuration.

## Restart behavior

A restart never replays commands and always changes the instance ID, so event clients resynchronize. Operations and idempotency keys are memory only. Built-in lamp effects keep running after the hub stops.

Without persistence, every light starts with unknown state. Brightness-only commands are then rejected until a color or effect is sent.

### Persisted last-sent state

With `"persist_state": true`, `runtime_dir/last-sent.json` holds per-light last-sent power, color, effect and brightness, tied to the light's address, profile, calibration gains and simulation/BLE mode. It holds no pending commands, operations or credentials.

- On startup, a light's state is restored only if address, profile, mode and gains still match; otherwise it starts unknown. Restored lights report `restored: true` and stay `unconfirmed`. Startup sends nothing.
- Before each write the light is removed from the snapshot; after a successful write the new state is saved. A crash during a write therefore restores that light as unknown rather than with stale state.
- A storage failure before sending fails the command without a write. A failure after sending keeps the result in memory and marks persistence degraded in `/health`. Nothing is retried.
- A corrupt or oversized (over 64 KiB) snapshot stops startup. Stop the service and move the file aside to reset.
- Writes use a temporary file, fsync and atomic replace. Protection against power loss depends on the OS and storage.

### Health

`GET /api/v1/health` reports MQTT state and persistence status; see [HUB_API.md](HUB_API.md#health-and-capabilities). HTTP keeps working during MQTT outages, and the bridge reconnects on its own. An unexpected bridge failure is reported as `failed` and needs a process restart; there is no health-based supervisor.
