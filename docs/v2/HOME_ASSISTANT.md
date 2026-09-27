# Home Assistant / MQTT bridge

## Implemented
The Python hub optionally connects to an MQTT 5 broker and discovers KS03~ lights using Home Assistant's JSON light schema. HTTP and MQTT share one bounded queue per light. Supported controls are On/Off, RGB, brightness (0..100), and the physically verified Purple breathing effect. Other light profiles are intentionally not discovered yet.

The bridge publishes last successfully sent state, not physical readback. Discovery enables optimistic control; attributes explicitly report `state_source: last_sent` and `confirmation: simulated` or `unconfirmed`. Availability means the hub's broker connection is online, not that each lamp is reachable. A failed BLE delivery invalidates remembered state. Restart starts with unknown state. Phone-side calibration is not imported.

## Setup
Install `requirements.lock` with `pip install --require-hashes -r requirements.lock` in the hub virtual environment. Use an MQTT 5 broker already configured in Home Assistant's MQTT integration. Keep one hub ID and one manifest path per installation; simultaneous processes must use distinct IDs.

Set `KS_LIGHT_TOKEN` as described in HUB_API.md. If your broker requires authentication, set `KS_MQTT_USERNAME` and `KS_MQTT_PASSWORD` locally in the process environment. Do not put secrets in the repo or command arguments.

Start with the simulator:

```powershell
python -m ks_light.hub --mqtt-host YOUR_BROKER --mqtt-id ks-light-test
```

The discovered light name includes `(Simulation)`. The HTTP listener stays on loopback; MQTT connects outbound, so this does not require exposing the HTTP server to the LAN.

For physical lights, configure the catalog from `examples/hub-lights.example.json`, stop direct Android control, and start:

```powershell
python -m ks_light.hub --ble --config lights.json --mqtt-host YOUR_BROKER --mqtt-id ks-light
```

Optional flags: `--mqtt-port`, `--mqtt-tls`, `--mqtt-ca-file`, `--mqtt-manifest`. TLS validates the broker certificate; the default port stays 1883 unless specified. Windows CLI selects the event loop required by aiomqtt.

Broker credentials and topic permissions authorize MQTT actions; the HTTP bearer token does not protect MQTT. Give controllers publish access only to their command topics and give the bridge discovery/state publication and command subscription access. Use broker authentication/TLS according to your network setup.

## Topics and controller commands
For hub ID `ks-light` and catalog light ID `desk`:

| Topic | Behavior |
| --- | --- |
| `ks_light/ks-light/devices/desk/set` | Non-retained JSON commands, subscription QoS 0 |
| `ks_light/ks-light/devices/desk/result` | Non-retained acceptance/rejection result |
| `ks_light/ks-light/devices/desk/state` | Retained last-sent state |
| `ks_light/ks-light/devices/desk/attributes` | Retained state-source attributes |
| `ks_light/ks-light/operations/OPERATION_ID` | Non-retained operation status updates |
| `ks_light/ks-light/availability` | Retained online/offline, including last will |

Examples:

```json
{"state":"ON","color":{"r":239,"g":66,"b":255},"brightness":35,"request_id":"button-42"}
{"effect":"Purple breathing","speed":35,"brightness":50}
{"state":"OFF"}
```

Send examples individually, not as one document. A color or brightness action means turn on. Brightness-only commands preserve the last successfully sent static color or native effect and its speed. The hub resolves that partial update when it reaches the front of the light queue. Unknown state is rejected. Native brightness must be 1..100; use Off to stop the output. Effect speed defaults to 35 and brightness to 50. Nonzero transitions, unknown effects, invalid values, and combined Off/settings commands are rejected.

`request_id` is optional (1..96 letters, digits, underscore, dot, colon, hyphen). Retries with identical bodies reuse the same operation within the hub's ten-minute in-memory retention window; changed commands with the same ID are rejected. Home Assistant does not provide these IDs. QoS 0 avoids MQTT redelivery but does not guarantee delivery. Rejected results have an error code; accepted results have an operation ID. Broker reconnects do not retry physical writes.

## Reconnect and discovery lifecycle
The bridge retries broker connections with a bounded delay and republishes discovery on reconnect and Home Assistant's `homeassistant/status` online message. MQTT 5 subscription options skip preexisting retained commands and preserve the live retain flag so new retained commands are rejected too. Never retain controller command messages.

