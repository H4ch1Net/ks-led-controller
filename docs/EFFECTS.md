# Android effects

The app offers two kinds of effects: built-in effects that the lamp firmware runs itself, and custom effects that the phone streams frame by frame.

## Built-in (on-light) effects, KS03~ only

Opening **Effects** on a KS03~ light shows the built-in effects first. Choose an animation (Breathing or Color fade), then a color or palette:

| ID | Effect |
| --- | --- |
| 0x82 (130) | Seven-color fade |
| 0x83 (131) | RGB fade |
| 0x84 to 0x8A (132 to 138) | Red, Green, Blue, Yellow, Cyan, Purple, White breathing |

Speed and brightness are 0 to 100 and 1 to 100. **Apply effect** sends power-on plus one effect command. The lamp then animates on its own and keeps running after the app closes or disconnects. **Turn off** sends Off; applying a static color replaces the effect.

- The firmware supports only these fixed colors and palettes. Arbitrary RGB breathing is not a built-in capability.
- Color balance does not apply to built-in effects.
- After the first Apply on a screen visit, slider changes send one update on release. No frames are streamed.
- Each light remembers its last applied effect, speed and brightness, plus up to 20 named effect presets. Reopening restores the choices without sending anything.
- Backgrounding the app closes the BLE session once any active write finishes; the lamp keeps animating.
- **Advanced > Read light state** sends the state query found in the vendor app. Tested firmware does not return a usable state, so the app reports readback as unavailable. Normal controls do not depend on it.

## Custom effects from phone

**Custom effects from phone** (or **Effects** on a room or group) runs software effects on any RGB-capable light. Every member must support RGB.

| Effect | Behavior |
| --- | --- |
| Breathing | Brightness envelope on one chosen color. Any color can be used. |
| Candle | Warm amber flicker. |
| Sunset | One pass from warm gold to dim red, then holds the final red. |
| Rainbow | Continuous hue cycle. |
| Color drift | Interpolates through a palette. |
| Palette wave | Palette progression offset by each member's position in the room. |

Palettes: Aurora, Warm, Ocean, Pink & violet. Cycle length is 10 to 120 seconds, intensity 5 to 100%. Per-light color balance is applied to every frame. On KS03~, breathing keeps the RGB ratio fixed and varies the separate brightness channel.

### Timing and limits

- Foreground only. Leaving the app stops new frames; returning does not restart the effect, and an app restart never resumes one.
- One write in flight, no frame queue. Frames target 150 ms (about 6.7 Hz); slow writes lower the rate. Missed frames are skipped, not replayed.
- For 1 to 4 targets the app holds one connection per light for the run. Larger groups use sequential short connections and update more slowly.
- Group members are updated in sequence, not synchronized.
- An offline member is dropped for the rest of the run; the others continue. If all fail, the run ends.
- Phone effects may look less smooth than built-in effects. Prefer built-in effects where they fit.

### Stop and restore

**Stop** lets the active write finish, then stops. With **Restore on stop** enabled, each light returns to its state captured at start, but only when that state is known (last sent Off, or last sent On with a remembered color). Unknown states are skipped rather than guessed. Stopping by backgrounding never sends a restore; the last frame stays on the lamp.
