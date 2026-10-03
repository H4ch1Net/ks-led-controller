# Android rooms, groups and scenes

Rooms, groups and scenes on the phone use direct Bluetooth and the saved light catalog. They are separate from [hub groups and scenes](HUB_LIBRARY.md).

## Collections

Open the **Scenes** tab. A room or group holds 1 to 32 saved lights; a light can belong to several. **All on** and **All off** send to each member in order.

Edit a collection to change its name, type (room or group) or members. Deleting a collection does not change the lights.

## Scenes

1. Apply the color and brightness you want on each light.
2. **Save scene**, select members and choose On or Off for each.

An On member stores that light's last successfully applied color and brightness. Unapplied picker edits are not captured. A light with no applied color is stored as power-on only.

**Apply** recalls the snapshot using each light's current color balance. Editing a scene changes its name, members and On/Off settings but keeps stored colors unless **Use latest applied colors** is enabled. Editing never sends commands.

## Delivery

- One BLE transaction runs at a time. Members are sent in sequence, not simultaneously.
- An unavailable member does not stop the rest. The result lists each light as delivered, failed or cancelled.
- **Stop after current light** waits for the active write, then skips the remaining members. Already changed lights are not reverted.
- Nothing is sent on startup and scenes are never replayed automatically.

## Backup and import

The **Library backup** menu in the Scenes toolbar offers:

| Action | Result |
| --- | --- |
| Export backup file / Open backup file | Save or load a JSON file through the Android document picker. No storage permission is needed. |
| Copy rooms & scenes / Import rooms & scenes | The same JSON through the clipboard. |

Import always shows a review first. Existing definitions are kept; name conflicts become numbered copies. **Match backup devices** maps each light in the backup to a saved light of the same model on this phone, so a backup can move to replacement lamps.

A backup contains collections, scenes and the light identities they reference. It does not contain calibration, names, the default light, widget settings or hub credentials. Limits: 256 KiB of text, 100 collections, 100 scenes, 256 referenced lights, 32 members per entry. Malformed, oversized or incompatible backups are rejected before anything is saved.

Demo and real libraries are stored separately, and demo backups import only in demo mode.
