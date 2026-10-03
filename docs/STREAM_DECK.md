# Stream Deck plugin

The KS Light plugin (`apps/streamdeck`, version 0.6.1) controls hub lights from an Elgato Stream Deck. It runs the repository's Python controller against a running [hub](HUB_API.md); it never opens a Bluetooth connection itself.

Requirements: Windows 10 or newer, Stream Deck 7.1 or newer, a KS Light checkout with its Python virtual environment, a running hub, and a [controller configuration](CONTROLLER_ACTIONS.md) with its token file. The plugin bundles its JavaScript dependencies and uses Stream Deck's Node 20 runtime. It is not published on the Elgato Marketplace.

## Install

1. Get `dev.kslight.controller.streamDeckPlugin` from a GitHub release, or build it (below).
2. Open the file to install it in Stream Deck.
3. Drag a KS Light action onto a key and fill in **Shared hub connection** once: Python executable, KS Light repository folder and controller configuration file (absolute paths). All keys reuse it.
4. Test against a simulation hub first. Keys show **Simulated** instead of **Sent**.

The plugin stores only paths and action settings. The token stays in the controller's token file.

## Key actions

| Action | Settings | Notes |
| --- | --- | --- |
| **Power** | Light; Toggle, On or Off | The icon highlights the hub's last-sent On. Toggle needs a known, non-restored state; after unknown state or a hub restart, use On or Off once. |
| **Set Color** | Light, color picker or hex, brightness, color response | Settings save automatically; only a physical press sends. |
| **Effect** | Light, animation (Breathing with a built-in color, Seven-color fade, RGB fade), speed, brightness | Built-in KS03~ effects; arbitrary RGB breathing is not available. |
| **Brightness** | Light, level | Applies to the last-sent color or effect and turns the light on. Rejected by the hub if nothing is known. |
| **Scene** | Hub scene | Recalls a [hub scene](HUB_LIBRARY.md). |
| **Run light action** | Named action from the controller configuration | Advanced; can target lights, groups or scenes. Optional **Show hub's last-sent state**. |

**Color response** compensates for washed-out intermediate colors before hub calibration: Balanced (gamma 2.2, default for new keys), Stronger saturation (gamma 2.5) or Raw RGB (no change, and the setting for keys created before this option existed). For example, picker `#FF7800` becomes `#FF2700` with Stronger saturation. This is adjustable perceptual compensation, not measured color matching.

## Feedback

- Pressing shows Sending, then **Sent** (hub reported success), **Simulated**, or **Failed** with the Stream Deck alert.
- Sent means the hub completed the Bluetooth write, not that the lamp state was read back.
- Repeated presses while a key is busy are ignored. Failed or uncertain commands are never retried.
- Changing settings or hiding a key discards late results from the old configuration.
- The plugin stops waiting after 125 seconds; a timeout cannot retract a command the hub already accepted.
- Configuring a key never sends a lamp command.

### Live last-sent display

Power, Color, Effect and Brightness keys show the target's last-sent power, color or effect, and brightness. On **Run light action** keys this is opt-in. Labels distinguish Sim (simulation), Saved (restored from disk) and Sent; group and scene keys show Mixed when members differ.

Visible keys that share a connection share one read-only Python reader using the hub's event long polling, refreshed at most once per second. The reader only issues GET requests and backs off on errors. Status recovery never replays a light command.

## Dials (Stream Deck+)

| Action | Use |
| --- | --- |
| **Choose light action** | List 1 to 32 action names. Turn to preview, press to run. Turning alone sends nothing. |
| **Choose brightness** | Choose a named color action (with `power: true` and `rgb`) or native-effect action. Turn in 5% steps (1 to 100%, starting at 50%), press to apply that action at the chosen level. The configuration file is not changed. |

**Choose brightness** has an optional continuous mode: turns within 200 ms are combined and only the latest level is kept while a command is in flight. After a failure it pauses until a deliberate press. The preview level is not the lamp's current brightness.

## Build

From `apps/streamdeck`:

```sh
npm ci
npm test
npm run build
npm run validate
npm run pack -- --force
```

End-to-end smoke test from the repository root (simulated Stream Deck host, real Python controller, simulated hub, no Bluetooth):

```sh
python -m apps.streamdeck.test.smoke
```

## Ownership

Keep the hub running while using the keys and do not control the same lamp from another Bluetooth client. The hub closes idle Bluetooth sessions after 30 seconds; stop using the keys before switching that lamp to phone-direct control.
