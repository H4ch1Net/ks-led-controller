# Deferred acceptance checklist
Updated 2026-09-27. All features below are implemented. Use the private 1.2.1/build 5 APK and Stream Deck 0.6.1 package; rebuilding is unnecessary unless source changes. The optimized APK upgrade, saved light/default retention, startup and redesigned screens were checked on the phone; desktop UI remains deferred while the PC is in use.

## Android - one combined session
- [x] User accepted 1.2.1 usability, including saved colors, effect selection and appearance.
- [x] Upgrade without uninstalling, optimized-build startup and saved light/default retention; visually inspect the redesigned screens.
- [ ] Complete calibration/presets, rooms/scenes and optional hub pairing retention checks and permission prompts.
- [ ] Add/rescan/deduplicate devices; change/clear default, restart and remove a referenced light. Confirm group/widget membership cleanup without affecting other lights.
- [ ] Color/brightness/native effects: explicit preview/apply, calibration once, cancel without writes, reconnect and Bluetooth-off feedback. Avoid running Android direct BLE and hub BLE ownership on the same lamp.
- [ ] Library editing: narrow-screen/keyboard layout, detached color previews, cancel/save, per-light values, backup/document-provider/clipboard import, oversized input rejection and replacement-device matching. Cancel must preserve original data.
- [ ] Hub: saved pairing across restart/lock, group color/brightness/native effects, scene recall, per-member results, calibration presets/import and definition editing. Start with simulator configuration; separate physical lamp acceptance.
- [ ] Widgets: independent power/favorite/scene snapshots; pin/configure/resize; current calibration; Scene/All off; reconfigure/delete/remove a member while work is pending; service interruption and partial/offline members. Scene widgets support 1..8 KS03 lights and sequential delivery.
- [ ] Quick Settings/Device Controls: highlighted On and inactive Off, matching last-sent status after app restart, unknown/error/offline behavior and service cleanup.
- [ ] Connection help: status accuracy, refresh and copied diagnostics excluding identifiers/credentials.

## Multiple lights and services
- [ ] Two or more real lights: group partial failures, cancellation, supported model differences, per-light color and effect behavior. One physical KS03 was available previously; simulator results cannot establish synchronization/color accuracy.
- [ ] Persistent Windows/Linux/Pi hub startup/restart/shutdown and trusted wireless Android connection. Confirm a single BLE owner, scoped credentials/revocation and no replay after reconnect.

## Stream Deck and keyboard
- [x] Install/link 0.6.1 on the 15-key Stream Deck; separate KS Light profile with Power/Color/Effect/Brightness/Off; inspect compact status and power highlighting. Existing personal profiles preserved.
- [x] Physical named Reading key -> simulator and BLE; user confirmed Reading/Off/Purple work. Reading still looks white; warm color accuracy remains unverified.
- [x] Adopt existing connection without entering paths; persist setup across app restart; visually inspect color swatches, hex and brightness; verify editing sends no hub command.
- [x] User confirmed new Power/Color/Effect controls work; reported slow/intermittent delivery and washed colors.
- [x] Connection reuse: user says speed is great; first operation 1.879 s, next ten 0.113–0.232 s with no failures in that sequence. This is a short physical check, not a long-duration reliability claim.
- [ ] Color-response compensation: 0.6.1 maps picker warm orange to the user's demonstrated redder drive values; final shade feedback pending. Brightness and Scene hardware acceptance remain separate.
- [ ] Multiple legacy connections, fresh shared setup, connection changes, per-key opt-out, offline/repeated presses and mixed group/scene status.
- [ ] Dials: action preview/press and brightness preview/press, touch-strip layout, continuous dimming coalescing, busy input, configuration changes, failure pause and deliberate recovery. Preview begins at 50%, not a lamp reading.
- [ ] Optional live display: external hub changes, mixed groups/scenes, offline/recovery, profile switches and reader cleanup. Display remains last-sent evidence.
- [ ] Assign keyboard launchers in macro software without overwriting existing bindings; verify target and action.

## Raspberry Pi and ESP32 â€” Experimental
- [ ] Chosen hardware/backend: dry-run wiring, startup-held buttons, one action per press, busy/offline feedback, status LEDs with suitable resistors/polarity and no replay after reconnect.
- [ ] Rotary direction/detents, bounce/fast turns, preview-only rotation in selector mode, motion while busy, dimming coalescing and explicit recovery after errors/button actions.
- [ ] Pi shutdown/SIGTERM GPIO cleanup and physical lamp output.
- [ ] ESP32 trusted HTTPS, Wi-Fi loss/recovery, USB setup/save/reboot/NVS persistence, busy rejection, forgotten connection staying disabled, scoped credentials and oversized/partial serial input. No board has been flashed.

## Previously observed - do not repeat without a related change
User confirmed direct power/color, native purple breathing smoother than software effects, hub/MQTT commands and Android hub blue delivery. On 2026-09-26 the Samsung catalog/default persistence and widget migration/chooser/pinning/Off fanout/service cleanup/temporary-widget deletion passed. These observations do not establish new scene/favorite widget behavior or multi-light/DIY hardware acceptance.
