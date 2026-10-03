# Android app

KS Light for Android controls KS Bluetooth lights directly from the phone. A hub is optional. Build and signing instructions are in [apps/android/README.md](../apps/android/README.md).

## Install

Download the APK from the project's [GitHub Releases](https://github.com/H4ch1Net/ks-led-controller/releases) and sideload it. Android 7.0 or newer is required. Distribution is GitHub only; there is no Play Store listing.

On first use the app asks for Bluetooth permissions: Nearby Devices on Android 12+, location on older versions. Permission requests happen only from the app, never from a widget or tile.

## Lights

| Task | How |
| --- | --- |
| Add lights | **Add devices** scans for about eight seconds and merges supported lights into the saved catalog. Saved lights stay listed when offline. |
| Default light | Tap the star on a saved light, or **Set as default device** on its control screen. The default opens on startup without scanning or sending a command. Tap the star again, or choose **Clear default device**, to clear it. |
| Rename | Light settings menu > **Rename**. Clear the field to restore the advertised name. Names are stored on the phone only. |
| Remove | Light settings menu > **Remove device**, then confirm. Removes the light from the catalog, the default, and any room, group or scene (empty collections are deleted). Name and calibration are kept for rediscovery. Removal does not turn the lamp off. |

The app default does not retarget existing widgets, Quick Settings, Device Controls, hub actions or Stream Deck keys. Those keep their own configured target.

## Controls

A light screen shows only the controls its profile supports: power, brightness (KS03~ only) and color.

- Color: saturation/value square, hue slider, named swatches, and hex/RGB entry under **Fine adjustments**.
- Edits are previews. Nothing is sent until **Apply**, which turns the light on and sends color and brightness.
- Power and color labels show the last command sent successfully from this app. There is no readback: changes from another controller, a power cut or the lamp's remote are not seen.
- A failed command clears the remembered state, because a partial write may have reached the lamp.

## Saved colors

**Saved colors** sits above the picker. **Save current** stores a named color plus brightness (up to 30, unique names). Tapping a swatch previews it on the current light; Apply sends it. Saving, recalling or deleting never transmits.

## Color balance

Lamp output often differs from the screen. **Color balance** in the light settings menu stores per-light red, green and blue multipliers (0 to 100%) applied to outgoing color packets. Start with white, reduce the channel that looks too strong, save, then Apply. Up to 20 named balance presets per light are supported, plus built-in starting points (Neutral, Less blue, Less red, Less green, Purple trial). Selecting a preset does not send a command.

Balance is manual compensation, not measured color calibration. Built-in lamp effects ignore it.

## Effects, rooms and shortcuts

- [Effects](EFFECTS.md): built-in lamp animations and phone-driven custom effects.
- [Rooms, groups and scenes](ROOMS_AND_SCENES.md): multi-light control, scene snapshots, backup and import.
- [Widgets, Quick Settings and Device Controls](ANDROID_SHORTCUTS.md).

## Hub mode

The **Hub** tab controls lights owned by a [KS Light hub](HUB_API.md) instead of using phone Bluetooth. The phone makes no BLE calls in this mode.

1. Enter the hub address and a token. Plain HTTP is accepted only for `127.0.0.1`/`localhost` (USB development). Any other address must be HTTPS with a certificate the phone trusts and a matching hostname. Redirects are refused.
2. **Connect**. Optionally **Remember this hub**: the address and token are stored in a file encrypted with an Android Keystore key, in the app's no-backup directory. **Load saved hub** fills the form but still requires Connect. **Forget saved hub** deletes the local copy only; revoke the token on the hub as well.
3. Select a light: On/Off, color, brightness and Purple breathing. Groups offer All on/All off and shared color, brightness or Purple breathing; scenes offer Apply. Controls appear only when every member supports them.

Each submission is sent once with a unique idempotency key, then polled until complete. Group and scene results list every member. A lost response is reported as uncertain and is never resent; check the hub before trying again. Labels show the hub's last-sent state, not readback. **Refresh** reloads the catalog; there is no background polling.

With an operator token and a hub configured with files, **Edit hub color balance** and **Edit rooms & scenes** edit hub calibration and the hub library. Both use drafts with explicit Save and version checks against concurrent edits. Editing sends no lamp commands.

For USB development against a hub on a PC:

```sh
adb -s PHONE_SERIAL reverse tcp:8765 tcp:8765
```

Then connect to `http://127.0.0.1:8765`. Remove the forwarding afterwards with `adb reverse --remove tcp:8765`.

Phone-side names, calibration, saved colors and rooms/scenes are separate from the hub and are not synchronized.

## Settings

- **Demo mode**: a virtual light set with no Bluetooth. Demo and real catalogs are stored separately.
- **Appearance**: Lime, Ocean, Violet, Rose and Amber themes. Themes never change lamp colors.
- **Connection help**: Bluetooth state, permissions, current Bluetooth owner inside the app, and saved light and widget counts, with recovery steps. **Copy diagnostics** includes only allowlisted diagnostics, no addresses, names, network details or credentials.

## Limits

- One BLE owner per lamp. Do not control the same lamp from the app, a hub, Home Assistant's original integration and the vendor app at the same time.
- No state readback; all status is last sent.
- Commands that fail or time out are never replayed automatically.
- Corrupt stored settings are reported and protected from being overwritten.
