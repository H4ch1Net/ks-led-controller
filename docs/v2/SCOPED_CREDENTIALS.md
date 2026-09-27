# Scoped controller credentials

The existing operator token keeps full access. An optional credential file provides separate controller tokens with `read` or `control` scope and an explicit list of allowed light IDs. Control includes read access. This is local configuration management; there is no remote token-management endpoint.

Create a credential from the repository root using a private directory that already exists:

```powershell
.venv/Scripts/python.exe -m ks_light.credentials --file .hub-local/credentials.json --catalog .hub-local/lights.json --id streamdeck --scope control --lights desk --token-out .hub-local/streamdeck-token
```

Use the generated token file in that controller's configuration. The command never prints the token or overwrites an existing token file. The registry stores SHA-256 hashes of randomly generated 256-bit tokens. Keep the registry and token files private. Use one configuration writer at a time. If a filesystem failure interrupts creation, check the output paths before trying again; an orphan token file is not authorization by itself.

Enable the registry with service configuration `"credentials_file": "credentials.json"` (relative to the service configuration), or the foreground hub's `--credentials` option. Restart once to enable it. Subsequent registry changes are read on each authenticated controller request; replacement is atomic when using the CLI.

```powershell
.venv/Scripts/python.exe -m ks_light.credentials --file .hub-local/credentials.json --catalog .hub-local/lights.json --id streamdeck --revoke
```

Revocation blocks future requests; it does not cancel work already admitted. The controller token may then be deleted from its device. Forgetting a saved Android pairing removes the local copy only; revoke it here as well if access should end.

Catalogs expose only authorized lights and groups/scenes whose entire membership is authorized. Commands for an unauthorized member are rejected before queue admission. Operations and events spanning unauthorized lights are not exposed. Event cursors are global and may have gaps. Health/capabilities remain visible. A read-only token cannot submit any mutation. Operator requests retain access for recovery if the optional credential registry becomes invalid; scoped credentials fail closed until the file is fixed.

Limits: 64 credentials, 1–64 light IDs per credential, registry up to 64 KiB. Unknown light IDs, duplicate credential IDs/hashes, duplicate targets and unsupported scopes are rejected. MQTT access is configured separately at the broker and is not governed by this HTTP registry.

Software checks cover scope/target denial, filtered catalogs, operations/events, live revocation, corrupt-file behavior and secret-free CLI output. No live hub credentials were changed during implementation.
