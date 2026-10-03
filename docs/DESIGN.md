# Design system

KS Light has one visual language across the Android app, the hub dashboard, the Stream Deck plugin and the repository art.

## Direction: lamp-lit instrument

The product controls physical lamps and is careful about what it knows. The interface borrows from functional hardware design (Braun under Dieter Rams, studio equipment): a neutral body, printed labels, few controls, and color used only where it carries meaning.

- **The only saturated color is light.** Lamp colors appear on lenses, light pools, swatches and scene strips. The rest of the interface stays graphite.
- **One signal accent.** Lime (or the chosen accent) marks the active power state, primary actions, focus and healthy indicators, like the single colored switch on a Braun panel.
- **Honest state.** Status is the last command sent. Indicators use LEDs and plain words, not decorative motion.
- **Hardware texture, not effects.** A faint perforated dot grid, hairline borders and a 1 px top highlight replace glass, blur and heavy shadows.

## Tokens

| Token | Value | Use |
| --- | --- | --- |
| `ink` | `#111514` | Page background, Stream Deck keys |
| `panel` | `#191e1c` | Cards and panels |
| `raised` | `#202624` | Buttons, selected rocker side |
| `well` | `#0d1110` | Inputs, recessed tracks, list rows |
| `line` / `line-strong` | white at 7% / 13% | Hairline borders |
| `text` / `muted` / `faint` | `#ecf0ec` / `#95a09b` / `#808b86` | Text hierarchy |
| `accent` | `#d4efa3` (Lime) | Signal color; Ocean `#8cd5ff`, Violet `#d0b4ff`, Rose `#ffb4cc`, Amber `#ffd08a` |
| `warn` / `danger` | `#f3c871` / `#ff8f80` | Simulation notice, failures |

Spacing follows a 4 px grid (4, 8, 12, 16, 20, 24, 32). Radii: 20 px panels, 12 px controls, pills for chips and indicators, circles for lenses.

## Type

- System sans (Inter when installed) for UI text. Headings are semibold with slight negative tracking.
- **Printed labels**: 10.5 to 11 px, uppercase, 0.09 em tracking, semibold, muted. Used for section and control labels.
- Monospace with tabular figures for values: hex colors, percentages, profile prefixes, times.

## Components

| Component | Rule |
| --- | --- |
| Lens | A lamp diffuser seen head-on. Dark glass when off; the last-sent color with a soft halo when on. Breathing effects pulse at a rate derived from the effect speed; fade effects cycle hue. |
| Light pool | A soft wash of the lamp color in the card corner, scaled by brightness. Only when lit. |
| Rocker | Two-position On/Off. On uses the accent; Off uses the raised tone. |
| Fader | 4 px track with printed 10% ticks, accent fill and a light hardware cap. |
| Indicator | 7 px LED plus a printed label: accent (ok), amber (simulation), red (fault), blinking (sending). |
| Scene tile | A strip of the scene's colors (hatched for off, spectrum for fade effects) above the name. |

## Icons and illustration

Icons sit on a 24 px grid with a 1.75 stroke, round caps and joins, and no fills. The same geometry drives the dashboard sprite (`ks_light/web/index.html`), the Stream Deck key images (scaled 3x on a 144 px key) and the white Stream Deck action-list icons. The articulated desk lamp line drawing is used for sign-in and empty states.

## Motion

Controls respond in 120 ms with an ease-out curve. Light changes fade over 450 ms, like a lamp. Toasts rise 8 px. Effects animate only to mirror what the lamp is doing. `prefers-reduced-motion` stops all animation.

## Accessibility

Text meets WCAG AA contrast on its surface. Focus is a 2 px accent outline. Color is never the only signal: power states have labels, swatches have names, activity LEDs have text and status labels. Controls are at least 32 px tall and lens colors are mirrored by hex text.

## Art sources

`docs/art/` holds the HTML sources for the README banner, social preview, Stream Deck key preview and plugin icons. Render them with `node docs/art/render.mjs` (needs Playwright with Chromium).
