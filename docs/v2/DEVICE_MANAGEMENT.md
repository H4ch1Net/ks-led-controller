# Saved devices and default light

Implemented 2026-09-26 in Android direct control:
- Previously saved lights are shown without rescanning. Use Change light to return to the list.
- Add devices scans for supported nearby lights and merges them into the saved catalog by ID; existing lights remain available when offline. Existing room/scene definitions remain intact.
- Star a saved light, or choose Set as default device on its control screen. Choosing another replaces the default; tapping the selected default clears it.
- A saved real default opens on startup in Bluetooth mode without scanning, requesting permissions or sending a command. A demo default remains separate and cannot override a real default. Selecting a saved device does not assert it is online.
- Old libraries load with no default. The default ID must belong to the saved catalog. Failed saves do not change the displayed default.

The app default does not silently retarget existing widgets, Quick Settings, Device Controls favorites, hub actions or Stream Deck keys. Those keep their explicitly configured targets; configure shortcuts from the desired light when changing them. Independent per-widget targets and safe device removal are implemented; see the sections below and ANDROID_SHORTCUTS.md.

Validation: existing 67 Flutter tests passed; three new tests cover legacy/default serialization, merged saved devices, selection/clear/restart with no writes, and failed default persistence. Debug APK built. Hardware and visual desktop/phone testing deferred at user request. No desktop interaction or phone commands used.

Phone acceptance (2026-09-26): latest APK installed on Samsung via ADB without desktop interaction. Real saved light loaded without scanning, default selection survived force-stop/relaunch into real mode, Add devices rescanned without duplicating/removing the saved light or dropping its default, and clearing default survived restart. Restored the test KS03 lamp as real default and left control screen open. Screenshot checked for layout/labels. No power/color writes sent. Adding a second physical light remains untested; merge behavior across multiple devices has automated coverage.

Safe device removal (2026-09-26): saved-device rows now include Remove with a confirmation describing consequences. Successful persistence removes the light from the catalog, clears its default and membership in collections/scenes, and removes empty collections/scenes. Other members remain intact; calibration/name settings are retained for rediscovery. Native real-library saves clear the shared quick-control target when that saved light is removed; old Device Controls favorites become unavailable. Removal does not turn a lamp off or cancel already-issued commands. Cancellation/save failure preserve visible devices. All 72 Flutter tests pass, analysis clean, debug APK built/installed. Phone confirmation and Cancel checked using demo entry; no real/demo devices deleted and no lamp writes. Native quick-control cleanup after real removal still needs hardware acceptance.
