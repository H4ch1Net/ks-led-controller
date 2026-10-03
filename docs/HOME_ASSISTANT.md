# Home Assistant and MQTT

The hub includes an optional MQTT 5 bridge. It publishes Home Assistant discovery for KS03~ lights using the [MQTT JSON light schema](https://www.home-assistant.io/integrations/light.mqtt/). HTTP and MQTT commands share the same per-light queues, so Home Assistant does not compete with other controllers for Bluetooth.

Only KS03~ lights are discovered. Each gets On/Off, RGB, brightness (0 to 100) and the nine built-in effects (Seven-color fade, RGB fade, and Red, Green, Blue, Yellow, Cyan, Purple and White breathing).

## Setup

Requirements: the hub installed from `requirements.lock`, and an MQTT 5 broker already used by Home Assistant's MQTT integration.

Foreground hub, simulation first:

```sh
export KS_LIGHT_TOKEN=...                  # required with --ble; see HUB_API.md
export KS_MQTT_USERNAME=...                # only if the broker needs authentication
export KS_MQTT_PASSWORD=...
python -m ks_light.hub --mqtt-host BROKER --mqtt-id ks-light-test
```

Simulated lights appear in Home Assistant with `(Simulation)` in their names. Only KS03~ demo lights are discovered. For real lights:

```sh
python -m ks_light.hub --ble --config lights.json --mqtt-host BROKER --mqtt-id ks-light
```

| Option | Default | Meaning |
| --- | --- | --- |
| `--mqtt-host` | none | Broker hostname; enables the bridge |
| `--mqtt-port` | 1883 | Set explicitly for TLS |
| `--mqtt-id` | `local` | Hub ID used in topics and discovery IDs |
| `--mqtt-tls` | off | TLS with certificate validation |
| `--mqtt-ca-file` | system CAs | Private CA (requires `--mqtt-tls`) |
| `--mqtt-manifest` | `.ks_light_mqtt_<id>.json` | Discovery ownership manifest |

For a service, use the `mqtt` block in the [service configuration](SERVICE_DEPLOYMENT.md#mqtt); the password is read from a file there.

Keep one stable hub ID and manifest per installation. Two hub processes must use different IDs. The HTTP API stays on loopback; MQTT connects outbound.

Before switching real lamps to the hub, stop any other Bluetooth controller of those lamps (the Android app, the vendor app, other Home Assistant integrations).

## Security

The HTTP bearer token does not protect MQTT; broker credentials and topic ACLs do. Give the bridge publish access to discovery, state, attributes, result, operation and availability topics and subscribe access to its `set` topics and `homeassistant/status`. Give other controllers publish access only to the `set` topics they need. Use broker authentication and TLS appropriate to your network.

## Topics

For hub ID `ks-light` and light `desk`:

| Topic | Retained | Content |
| --- | --- | --- |
| `homeassistant/light/kslight_ks-light_desk/config` | yes | Discovery |
| `ks_light/ks-light/devices/desk/set` | must not be | JSON commands (subscribed at QoS 0) |
| `ks_light/ks-light/devices/desk/result` | no | Accepted (with operation ID) or rejected (with error code) |
| `ks_light/ks-light/devices/desk/state` | yes | Last-sent state |
| `ks_light/ks-light/devices/desk/attributes` | yes | `state_source: last_sent`, `confirmation`, hub instance |
| `ks_light/ks-light/operations/<id>` | no | Operation status updates |
| `ks_light/ks-light/availability` | yes | `online`/`offline`, with last will |

## Commands

Publish each as a separate message:

```json
{"state": "ON", "color": {"r": 239, "g": 66, "b": 255}, "brightness": 35, "request_id": "button-42"}
{"effect": "Purple breathing", "speed": 35, "brightness": 50}
{"state": "OFF"}
```

- A color or brightness command means turn on.
- Brightness alone reuses the last-sent color, or the running effect and its speed. It is rejected when nothing is remembered.
- Effects: speed defaults to 35 and brightness to 50; effect brightness must be 1 to 100. Effects cannot be combined with a color.
- Off cannot carry other settings. Nonzero `transition`, unknown fields and invalid values are rejected.
- Retained commands are rejected, including ones already on the broker when the bridge subscribes. Never publish commands with the retain flag.
- `request_id` (optional, 1 to 96 letters, digits, `_ . : -`) works like an HTTP idempotency key: the same ID and body within ten minutes returns the original operation. Home Assistant itself does not send request IDs.

QoS 0 avoids broker redelivery but does not guarantee delivery. Broker reconnects never retry physical writes.

## State semantics

Home Assistant entities are optimistic. Published state is the last command the hub sent successfully, not readback. Availability means the bridge is connected to the broker, not that each lamp is reachable. A failed Bluetooth write clears the light's state. After a restart state is unknown, unless the service has `persist_state` enabled.

## Discovery lifecycle

- Discovery and state are republished on every broker connection and when Home Assistant publishes `online` on `homeassistant/status`.
- The manifest records which discovery entries this hub owns. Lights removed from the catalog have their retained discovery, state and attributes cleared at the next announcement. Keep the manifest and hub ID stable so this works.
- Stopping the hub marks lights offline. It does not remove them; delete their discovery entries to retire a hub.
- Neither discovery nor startup sends light commands.

Broker connections retry with a delay growing from 2 to 60 seconds; a connection lasting at least 30 seconds resets it. Bridge state is visible in the hub's `/health` endpoint.
