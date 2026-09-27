# Integration specification
## Home Assistant and MQTT
Implement a hub MQTT adapter first. Publish Home Assistant discovery for verified capabilities only: light power, brightness, RGB and supported effect choices.
Provide availability through broker last-will and per-device status. Without readback use explicit optimistic semantics, not fabricated confirmed state.
Define broker topics under ks_light/{hub_id}/ with devices/{id}/set, devices/{id}/state, availability and operations/{id}.
Commands carry request_id; QoS duplication is deduplicated. Do not retain command messages. Reconnect publishes fresh discovery/state; stale retained discovery is removed on deletion.
Home Assistant units and color modes are adapted at this boundary. MQTT credentials stay on the hub.
Later native BLE integration can reuse the Python protocol library and Home Assistant Bluetooth infrastructure; it is a different ownership path, not another simultaneous writer.

## Stream Deck
TypeScript plugin; select a hub, pair, then select a light/group/scene/effect in settings.
Actions: on/off/toggle, scene activation, next favorite, brightness adjust, effect start/stop, all off.
Stream Deck+ where available: dial brightness, hue and effect speed; press changes assigned mode or toggles.
WebSocket subscriptions update key color/title, availability and pending/error indicators. Reconnect after sleep. Never label unconfirmed state as measured.
Store credentials in an appropriate protected facility; exported profiles must not include usable tokens.
Test real keys/dials if hardware is available; otherwise distinguish simulator verification from hardware acceptance. Store submission is separate from implementation.

## Windows keyboards and macro pads
A small tray companion registers user-selected global shortcuts and calls the same API. Existing CLI commands are also available to vendor launch-program macros.
Support F13-F24 or user-defined combinations where the OS/device permits; report conflicts rather than hijacking existing assignments.
Media keys are opt-in. QMK/vendor examples map keys to shortcuts; proprietary knobs may require vendor-specific support.
Credential storage belongs in the OS credential facility; not command-line arguments. Companion can control a local or paired remote hub.

## Raspberry Pi
A headless Linux service with a virtual environment, service unit, restart behavior, local configuration and documented Bluetooth permissions.
GPIO buttons use debounce, single/double/hold mappings and release handling. Rotary encoders support bounded brightness and configurable step size.
Stop active software effects on service shutdown; startup marks light state unconfirmed.
Provide a tested model/OS/adapter matrix instead of claiming every Pi image works.

## ESP32 / Arduino framework
First examples: a Wi-Fi MQTT scene button and rotary dimmer. Select a concrete board after confirming available hardware. Board pin maps and required libraries are explicit.
Button actions: toggle, scene, cycle favorites, hold-to-dim. A setup mapping associates controller inputs with hub targets.
Use distinct scoped controller credentials, reconnect with backoff, bounded offline behavior and no stale command replay. Do not embed real credentials in sketches.
A classic Arduino board without networking requires a suitable module or USB-connected host. Arduino framework support does not imply all boards have BLE/Wi-Fi.
Standalone BLE remotes and custom BLE proxy firmware are later work; avoid competing with hub-owned lights.

## References
https://www.home-assistant.io/integrations/mqtt
https://www.home-assistant.io/integrations/light.mqtt
https://developers.home-assistant.io/docs/bluetooth/
https://esphome.io/components/bluetooth_proxy/
https://docs.elgato.com/streamdeck/sdk/guides/keys/
https://docs.elgato.com/streamdeck/sdk/guides/dials/
https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-guides/bt-architecture/overview.html
https://github.com/arduino-libraries/ArduinoBLE


Current M6 implementation (2026-09-23): shared named-action CLI and Windows launchers are available; see CONTROLLER_ACTIONS.md. Native Stream Deck plugin and dial support remain planned. No global keyboard bindings installed.

Native Stream Deck key plugin is now implemented and packaged (2026-09-23); see STREAM_DECK.md. It runs named actions via the shared client and shows completion feedback. Dial support, continuous state monitoring, shared setup and hardware acceptance remain open.