The `.ks_light_mqtt_HUBID.json` manifest records discovery owned by that hub. Removed catalog entries have their retained discovery/state/attributes cleared at the next announcement. Preserve the manifest and stable hub ID to allow cleanup. Invalid manifests fail initial setup or cause logged retries if changed while running. To retire the whole hub, remove its discovery entries explicitly; stopping marks lights offline. Neither discovery refresh nor process startup sends light commands.

## Validation and remaining acceptance
- 77 Python tests pass, including 12 MQTT tests for validation, state, native packet encoding, retry IDs, retained rejection, lifecycle cleanup, manifest ownership, birth refresh and failed delivery.
- Live test against the user's Home Assistant host MQTT 5 broker passed retained-command rejection, unknown-color brightness rejection, simulated native command completion, last-sent publication and graceful offline shutdown. Temporary discovery and retained test records were removed afterward.
- Dependency consistency check passes. No Android changes in this slice.
- Home Assistant UI acceptance passed on Home Assistant host: the discovered simulator exposed On/Off, RGB favorites, brightness and Purple breathing. UI On, native-effect selection, color preset and Off were exercised; broker state confirmed native effect and RGB delivery. The test server was stopped afterward, so the retained simulator entity is offline until restarted. A subsequent physical test through Home Assistant host MQTT and the PC BLE adapter completed Purple breathing (speed 35, brightness 50) successfully on the KS03 lamp. This confirms transport delivery; user visual confirmation is still pending. Multi-light hardware acceptance remains open.

Implementation references: [Home Assistant MQTT JSON lights](https://www.home-assistant.io/integrations/light.mqtt/), [MQTT discovery and birth messages](https://www.home-assistant.io/integrations/mqtt/), [aiomqtt](https://pypi.org/project/aiomqtt/).


## Physical test and controller ownership (2026-09-22)
The original KS Smart LED Controller integration in Home Assistant host was temporarily disabled and the Android app stopped to keep a single BLE writer. The new hub accepted an MQTT effect command, delivered its power/native packets to the test KS03 lamp, and reported `succeeded`, `confirmation: unconfirmed`. The temporary hub then disconnected and stopped. The original integration was re-enabled, Android reopened, and temporary hardware-test discovery removed. Native animation can continue after the hub disconnects.

For persistent use, choose one BLE owner: the existing HA custom integration, Android direct mode, or the new Python hub. Android hub mode and automatic ownership handoff are still planned. Do not leave two controllers issuing writes to the same lamp. The test did not change the existing HA entity's identity, room or automations.

The native-brightness follow-up is covered by simulated packet/state/retry tests; changing native brightness over physical BLE through this hub has not yet been separately accepted. The Android APK is unchanged.


## Follow-up after no visible change (2026-09-22)
The user saw no change during the first MQTT native-effect test, so its transport-success result is not physical acceptance. With competing controllers paused again, the hub sent Off, waited five seconds, then sent static red at 40%. The user confirmed the lamp was steady red. This physically verifies the hub's static-color path; it does not establish why the earlier effect was not seen.

During the follow-up, Home Assistant host MQTT connection/CONNACK attempts timed out twice, before test command publication. TCP port 1883 remained reachable while one port 8123 probe timed out. No broker restart or security/configuration change was attempted. A direct hub BLE Purple breathing command was then delivered to separate lamp behavior from broker availability; the user confirmed it changed from steady red to smoothly breathing purple.

The original HA integration was re-enabled and Android reopened after observation. MQTT subsequently reconnected and temporary hardware-test discovery was removed. The earlier no-change report remains unexplained; direct hub BLE color and native effects now have user-confirmed physical acceptance, while a repeat end-to-end MQTT visual test remains open.


## End-to-end physical acceptance and diagnostics (2026-09-22)
A new test waited until the MQTT bridge was online, then published a non-retained steady-green command at 40% through Home Assistant host. The hub queued and completed real BLE delivery, and the user confirmed the lamp was steady green. This closes end-to-end physical MQTT color acceptance. Earlier direct BLE Purple breathing is also user-confirmed. It does not prove readback, all native modes, multi-light behavior, or unattended reliability.

The original HA integration was re-enabled, Android reopened and temporary hardware discovery removed. The hub now exposes MQTT lifecycle and sanitized failures in authenticated HTTP health; configured MQTT outages mark it degraded. Reconnect backoff survives short-lived connections. Validation: 80 tests passed in the full suite, then 15 MQTT tests passed including the added short-lived-connection regression (81 total test cases). Android unchanged. Persistent service packaging and Android hub mode remain next.
