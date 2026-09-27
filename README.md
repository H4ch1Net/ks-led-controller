# KS Light

Local control for compatible KS Bluetooth lights, with an Android app and an optional hub for integrations. No cloud account is required for direct Bluetooth control.

**Current candidate: Android 1.2.1 (build 5).** The app is being distributed privately by APK sideloading while the first GitHub release is prepared. This README does not imply that a public APK is already available. **GitHub only; no Google Play release.**

[Current status](docs/v2/CURRENT_STATUS.md) · [Release plan](docs/v2/GITHUB_RELEASE_PLAN.md) · [Documentation](docs/v2/README.md) · [MIT license](LICENSE)

## The Android app

- Add multiple lights, rename them and choose a default.
- Control power, brightness and color, with per-light color balance.
- Save named color/brightness presets and organize rooms and scenes.
- Choose an animation, then its color or palette. Built-in KS03 effects run on the lamp; custom phone effects offer more choices.
- Add home-screen widgets, a Quick Settings tile and Android Device Controls.
- Choose Lime, Ocean, Violet, Rose or Amber under Settings → Appearance.
- Connect to an optional hub for shared controls and Home Assistant.

### Screenshots

These images are rendered directly from the app's Flutter screens using synthetic demo data. They show the current interface, not physical lamp state. [Capture details](docs/images/README.md).

<table>
<tr>
<td><img src="docs/images/controls.png" width="250" alt="Light controls with power, brightness and saved colors"></td>
<td><img src="docs/images/colors.png" width="250" alt="Named color presets and the color picker"></td>
<td><img src="docs/images/effects.png" width="250" alt="Effect animation and color selected separately"></td>
</tr>
<tr><td>Light controls</td><td>Saved colors</td><td>Built-in effects</td></tr>
<tr>
<td><img src="docs/images/lights.png" width="250" alt="Saved lights and add-device action"></td>
<td><img src="docs/images/scenes.png" width="250" alt="Rooms and named lighting scenes"></td>
<td><img src="docs/images/appearance.png" width="250" alt="Five appearance themes in settings"></td>
</tr>
<tr><td>Your lights</td><td>Rooms &amp; scenes</td><td>Appearance</td></tr>
</table>

## Getting started

### Android: control a light directly

Android 7.0 or later and a compatible Bluetooth light are required. A PC, Raspberry Pi or hub is **optional**.

1. Obtain the APK from a maintainer-provided private candidate, or from this repository's [GitHub Releases](https://github.com/H4ch1Net/ks-led-controller/releases) when a release is published. Avoid APK mirrors.
2. Install the APK and grant Bluetooth access when requested. Older Android versions may also require location access for scanning.
3. Choose **Add devices** / **Scan for lights**, then select your light. Use the star to make it the default.
4. Choose a color and brightness, then **Apply color**. Use **Saved colors → Save current** to name a preset. Tapping a saved color previews it; Apply sends it.
5. Open **Effects** for animation and color choices, or **Settings → Appearance** to change the app theme.

Updates must use the same signing certificate to install over an existing app. Current private builds use a development certificate. The permanent public signing identity and migration instructions must be established before the first public APK; see the [release plan](docs/v2/GITHUB_RELEASE_PLAN.md). Do not uninstall an existing setup just to bypass a signature mismatch.

### Integrations: add the hub when you need it

The hub is a small service on a Bluetooth-capable computer that owns the connection to your lights. Android, Home Assistant and external controllers send it requests. Use direct Android Bluetooth for standalone phone control; use the hub when several integrations need the same lamp. Do not run both Bluetooth owners against one light simultaneously.

| Component | What it provides | Status |
| --- | --- | --- |
| [Android](apps/android/README.md) | Direct BLE, presets, scenes, effects, widgets and themes | Private APK; user usability accepted, remaining device checks documented |
| [Hub/API](docs/v2/HUB_API.md) | Authenticated light, group and scene control | Implemented; selected real lamp paths verified |
| [Home Assistant](docs/v2/HOME_ASSISTANT.md) | MQTT discovery and controls through the hub | Implemented; selected commands physically confirmed |
| [Stream Deck](docs/v2/STREAM_DECK.md) | Keys, dials, shared setup and optional last-sent status | Plugin 0.5.0 packaged; physical installation/acceptance pending |
| [Keyboard actions](docs/v2/CONTROLLER_ACTIONS.md) | Named actions for macro keys and launchers | Implemented; assign bindings in your keyboard software |
| [Raspberry Pi GPIO](docs/v2/RASPBERRY_PI_BUTTONS.md) | Buttons, rotary controls and status LEDs | **Experimental** — host checks pass; no physical board verification |
| [ESP32](apps/esp32/README.md) | Arduino-framework buttons/rotary controls through HTTPS | **Experimental** — classic ESP32 DevKit only; no board flashed or wiring verified |

The Raspberry Pi GPIO adapter and ESP32 firmware are optional DIY controller examples. Their experimental status does not imply support for every Pi model, Arduino board, encoder or wiring arrangement.

## Compatibility and limitations

- **KS03~** is the physically exercised lamp family. Selected power, color and native breathing flows have been confirmed on one lamp; that does not certify every product sold under the same name.
- Profiles also exist for other KS prefixes, including **KS03-**, **KS04-**, **KS01-** and **KS02-**. These are inherited protocol definitions, not a hardware compatibility guarantee. See [protocol evidence](docs/v2/PROTOCOL_AND_TESTING.md).
- The tilde in `KS03~` matters: it is different from `KS03-`.
- Built-in KS03 breathing uses seven fixed firmware colors. Arbitrary-color breathing runs from the phone and may be less smooth; phone effects stop when the app leaves the foreground.
- Status generally means the last successfully sent command, not verified physical state. Commands with uncertain delivery are not automatically replayed.
- Multiple-light failure handling is implemented; physical synchronization and color matching are not guaranteed.
- iOS is deferred. There is no Google Play or Stream Deck Marketplace release in this plan.

## Python CLI and development

Python 3.10+ is required for the CLI/hub. Use a Bluetooth adapter and an OS supported by Bleak for real lights. Windows and Linux have local development evidence; other platforms and adapters need their own checks.

```sh
git clone https://github.com/H4ch1Net/ks-led-controller.git
cd ks-led-controller
python -m venv .venv
# Activate .venv using your shell, then:
python -m pip install --require-hashes -r requirements.lock
python led_control.py list --json
python led_control.py scan --json
```

For the interactive terminal menu, run `python led_menu.py`. See the [CLI guide](docs/v2/CLI_GUIDE.md), [hub service setup](docs/v2/SERVICE_DEPLOYMENT.md), [Android build instructions](apps/android/README.md), and [source packaging guide](release/README.md).

During release preparation the candidate work is on `ks-light-v2-foundation` locally. The default GitHub branch may still show the earlier CLI-only version until the source PR is merged. The [release plan](docs/v2/GITHUB_RELEASE_PLAN.md) tracks that handoff.

## Contributing and reporting problems

Include your app/plugin version, Android/OS version, lamp prefix, the steps that failed, and whether you used direct Bluetooth or the hub. Remove device addresses, tokens, Wi-Fi credentials and personal screenshots from public reports. For a new lamp, distinguish a successful protocol write from an observed physical response.

See the [current checklist](docs/v2/CURRENT_STATUS.md) before starting work. Keep physical acceptance separate from unit tests and simulator results.

Licensed under [MIT](LICENSE). This is an independent project, not an official KS, KeepSmile or Elgato product.
