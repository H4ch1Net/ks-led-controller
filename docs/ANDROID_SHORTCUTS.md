# Android widgets, Quick Settings and Device Controls

Shortcuts control KS03~ lights directly over Bluetooth without opening the app. No hub or broker is needed.

## Setup

In the app, select a real light (Demo mode off) and open **Widget & Quick Settings** from the light menu. Choose **Add widget**, **Add quick tile** or **Add device control**, then confirm Android's dialog. The tile can also be added from the system Quick Settings editor, and widgets from the launcher's widget gallery (which opens a chooser).

Tap a widget's name to reconfigure it. A widget can be one of:

| Widget type | Buttons | Target |
| --- | --- | --- |
| Power | On, Off | One saved KS03~ light |
| Favorite color | Color, Off | One light plus a stored color and brightness snapshot |
| Scene | Scene, Off | A saved scene with 1 to 8 KS03~ lights |

Each widget stores its own target. Favorite and scene widgets store a snapshot: later edits in the app do not change them until the widget is reconfigured. Color balance is read at send time, so balance changes do apply.

The Quick Settings tile and Device Controls share one configured target. Changing the app's default light does not retarget any shortcut.

## Behavior

- A tap starts a short foreground service with a notification. It connects, sends the power packet (plus one color packet for a favorite), disconnects and stops. Overall deadline: 15 seconds per light.
- Scene widgets validate all packets first, then send to members in sequence with a 15-second deadline each. A failed member is skipped and not retried. Tap the widget name to see per-light results. Scenes are not atomic or synchronized.
- Overlapping taps are rejected. Uncertain writes are never retried.
- A process-wide lock is shared with the app. If the app holds Bluetooth (for example during an effect), the shortcut reports busy instead of opening a second connection. Other apps and a separate hub are outside this lock.
- Status shows the last successful command (for example "Last sent: Off"), not lamp state. The tile is highlighted after a successful On and inactive after a successful Off. Failed commands do not change the stored state.
- Missing permission, Bluetooth off, discovery failures and timeouts are shown on the widget. Open the app to grant permissions.

## Device Controls

On Android 11 and newer, KS Light registers a Device Controls provider with a power toggle and last-command status. Panel location and naming vary by vendor (Samsung lists it under the device control panel). Each control is bound to its light's address; if that light is removed or the target changes, the control becomes unavailable instead of controlling another lamp.

## Cleanup rules

- Removing a saved light clears every widget assigned to it (and scene widgets containing it). They show setup instead of falling back to another light.
- Deleting a widget clears its settings. Reconfiguring or deleting a scene widget stops the remaining members at the next connection boundary; commands already sent cannot be undone.
- A force-stopped app can block shortcuts until it is reopened. OEM battery policies can also interfere.
