# Android visual design - 1.2.1

## Direction
Controls first, setup second. Deep charcoal surfaces, soft lime accents, generous spacing, rounded panels and consistent typography. Color itself is the focus; decoration never implies a live lamp reading.

## Navigation and hierarchy
- Lights: saved device cards, visible default star, one Add action. Selecting a light opens power, brightness and color. Apply stays available above navigation.
- Scenes: rooms and scenes with compact cards, color swatches and one primary action. Editing/deletion live in overflow menus; backups stay in the toolbar.
- Hub: concise connection form and capability-aware controls using the same styling.
- Light settings: rename, calibration, default, shortcuts and removal in one menu. App settings hold demo mode and connection diagnostics.
- Effects: selectable visual cards, speed/brightness and clear Apply/Off actions. Native effects keep their on-release behavior; phone effects keep their foreground lifecycle behavior.

## Saved colors, effects and appearance
- Saved colors sits above the color picker with a visible Save current action. Name a color plus brightness, then tap its swatch to preview it on any light; Apply sends it. Saving, recalling or deleting a preset never transmits. Names must be unique; up to 30 colors are stored on this phone, independently of calibration presets.
- Built-in effects use Animation (Breathing / Color fade), followed by Color or Palette. The verified KS03 firmware supports seven fixed breathing colors and two fade palettes, not arbitrary RGB effect colors. Existing effect presets and command IDs remain compatible.
- Custom effects from phone provides an arbitrary color picker and saved colors for breathing. It retains foreground-only operation and may fade less smoothly than built-in effects. Built-in effects remain the smooth default.
- Settings > Appearance provides Lime, Ocean, Violet, Rose and Amber. Accent, selection, surfaces and navigation update together, without changing lamp colors. Choices persist independently of lamp settings; unreadable preferences are protected from overwrite.

## Copy and accessibility
Remove prototype notices, repeated instructions, device addresses and implementation details from everyday controls. Keep actionable errors, delivery uncertainty, demo mode and destructive-action consequences. Exact hex/RGB live under Fine adjustments; calibration remains per-light. Swatches retain named semantics/tooltips and 48 px targets. Compact screens scroll and the primary Apply button stays reachable. Large text must remain usable.

## Acceptance
Preserve saved data, packet generation, calibration, no-write previews, failure feedback, effect stop/cleanup and import review. Validate affected UI flows and inspect the actual phone. Do not infer physical lamp acceptance from UI or transport success.

## Distribution
GitHub-only APK distribution. No Google Play enrollment, listing or AAB work. The current device-compatible candidate uses the existing development certificate; public release signing remains a separate decision. No upload/publication is performed as part of the visual redesign.
