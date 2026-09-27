# Android effects

## On-light effects (KS03~)
Single-light Effects opens the device-native controls first. Purple breathing is physically tested and the user confirmed smoother animation. Nine gradual built-in modes, speed and brightness controls are available; the other modes still need individual visual acceptance. One settings transaction starts the animation on the light itself. It continues after leaving or closing the app. Stop and turn off sends Off; applying a static color replaces the dynamic mode. Built-in palettes do not use channel calibration. Native controls have no per-frame traffic or automatic state polling.
Optional state readback currently reports unavailable on the tested firmware, which returns identification data instead of a recognized state. Do not treat the displayed last command as device-reported state.

## Saved native settings and live adjustment
Each real light has its own last successfully applied effect, speed and brightness, plus up to 20 named presets. Native preferences use separate per-light storage keys; they do not modify calibration, static colors, rooms or scenes. Save preset captures current choices without sending a lighting command; using an existing name updates that preset. Delete removes only that preset.
Reopening restores choices without transmitting or claiming that the light is currently running them. Tap Apply once to enable live adjustment for this screen visit. Thereafter sliders send one transaction on release; changing the effect or selecting a preset also applies it. No animation frames are streamed. Off disables live adjustment.
Apply and Stop remain pinned above Android navigation. Backgrounding disables live adjustment and closes the BLE session after an active operation finishes, while the native animation continues on the light. Returning does not reconnect or resend until another explicit action. Connection cleanup finishes before a new session opens. Save failures are reported separately from successful lighting commands. If saved preferences cannot be decoded, saving is disabled rather than overwriting them.

## Custom effects from phone
Select an RGB-capable light and tap Effects, or use Effects on a saved room/group. Every member must have a supported RGB profile; power-only groups are rejected before starting.
Choose an effect, cycle/duration (10-120 seconds), intensity (5-100%) and applicable palette. Start turns the selected lights on. Stop holds the final color unless Restore previous settings is enabled.

## Effects
- Breathing: smoothly sampled brightness envelope on the first palette color.
- Candle: deterministic warm amber fluctuations.
- Sunset: one pass from warm gold to dim red; holds final red when finished.
- Rainbow: continuous full hue cycle.
- Color drift: interpolation through a selected palette.
- Palette wave: palette progression offset by each member's saved order.
Aurora, Warm, Ocean and Pink & violet palettes are available. Candle, sunset and rainbow use their own colors. Current per-light calibration is applied to every frame. KS03~ breathing holds calibrated RGB constant and varies the separate brightness channel. Other custom effects scale RGB. KS03~ brightness is encoded as 0..100 while the app stores normalized 0..255 values.

## Scheduling and stop
This is a conservative foreground software preview, not a device-native effect or background service. No new protocol commands were introduced.
There is one write in flight and no frame queue. For 1-4 targets, each connection is opened/discovered once and held until stop, completion or failure. The scheduler targets one frame every 150 ms (about 6.7 Hz); unchanged calibrated packets are skipped. Power-on is sent once per target, then frames contain only color. Groups above four targets retain sequential short-lived connections to bound simultaneous GATT connections. Slow writes reduce the update rate. Samples are calculated from a monotonic Stopwatch, so missed intermediate frames are skipped rather than replayed.
Groups are sequential and not synchronized. Actual light rendering and practical BLE update limits remain hardware dependent. Manual sends still use short-lived connections; inter-command waits are reduced to 100 ms, with a 100 ms drain delay before disconnect instead of 300 ms after every packet.
Stop marks the run as stopped, wakes an idle wait, lets the active transaction complete and clean up, skips later members/frames, then optionally restores. No manual commands in the app can overlap because the effect route stays open until completion; stop first to return to manual controls.
An offline member is removed for the remainder of a run. Other members continue; if all fail the run exits. There is no unbounded retry loop.

## Restoration and lifecycle
Snapshots are taken at run start. Restore is available only for a known last-sent Off, or known last-sent On plus a remembered RGB/brightness. Unknown prior states are skipped rather than guessed. These are app observations, not device readback; another controller can invalidate them.
On normal stop, restoring is ordered after the active transaction. Restore errors are shown per target. Sunset completion holds the final frame even when manual-stop restoration is enabled.
Leaving the app (including inactive/paused lifecycle transitions) stops new effect updates and suppresses further restoration transactions. An already-active transaction can finish. Returning does not restart the effect. App restart does not resume effects.
Last delivered state is sent back to the manual controls and persisted once after the run, not on every frame. A failed target becomes unknown. Background stopping leaves the last effect color on the light; it is not an Off command.

## Validation and remaining work
58 Android tests pass across suite and focused reruns; Flutter analysis clean; debug APK builds. Tests cover all six sampled effects, output ranges, palette wave offsets, sunset completion, invalid parameters, stop during active writes, restore ordering, unknown-state skip, isolated offline failure, calibrated packets, waking idle waits, connection reuse, power-on-once, session serialization/cleanup, and lifecycle stop without automatic resume.
On Samsung SM-S938U1, demo breathing started and stopped; restoring a known Off setting returned the parent control to Last sent: Off. A second demo run stopped after Home/app foreground transition and stayed stopped on return.
After the transport update, the real KS03 light accepted repeated effect writes (79 observed at one checkpoint); Android logs show one connection/discovery across a 27-second run, then clean disconnect on Stop. The status label refreshes at most once per second during a run. Transport success does not confirm physical output.
Physical light effect quality, real group timing and restore behavior under actual BLE loss remain open. Effect configuration is session-only. Persistent named effect definitions, a custom palette editor, background services and the hub effect implementation remain future work.
