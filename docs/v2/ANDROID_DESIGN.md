# Android visual redesign - 1.2.0

## Direction
Controls first, setup second. Deep charcoal surfaces, soft lime accents, generous spacing, rounded panels and consistent typography. Color itself is the focus; decoration never implies a live lamp reading.

## Navigation and hierarchy
- Lights: saved device cards, visible default star, one Add action. Selecting a light opens power, brightness and color. Apply stays available above navigation.
- Scenes: rooms and scenes with compact cards, color swatches and one primary action. Editing/deletion live in overflow menus; backups stay in the toolbar.
- Hub: concise connection form and capability-aware controls using the same styling.
- Light settings: rename, calibration, default, shortcuts and removal in one menu. App settings hold demo mode and connection diagnostics.
- Effects: selectable visual cards, speed/brightness and clear Apply/Off actions. Native effects keep their on-release behavior; phone effects keep their foreground lifecycle behavior.

## Copy and accessibility
Remove prototype notices, repeated instructions, device addresses and implementation details from everyday controls. Keep actionable errors, delivery uncertainty, demo mode and destructive-action consequences. Exact hex/RGB live under Fine adjustments; calibration remains per-light. Swatches retain named semantics/tooltips and 48 px targets. Compact screens scroll and the primary Apply button stays reachable. Large text must remain usable.

## Acceptance
Preserve saved data, packet generation, calibration, no-write previews, failure feedback, effect stop/cleanup and import review. Validate affected UI flows and inspect the actual phone. Do not infer physical lamp acceptance from UI or transport success.

## Distribution
GitHub-only APK distribution. No Google Play enrollment, listing or AAB work. The current device-compatible candidate uses the existing development certificate; public release signing remains a separate decision. No upload/publication is performed as part of the visual redesign.
