# Physical Android test: 2026-09-21

Device: Samsung SM-S938U1, Android 16. Debug APK installed via authorized USB ADB.

## Observed passes
- Install and launch on physical phone.
- Demo discovery, selection, On and Apply-color flows.
- Nearby Devices permission prompt and grant.
- Real BLE scan discovers the test KS03 lamp.
- Real On transaction: UI reports command sent; Android Bluetooth log shows connection status 0, service discovery and disconnect status 0.
- Bottom controls scroll above the system navigation bar after SafeArea fix.

## Issues found and fixed
- Initial permission grant briefly emitted cached BleStatus.unauthorized. Backend now allows a bounded wait for the status update. Added three regression tests.
- Content extended beneath Samsung navigation controls. Added bottom safe-area handling and verified the corrected screen on the phone.

Validation: 18 Android tests pass; Flutter analysis clean; updated debug APK builds and is installed. Python was not changed during this test.

## Acceptance still open
User confirmed physical On and Off work and applying color changes the light. The shade differs from the phone preview; user describes it as mostly correct, not swapped channels. Precise color matching, dimming, power-cycle recovery and background behavior remain unverified.

An On command may leave the light on; original physical state is unknown without readback. USB stay-awake was temporarily enabled for testing, then restored to its original value (0), verified through ADB.

## Follow-up: power feedback, names and color balance
- On/Off now use equal segmented controls, initially unselected with Power: unknown.
- Successful power or Apply updates Last sent: On/Off. Failed transactions clear the indicator because partial delivery is possible. Other controllers and restarts cannot provide live state without readback.
- Rename saves a local alias by device ID; blank restores the advertised Bluetooth name.
- Color balance saves independent red, green and blue multipliers (0-100%) per device. It modifies outgoing color packets without changing the target swatch or brightness byte. Reset restores all channels to 100%.
- Red/Green/Blue/White target presets help compare the physical output. White here means mixed RGB, not the separate white-mode command.
- Color balance is manual compensation, not measured color calibration. Default settings leave packets unchanged. Save does not send a light command; Apply color does.
- Android private SharedPreferences persist names/balance across app restarts and replacement installs. Power and last requested color remain session-only. Corrupt stored settings are not silently overwritten.

Validation: analysis clean; 22 Android tests pass across the suite and focused follow-up, including rename/reload, per-device balance persistence, transformed packet delivery, power selection and error recovery. Updated debug APK built and installed. Physical acceptance of the new controls and tuned shade remains open.

Physical phone follow-up: verified demo Off selection visually; local alias and 99% red balance survived app force-stop/relaunch, with power unknown after restart. Reset restored 100% balance and blank rename restored advertised name. QA settings were confined to the virtual demo light. Real-device balance remains neutral pending user tuning. Final build: analysis clean and full suite 22/22 passing.

User shade feedback: requested RGB239/66/255 appeared as approximate ambient #9F94E3; after suggested balance100/30/75 user reports #8A2BE2. These are subjective ambient comparisons, not measurements. Suggested next experiment100/27/50 is not applied automatically. Named calibration profiles now implemented; 26 tests pass including migration, draft cancellation, independent preset snapshots, built-in selection and validation. Phone UI verified preset selector and Purple trial channel values; canceled QA edits to preserve saved settings. Exact shade acceptance remains open.

Color UX investigation: read this app's settings on the phone. Real light had active gains100/100/75 with Previous balance100/30/75 stored separately; this does not establish why ambient color appears unchanged. No further correction was automatically applied. Added a visual picker, active-balance label, sticky Apply and last-color persistence. Device test caught shade gestures competing with parent scrolling; added explicit tap/axis drag handling and regression coverage. Full suite31/31, analysis clean. Color accuracy remains unverified.

Final picker APK installed on the phone. Verified a tap changes preview from #FF9329 to #C3874C and an in-square drag changes it to #83582C without scrolling the page; sticky Apply remains visible and selection stays Not applied until a command succeeds. QA used the virtual demo light. Existing real-light calibration was preserved.

User accepted calibration as good enough and authorized continuing the roadmap. Close subjective shade tuning for this prototype; no claim of measured color accuracy.

Rooms/scenes APK built, signature verified and installed. On physical Samsung phone, created a demo room, ran All on, captured and activated an Evening scene, force-stopped/relaunched and verified both records remained without rescanning. Deleted only the temporary QA records afterward. Demo actions do not establish physical multi-light acceptance. 40 automated Android tests pass; analysis clean.

Effects update: debug APK installed. On-device demo breathing produced update counts; manual Stop with restore enabled returned the parent to Last sent: Off. A second demo run was stopped by Home/backgrounding and remained stopped when reopening. No real-light effect was run in this turn. Automated suite50/50 and analysis clean; physical cadence/appearance remains open.

## Native preference and live-adjustment follow-up
Installed updated debug APK on Samsung SM-S938U1. Applied Purple breathing at speed 35 / brightness 50, then saved a named Purple evening preset through the app UI. Dragging and releasing speed changed it to 38; the app reported the command sent and settings saved. SharedPreferences confirmed the separate per-light native key, last-applied speed 38 and a preset retaining speed 35. Existing calibration and library records remain separate. Force-stopped and relaunched the app, scanned, selected the same light and opened Effects: Purple breathing, speed 38, brightness 50 and Purple evening were restored with the explicit Tap Apply message. No automatic restart command is expected or issued by this route. Apply and Stop remain pinned and visible. Automated tests verify absence of writes on restore, one update on slider release, persistence failure behavior and background cleanup.

Phone acceptance (2026-09-26): latest APK installed on Samsung via ADB without desktop interaction. Real saved light loaded without scanning, default selection survived force-stop/relaunch into real mode, Add devices rescanned without duplicating/removing the saved light or dropping its default, and clearing default survived restart. Restored the test KS03 lamp as real default and left control screen open. Screenshot checked for layout/labels. No power/color writes sent. Adding a second physical light remains untested; merge behavior across multiple devices has automated coverage.

Safe device removal (2026-09-26): saved-device rows now include Remove with a confirmation describing consequences. Successful persistence removes the light from the catalog, clears its default and membership in collections/scenes, and removes empty collections/scenes. Other members remain intact; calibration/name settings are retained for rediscovery. Native real-library saves clear the shared quick-control target when that saved light is removed; old Device Controls favorites become unavailable. Removal does not turn a lamp off or cancel already-issued commands. Cancellation/save failure preserve visible devices. All 72 Flutter tests pass, analysis clean, debug APK built/installed. Phone confirmation and Cancel checked using demo entry; no real/demo devices deleted and no lamp writes. Native quick-control cleanup after real removal still needs hardware acceptance.

## Independent widget targets completed (2026-09-26)
Implemented separate saved targets, chooser/reconfiguration, upgrade migration, stale-action rejection, removed-light cleanup and deleted-widget cleanup. Flutter analysis clean; 72 Flutter tests and six native routing tests pass. APK built/installed. Samsung phone verified migration, chooser Cancel/save, in-app second-widget pinning, successful Off write, matching status on both widgets, service shutdown and temporary-widget removal/cleared settings. Original widget preserved, last command Off. Desktop untouched. Physical multi-light behavior and launcher-gallery setup remain open; no readback or physical lamp observation claimed.
