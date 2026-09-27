# Android rooms, groups and scenes

## Implemented
Open **Rooms & scenes** from the top-right dashboard icon. Scan first to save lights in the local catalog. The catalog survives restarts; a missing scan advertisement does not delete a light or imply confirmed availability.

- Create named rooms or groups containing 1-32 saved lights. A light may belong to multiple collections.
- All on / All off sends to each member in order.
- Set each light's color and brightness with Apply, then use Save scene. Select members and choose On or Off for each. On captures that light's last successfully applied target RGB and brightness; pending picker edits are excluded. Without a saved color it records power-on only.
- Activate recalls the snapshot using each light's current calibration. Off does not discard its remembered color.
- Rooms, groups and scenes can be edited or deleted. Edit collection changes its name, room/group type and members. Edit scene changes its name, members and each member's On/Off setting. Existing scene colors remain unchanged by default; enable Use latest applied colors to recapture current saved settings. New members use their last applied color. Editing sends nothing. The Library backup menu copies rooms/scenes as text and imports a reviewed copy.
- Demo and real-device catalogs are stored separately. No startup command or automatic scene replay occurs.

## Delivery and cancellation
Only one BLE transaction runs at once. One unavailable member does not stop the remaining members. Results identify every delivered, failed or cancelled target; delivery remains unconfirmed physical state.
Unsupported color/brightness combinations fail before sending that target's power command. A persistence failure after a successful send is reported separately from BLE delivery failure.
Stop after current light waits for the active transaction to finish/clean up, then skips remaining members. It does not restore already changed lights. Navigation is held during active operations to avoid concurrent direct commands.

## Persistence
Version 1 library JSON is saved through Android private SharedPreferences with a committed update. Invalid/version-mismatched data is retained and reported instead of silently reset. Scans merge known records; they never prune absent lights.
Per-phone device IDs currently match Android BLE identities. Hub logical IDs and explicit device remapping remain future work. Rooms/scenes can be imported when the same saved light IDs and profiles already exist on the receiving phone. Stored profiles reference the bundled registry by prefix rather than accepting arbitrary UUID/packet definitions.

## Validation and limits
40 Android tests pass. New tests cover room/scene persistence, independent scene snapshots, demo separation, calibrated multi-target packets, serial writes, one offline member, incompatible modes, cancellation before pending targets, and separate delivery/storage failures. Widget tests exercise create, reopen and activate flows.
Only one physical KS03~ light is known. Multi-light timing, real offline-member behavior and true physical group synchronization have not been tested; no simultaneity is promised. M3 is implemented and automatically verified, with multi-light hardware acceptance open.

Editing validation (2026-09-26): saved colors survive rename; explicit recapture updates them; case-insensitive duplicate names and empty membership are rejected. A collection and scene may share a name without edits crossing between them. Cancel and storage failure preserve the original data and default device. Four new widget tests pass; full Flutter suite is 82 tests with clean analysis. New editing UI acceptance on the locked phone remains pending.

## Copy and import rooms/scenes
Open the top-right Library backup menu. **Copy rooms & scenes** puts a versioned JSON backup on the clipboard; paste it into a text file or another place you choose to keep it. The app does not send it to a cloud service. This export contains collection membership, scene snapshots and the light identities needed to match those definitions.

Choose **Import rooms & scenes**, paste the backup and tap **Review**. Review lists the exact names that will be added. Matching names get numbered copies instead of replacing existing definitions. Tap Import to save, or Cancel to keep the current library. No light commands are sent while copying, reviewing or importing.

Scan/save the same lights before importing on another phone. Light IDs and profile prefixes must match; device remapping is not automatic. Demo backups stay in demo mode. Current device names, default selection, calibration and widget settings are preserved; hub credentials are not part of this backup. Scene colors use the receiving phone's current calibration when later activated.

Limits are 256 KiB of UTF-8 backup text, 100 collections, 100 scenes and 256 referenced lights; the resulting library must fit those limits. Each collection/scene remains limited to 32 members. Unsupported versions, unknown lights, profile mismatch, incompatible scene settings and malformed text are rejected before saving. The original library remains usable after cancellation or storage failure.

Validation: 90 Flutter tests pass with clean analysis. Added checks cover copy/paste review, preserving originals and defaults, storage failure, demo separation, stale device/profile identity, malformed/oversized inputs, unsupported scene brightness, Unicode-safe duplicate naming and a 360-pixel-wide import dialog. Physical clipboard/paste and on-phone editing checks remain pending after the phone disconnected.

## File backups and device matching

Library backup now offers Export backup file and Open backup file through Android’s system document picker. Only the selected document is accessed; no broad storage permission is needed. Imports accept UTF-8 files up to 256 KiB and retain the preview/review/Import sequence. Picker cancellation changes nothing. Clipboard backup remains available.

Match backup devices lets each source light map to a saved target of the same model. Every target must be unique, and mappings apply to both collection memberships and scene states. The final review lists source and destination names/IDs. Existing definitions receive numbered copies, while target names, default device and calibration stay unchanged. Backups contain rooms/scenes and their referenced device identities, not calibration or hub credentials. Native file-provider and replacement-device acceptance remain pending.
