# Protocol and testing

## Profiles

Light profiles live in `ks_light/profiles.json` and are shared with the Android app (`protocol/` holds language-neutral fixtures). A profile maps a Bluetooth name prefix to a GATT service, a write characteristic (16-bit short UUIDs in the `0000xxxx-0000-1000-8000-00805f9b34fb` template) and a color packet format.

| Prefix | Service | Write | Color format |
| --- | --- | --- | --- |
| KS03~ | AFD0 | AFD1 | extended RGB with brightness, native effects |
| KS03-, KS04- | FFF0 | FFF3 | standard RGB |
| KS01-, KS02- | AE00 | AE01 | standard RGB |
| KS05- | AE00 | AE02 | power only |
| KS04~, KS07- to KS13- | AE00 | AE10 | power only |
| KS15~ | AFD0 | AFD3 | power only |

All mappings were inherited from the original project, which derived them from the vendor app. Only KS03~ has been exercised on hardware (see [HARDWARE_TESTING.md](HARDWARE_TESTING.md)). The power-only entries are candidates; do not add RGB support for them without evidence.

## Packets

| Command | Bytes (hex) | Notes |
| --- | --- | --- |
| Power on | `5B F0 01 B5` | Used for all profiles; universality unverified |
| Power off | `5B 0F 01 B5` | |
| Standard RGB | `7E 07 05 03 RR GG BB 00 EF` | No independent brightness |
| Extended RGB | `5A 00 01 RR GG BB 00 LL 00 A5` | `LL` brightness |
| Extended white | `5A 00 02 00 00 00 00 LL 00 A5` | Encoder exists; no UI uses it |
| Native effect | `5C 00 EE SS LL 00 C5` | `EE` effect 0x82 to 0x8A, `SS` speed 0 to 100, `LL` brightness 1 to 100 |
| State query | `5F 01 00 F5` | Found in the vendor app; see readback below |

Brightness: the vendor app's brightness slider ranges 0 to 100. The hub and Android send KS03~ brightness as a percent (0 to 100). The legacy CLI passes a raw byte (0 to 255).

Native effect IDs: 0x82 Seven-color fade, 0x83 RGB fade, 0x84 to 0x8A Red, Green, Blue, Yellow, Cyan, Purple and White breathing. Jump and strobe modes from the vendor app are not exposed. Native effects keep running after the controller disconnects.

Writes go only to the configured characteristic, using a write mode it advertises. There is no probing of other characteristics. The hub and Android space consecutive packets by 100 ms; the CLI transport uses longer delays and connects for each command.

### Readback

KS03~ exposes AFD2 (notify) and AFD3 (read). On the tested firmware the state query produced no recognized state notification, and AFD3 returned an identification string. Readback is therefore treated as unavailable: every client reports last-sent state, never device state. Android's **Read light state** reports this explicitly.

## Evidence policy

Evidence levels: unknown, inherited implementation, observed in the vendor APK, tested on hardware. Track evidence per capability and device variant.

- A command seen in the vendor app is not hardware-tested.
- Do not guess effect, timer or segment IDs from neighboring values.
- Keep APKs and decompiled material out of the repository; document only the interoperability facts needed for an independent implementation.
- Normal controls never send firmware updates or arbitrary raw packets.

## Automated tests

| Area | Command (from repository root unless noted) |
| --- | --- |
| Python (CLI, protocol, transport, queue, hub, MQTT, service, credentials, GPIO, ESP32 contract, packaging) | `python -m unittest discover -s tests -v` |
| Simulator demo | `python -m ks_light.simulator` |
| Android | `flutter --no-version-check test --no-pub` in `apps/android` |
| Android to hub contract | `python -m apps.android.tool.smoke_hub --dart PATH_TO_DART` |
| Android native shortcuts | `./gradlew :app:testDebugUnitTest` in `apps/android/android` |
| Stream Deck | `npm test` in `apps/streamdeck`; `python -m apps.streamdeck.test.smoke` |
| ESP32 host logic | see [apps/esp32/README.md](../apps/esp32/README.md#host-tests) |

`protocol/golden_packets.json` holds packet fixtures that both the Python and Dart encoders must reproduce, including boundary values. Mock transports and the simulator verify logic only; they say nothing about BLE compatibility, timing or color output.

`python -m ks_light.simulator` never loads a Bluetooth client. It submits 101 rapid slider values to one virtual light, one command to a second light, and one to an offline light, and should report 100 superseded, two succeeded and one failed, with at most two concurrent sends.
