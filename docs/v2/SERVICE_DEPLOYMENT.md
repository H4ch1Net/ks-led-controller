# Continuous hub operation

The configured runner is implemented and tested on Windows. Windows logon-task registration/execution and the Linux service template have not been deployed. No automatic BLE controller was enabled; the existing Home Assistant integration retains ownership.

## Configuration
Create a private directory outside the repository. Copy deploy/hub.example.json to hub.json and deploy/lights.example.json to lights.json there. Begin in simulation mode. All paths resolve relative to the configuration file, independent of the current directory.

Create api-token.txt containing a randomly generated token of at least 32 ASCII characters, without spaces. Generate it locally without printing it; protect the directory and secret with account-only filesystem permissions. Secrets are plaintext files, never process arguments. Keep them out of source control and shared bundles.

Run from the repository with its virtual-environment Python:

```text
python -m ks_light.service --config PATH_TO_HUB_JSON --check
python -m ks_light.service --config PATH_TO_HUB_JSON
```

Preflight validates schema, catalog, credentials, TLS configuration and the discovery manifest without network/BLE connections or runtime writes. It does not test broker connectivity, directory writability or Bluetooth availability. Unknown configuration fields are rejected.

Add optional MQTT configuration:

```json
{"hostname":"YOUR_BROKER","hub_id":"ks-light","port":1883,"tls":false}
```

This object belongs under the config's mqtt key. Optional username, password_file and ca_file keys are supported. A password requires a username; a CA file requires TLS. Specify the TLS port explicitly. Secret files contain one line and load at startup. Restart after changing configuration or credentials.

For hardware, change mode to ble and use real catalog addresses after pausing other direct controllers. Use one stable hub ID and runtime directory. The runtime lock cannot coordinate Android, the original HA integration, or another configuration directory. Android includes an initial separate hub-control screen. The HTTP API defaults to loopback. Optional HTTPS listening is described below; remote deployment is explicit.

## Windows deployment helper
deploy/install-windows-task.ps1 accepts a required Config path and optional TaskName (default KS Light Hub). It validates configuration, refuses to overwrite an existing task, and registers an interactive current-user logon task without starting it. It uses pythonw.exe from the repo virtual environment and does not store an account password or request elevation.

Start, stop, disable and inspect the registered task in Task Scheduler. The task retries failed processes up to five times at one-minute intervals and disallows concurrent instances. This is a logon task, not a machine service; logoff and normal scheduler power conditions apply. Scheduler termination can be abrupt: the OS releases the lock and MQTT's last will reports offline after broker detection. Stopping the hub does not turn the lamp off. A console instance supports Ctrl+C for normal application cleanup.

The installer passed PowerShell syntax parsing. Actual registration and future-logon execution remain untested.

## Raspberry Pi / Linux template
deploy/ks-light.service assumes the repo/virtual environment at /opt/ks-light, config at /etc/ks-light/hub.json and a pre-created kslight account. Set runtime_dir to /var/lib/ks-light and grant that account access to its runtime directory, configuration, secrets and Bluetooth adapter. BlueZ permissions depend on the distribution.

Adapt and validate those paths and permissions before installing/enabling the unit through systemd. The template restarts failed processes after 15 seconds, bounded by five starts per five minutes, and allows 30 seconds for graceful stop. Inspect the systemd journal for setup failures and runtime logs for normal operation. The template has not been run on a Pi. The Python runner does not install software, change privileges or activate services.

## Runtime and recovery
The runtime directory holds hub.log plus up to three rotated 1 MiB backups, hub.lock and, with MQTT enabled, discovery.json. Preserve the discovery manifest across restarts. Never remove an active lock file; OS lock ownership releases automatically on exit/crash.

Authenticated GET /api/v1/health reports MQTT state and sanitized errors. HTTP remains available during MQTT outages. Service managers restart failed processes; MQTT outages use the bridge reconnect loop. An unexpected MQTT task failure is reported as failed and currently requires a process restart; no health-based process supervisor is implemented.

Restart never replays commands and always changes the instance ID. By default last-sent state remains memory-only and starts unknown. Optional last-sent persistence is described below; retry/operation records remain memory-only. Native effects can continue on the lamp after hub shutdown. Logs may contain device addresses and should stay private. HTTP access logs are disabled; setup errors never print configuration contents or credentials.

## Validation
87 Python tests pass, including schema/path/secret handling, read-only preflight, cross-process duplicate rejection and lock release. A separate-process simulator smoke test verified authenticated command completion, duplicate-service rejection, forced termination/restart recovery, unknown state after restart, and absence of the API token in logs. Android is unchanged.

