# Android widgets and Quick Settings

## Implemented first version
A home-screen power widget and a Quick Settings tile now control one explicitly selected KS03~ light directly over Bluetooth. No PC, hub or MQTT broker is needed.

In the app, turn off Demo mode, scan/select the real light, and tap **Widget & Quick Settings**. Choose **Add widget** or **Add quick tile**, then complete Android's dialog. Older Android versions can add the tile through the normal Quick Settings editor. Configuration persists across process restarts. Each widget stores its own light. Tap its name to choose another saved KS03 light. The tile and Device Controls use the explicitly configured shared shortcut target; changing that target or the app default does not redirect existing widgets. Launcher-added widgets open a chooser; in-app Add widget snapshots the selected light.

The widget offers separate On/Off buttons, or Color/Off when configured with a favorite. The tile toggles the last power command sent by the app/shortcut and labels its next action. The tile highlights On after a successful On write and becomes inactive after a successful Off write. This is the last command sent, not verified physical state: reliable readback is unavailable. External controllers are not tracked. Tapping an unconfigured widget opens its light chooser; an unconfigured tile opens the app. Locked Quick Settings use Android's unlock flow.

## Background execution
User actions start a short foreground Bluetooth service with a temporary notification. It connects only to the configured KS03~ service AFD0/characteristic AFD1, sends the existing power packet (followed by one calibrated color packet for a favorite), disconnects and stops. It has a 15-second overall deadline, rejects overlapping shortcut taps and never retries an uncertain physical write. Missing Bluetooth permission, Bluetooth off, failed discovery and write/timeout errors appear in widget status. Open the app to grant permissions; the shortcut does not request permissions in the background.

A process-wide ownership lock coordinates the shortcut service and the Flutter Bluetooth backend, including retained effect sessions. Shortcut attempts while an in-app session owns Bluetooth report busy instead of creating another connection. Other apps, the HA integration and a separately running hub are outside this lock. OS force-stop can prevent shortcuts until the app is reopened. OEM battery policies and more Android versions need acceptance testing.

## Scope and validation
Widgets cover power and favorite colors for KS03~ devices, with independent targets. Saved scene widgets are implemented below; effect-specific widgets remain a possible extension. The first Android Device Controls provider is implemented below.

The debug build compiles, Flutter analysis is clean, and the existing 67 Flutter tests pass. Those tests do not establish native service lifecycle or Bluetooth hardware acceptance. On the Samsung phone, real-light configuration and home-screen widget placement were verified; the widget recorded a completed Off command and the service stopped afterward. Physical user acceptance and Quick Settings activation results are recorded in ROADMAP.md. A Samsung launcher preview failure was addressed by adding an explicit preview layout.

