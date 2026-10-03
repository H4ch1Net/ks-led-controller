# KS Light documentation

## Users

| Guide | Contents |
| --- | --- |
| [Android app](ANDROID.md) | Install, lights, colors, calibration, hub mode, settings |
| [Effects](EFFECTS.md) | Built-in lamp effects and phone-driven effects |
| [Rooms, groups and scenes](ROOMS_AND_SCENES.md) | Multi-light control on the phone, backup and import |
| [Widgets and shortcuts](ANDROID_SHORTCUTS.md) | Home-screen widgets, Quick Settings tile, Device Controls |
| [Direct CLI](CLI_GUIDE.md) | `led_control.py` and `led_menu.py` |

## Integrations

| Guide | Contents |
| --- | --- |
| [Hub API](HUB_API.md) | Running the hub, authentication, scoped credentials, endpoints, calibration |
| [Hub groups and scenes](HUB_LIBRARY.md) | Library file, group and scene operations, editing |
| [Hub as a service](SERVICE_DEPLOYMENT.md) | Configuration file, Windows task, systemd, HTTPS, persistence |
| [Home Assistant and MQTT](HOME_ASSISTANT.md) | MQTT bridge, discovery, topics, commands |
| [Stream Deck](STREAM_DECK.md) | Plugin actions, dials, build |
| [Named controller actions](CONTROLLER_ACTIONS.md) | Action CLI, keyboard and macro launchers |

## DIY hardware (experimental)

| Guide | Contents |
| --- | --- |
| [Raspberry Pi GPIO](RASPBERRY_PI_BUTTONS.md) | Buttons, rotary encoders, status LEDs |
| [ESP32 controller](../apps/esp32/README.md) | Firmware, wiring, USB setup |
| [Hardware coverage and testing](HARDWARE_TESTING.md) | What has been tested on real hardware, test checklist |

## Developers

| Guide | Contents |
| --- | --- |
| [Architecture](ARCHITECTURE.md) | Components, principles, command queue, state |
| [Protocol and testing](PROTOCOL_AND_TESTING.md) | Profiles, packets, evidence policy, automated tests |
| [Development](DEVELOPMENT.md) | Environment, dependency locks, CI |
| [Android build and signing](../apps/android/README.md) | Toolchain, tests, release builds |
| [Release checklist](RELEASE_CHECKLIST.md) | Release steps and dependency verification |
| [Source packaging](../release/README.md) | Reproducible source archive |
| [Screenshots](images/README.md) | How the documentation images are generated |

## Safety notes

- One Bluetooth owner per lamp: the phone, one hub, or another integration, never several at once.
- No readback: every status is the last command sent, not the lamp's actual state.
- No automatic replay: failed or uncertain commands are reported, never resent.
- Raspberry Pi and ESP32 controllers are experimental and untested on real boards.