References: [Microsoft Task Scheduler settings](https://learn.microsoft.com/en-us/windows/win32/taskschd/tasksettings), [systemd service lifecycle](https://github.com/systemd/systemd/blob/main/man/systemd.service.xml).


## Optional HTTPS listener (2026-09-22)
The configured service accepts `listen_host` as an explicit IP address, defaulting to 127.0.0.1. A non-loopback address requires a `tls` object containing exactly `cert_file` and `key_file`. See deploy/hub-https.example.json and replace its example address. Certificate/key paths resolve relative to the config. The server requires TLS 1.2 or newer, loads the certificate/key during preflight, and does not fall back to plaintext if loading fails. Use an unencrypted private-key file protected by filesystem permissions; unattended passphrase prompting is disabled.

Use a certificate chain trusted by the phone and matching the DNS name or IP entered in the app. Installing an arbitrary self-signed certificate on the server is insufficient; Android still validates trust and hostname. No trust bypass, certificate enrollment, DNS record, port forwarding, firewall rule or remote listener was deployed during this implementation. A trusted-name/certificate setup and wireless phone acceptance remain open. The plain `ks_light.hub` CLI retains its original loopback-only behavior; HTTPS options belong to the configured `ks_light.service` runner.

Validation: 89 Python tests pass. A temporary loopback TLS service passed a real verified HTTPS handshake and bearer-authenticated health request. Missing authorization returned 401, and a client without trust for the temporary test certificate rejected it. Test keys were temporary and removed afterward.


## Optional last-sent persistence (2026-09-26)

Add `"persist_state": true` to the configured service JSON to save `runtime_dir/last-sent.json`. Default is false; no running deployment was changed. This snapshot contains per-light last-sent color, effect, brightness and power metadata, with device address/profile and simulation/BLE mode identity. It contains no commands waiting to be sent, operation/retry records or credentials. Treat the file as private device metadata.

Startup restores matching IDs only when address, profile and mode also match. Changed devices and mode switches start unknown. Restored values have `restored: true` in the light API response and remain `confirmation: unconfirmed` in BLE mode. They can be stale if another controller changed the lamp. Startup sends nothing; restoring color/effect merely permits later explicit partial brightness requests to use remembered settings. A successful new write clears the restored flag.

Before transport, the target is removed from the disk snapshot. After successful transport, the new last-sent state is atomically saved. Concurrent pending lights remain omitted. A storage failure before transport fails the operation without a light write; a failure afterward preserves successful delivery in memory and reports persistence degradation without retrying. Thus process interruption during transport or post-send save failure restores that target as unknown instead of resurrecting its older command. The instance lock is acquired before runtime restore.

`GET /api/v1/health` includes `persistence.enabled` and `persistence.status`; a storage error makes overall status degraded. `GET /api/v1/capabilities` includes `durable_last_sent`. Operations are never replayed after restart, and old idempotency keys are not retained. API clients must continue treating an uncertain submission as potentially delivered.

Preflight remains read-only, checks an existing snapshot, and creates no runtime directory. Corrupt/oversized snapshots fail startup rather than being silently discarded. Stop the service and preserve/inspect the snapshot before manually moving it aside if you choose to reset remembered state. Snapshot writes use a temporary file, flush/fsync, atomic replacement and a directory sync on POSIX. Power-loss guarantees still depend on the OS/filesystem/storage; this is tested for process termination, not a power cut. Synchronous small snapshot writes add disk latency, so persistence is optional.

Validation: full 127-test Python suite passed, including an actual-service subprocess test for forced stop/restart, restored metadata, new instance identity and zero replay events. Tests include color/native-effect restore, mode/device isolation, corrupt/oversized snapshots, pre/post-send disk failures, concurrent target snapshots and read-only preflight. No physical BLE command was sent; mock senders and simulation were used.

## Optional group and scene library
Set `library_file` to a JSON path relative to the service configuration. See HUB_LIBRARY.md and examples/hub-library.example.json. `--check` validates all members and scene capabilities without sending commands. Definitions load on startup; editing the file requires a service restart. No scene is recalled at startup. Existing configurations without a library remain valid.

Per-light optional RGB gains live in the light catalog, not the service token file. Invalid gains fail `--check`. A changed balance invalidates matching restored last-sent metadata; legacy neutral snapshots remain readable. See HUB_API.md. Restarting never sends a calibration or color command.