References: [Android Quick Settings tiles](https://developer.android.com/develop/ui/views/quicksettings-tiles), [Bluetooth background communication](https://developer.android.com/develop/connectivity/bluetooth/ble/background).

## Compact widget refinement (2026-09-22)
Redesigned the widget as a rounded single-row card with 48dp On/Off touch targets, smaller typography, a short last-command label, and a tappable details area that opens the app. Default device IDs display as KS Light; custom names remain intact and the full name/status are available to accessibility services. Neither button claims a verified physical power state. New placements request 2x1 cells and support one-row resizing.

Debug APK built and installed successfully. On the Samsung launcher, the existing 4x2 placement was resized to 2x1 and visually checked: title, status and both controls fit without clipping. Existing BLE command behavior is unchanged; no light commands were sent during this layout check.

## Quick Settings state feedback (2026-09-22)
The tile now uses active/inactive styling for the persisted last successful power command, with On/Off subtitles, Sending feedback and retry feedback on errors. Failed commands do not flip the stored state. Accessibility describes the last successful command and next action. Default KS03 device IDs display as KS Light; custom names are preserved. Android uses the system tile styling.

Validation: debug build and installation passed. Actual Quick Settings taps on Samsung completed On and Off Bluetooth writes; UI inspection showed checked=true with On and checked=false with Off, and the On highlight was visually verified. Final command was Off. Physical lamp behavior still requires user observation; no readback is claimed.

## Android Device Controls (2026-09-22)
Implemented an Android 11+ ControlsProviderService for the configured KS03 light, with a power toggle, last-command status and updates when the widget, tile or app records power. The Quick controls dialog now includes Add device control, requesting the system favorite-add dialog. System panel availability and placement vary by launcher/vendor. The provider is disabled below Android 11; widget and tile behavior remain available.

Controls use the same bounded foreground BLE service and ownership lock. The action response acknowledges dispatch, while subsequent status reports delivery or error. Highlighting represents last successful power write, not readback. Each favorite embeds its target address; a removed/reconfigured target is unavailable and cannot silently control the replacement. Publisher subscriptions honor demand, retain only latest snapshots and unregister listeners on cancellation/service destruction.

Validation: debug build/install succeeded; Android package discovery lists KS Light as a protected Device Controls provider alongside the phone's existing providers. Flutter analysis is clean and all 67 existing tests pass; these do not cover native ControlsProviderService behavior. Phone locked before system favorite-add and toggle acceptance could be checked. Those UI/hardware gates remain open. No lamp commands issued during this slice.

Device Controls setup follow-up (2026-09-22): Samsung displayed the system Add to Device control panel confirmation and accepted KS Light. Enabled the Device control panel entry in Quick Settings (Samsung labels it SmartThings in the add-controls picker). The panel app selector lists KS Light. Final provider toggle/write acceptance remains open; Google Home became foreground during navigation. No lamp commands were sent in this follow-up.

Device Controls on-phone acceptance (2026-09-22): selected KS Light in Samsung Device control panel, tapped its power icon for On and Off, and observed live Last sent: On then Last sent: Off updates after successful BLE writes. ShortcutPowerService was no longer running after completion. Left KS Light selected in the system panel, last command Off. Physical lamp appearance is not inferred from software delivery. Samsung opens app details when tapping the card body; the small power icon controls power. No application code changed in this verification.

## Independent widget targets (2026-09-26)
Each widget has separate persisted configuration and distinct button intents. Existing widgets migrate their previous target on upgrade. Queued actions for deleted widgets or changed targets are rejected. Removing a saved light clears widgets assigned to it; they show setup rather than falling back to another light. Deleting a widget clears its settings. Pin callbacks and chooser saves revalidate that the widget and saved KS03 device still exist. Successful power writes update only shortcuts matching that address. Labels and setup respect system bars.

Validation: clean Flutter analysis, 72 Flutter tests, six native JUnit routing tests, debug build and installation passed. On Samsung Android 16, verified existing-widget migration, chooser Cancel/save, in-app pinning of a second widget, separate persisted configurations, a completed Off write from the new widget, matching status updates on both widgets, service shutdown, and deleting the temporary widget with settings cleanup. The original widget remains in place. Physical lamp appearance was not independently observed. Different physical-light targets, launcher-gallery setup and live device-removal cleanup remain acceptance checks; routing tests cover distinct targets, stale actions and removed widget IDs.

Native tests: from apps/android/android run `gradlew.bat :app:testDebugUnitTest` (or `./gradlew` on Unix).

## Favorite-color widgets (2026-09-26)
Apply a color and brightness in the app, then tap the home-screen widget name. Choose a light and select its Favorite option. The widget stores a snapshot, so later color changes in the app do not replace the favorite. Color turns the light on and applies the snapshot; Off remains a separate button. To replace the favorite, apply the new color in the app and repeat setup. Cancel preserves the existing widget. In-app pinning still starts with power controls.

Calibration is read when sending, so calibration adjustments also affect existing favorites without calibrating a color twice. One Bluetooth connection and ownership lock cover both writes. Failed or uncertain delivery is not automatically retried. Reconfigured favorites reject already queued actions for their previous configuration. Last-sent power feedback is updated only after the full command sequence completes; it does not establish physical color or power readback.

Validation: native compilation and nine native unit tests passed. Tests cover packet bytes, brightness conversion, calibration before channel ordering, invalid settings and queued-action routing. Launcher UI and physical color delivery await the phone. No APK/export refresh was performed for this source batch.

## Scene widgets and connection help (unreleased source)

Tap a widget name and choose a saved scene. Eligible scenes contain 1..8 saved KS03 lights. The compact widget offers Scene and Off: Scene applies each member's saved power/color/brightness, while Off turns every member off. The widget stores a snapshot; editing the app scene does not silently replace it. Reopen widget setup to replace the snapshot. Calibration is read when sending and applied once.

All member packets are validated before connecting. One foreground service and transport lock process lights sequentially, with a 15-second deadline per member. A failed member is not retried; the remaining members can proceed. The widget shows completed/total delivery, and tapping its name shows per-light results. Removing a member clears that widget's configuration. Deleting or reconfiguring a widget stops remaining members at the next connection boundary; already submitted commands cannot be undone. App/service destruction aborts remaining work without replay. Scenes are not atomic or physically synchronized.

The main app's **Connection help** button shows Bluetooth availability, permissions, current KS Light ownership, saved-light/widget counts and relevant recovery steps. Refresh and copying a report do not send lamp commands. Reports include only allowlisted diagnostics, excluding addresses, names, network details and credentials.

Validation: native source compilation and one focused mixed-scene/All-off packet-planning test passed. The diagnostics widget check passed and Flutter analysis is clean. Phone layout, service interruption, multiple lights and partial failures remain hardware/lifecycle acceptance checks. No new APK was exported or installed.
