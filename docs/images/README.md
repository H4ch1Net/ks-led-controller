# Screenshots

`app-icon.svg` is the editable KS Light launcher artwork; `app-icon.png` is its README preview. Android includes matching legacy PNGs at five densities, adaptive layers for Android 8+, and a monochrome layer for Android 13+ themed icons. The lime bulb matches the default app accent on charcoal and replaces the Flutter template logo.

Captured from the actual Android Flutter widgets at 430 × 1000 logical pixels and 2× output scale (860 × 2000 PNG). These are app-rendered demonstration screenshots, not camera photos or captures from a physical Android device. No lamp/network connection was used. Names, colors, rooms and scenes are synthetic.

The screenshot harness loads Roboto and Material Icons from the pinned Flutter SDK. It replaces the test engine's unspecified Ahem font with Roboto at render time so text matches Android's default font. It does not alter app labels, colors, controls or layout code. Images are not AI-generated or retouched. System status/navigation bars are outside the captured Flutter surface.

- `lights.png`: saved device catalog.
- `controls.png`: power, brightness and saved colors.
- `colors.png`: color presets and picker, scrolled to show the controls.
- `effects.png`: native animation/color selection, rendered with a fake transport.
- `scenes.png`: synthetic room and scenes.
- `appearance.png`: Violet selected in Settings, with all five themes available.

From `apps/android`, replace the two absolute directory placeholders for your machine. Font file names are matched case-insensitively, so this works on Linux, macOS and Windows:

```sh
flutter --no-version-check test tool/capture_screenshots.dart --dart-define=KS_SCREENSHOT_FONT_DIR=/absolute/flutter/bin/cache/artifacts/material_fonts --dart-define=KS_SCREENSHOT_DIR=/absolute/ks-led-controller/docs/images
```

Review the PNGs after regenerating. Never replace them with unreviewed phone screenshots containing notifications, device addresses, hub URLs or personal names. The harness uses in-memory settings and DemoBackend; it does not read or change phone data.

## Hub dashboard

`hub-dashboard.png` (1360 x 900 viewport, 1.5x), `hub-dashboard-mobile.png` (390 x 844, 2x) and `hub-signin.png` (1280 x 800, 1.5x) are captured with Playwright and Chromium from `python -m ks_light.hub` in simulation mode, after applying the Evening scene and a Blue color to the ceiling demo light. No real lights or tokens appear.

## Brand art

`banner.png` (README header), `social-preview.png` (1280 x 640, for the GitHub social preview setting) and `streamdeck-keys.png` are rendered from the HTML sources in [`docs/art`](../art) with `node docs/art/render.mjs`. The same script renders the Stream Deck `plugin.png` and `plugin@2x.png` from `app-icon.svg`. The Stream Deck preview uses the plugin's real key images. See [DESIGN.md](../DESIGN.md) for the visual rules.
