# Android hub control

Open the new Hub control icon in the app bar. The hub screen controls a selected light from the hub catalog: On/Off, RGB, brightness, and Purple breathing (speed 35). Commands go through the hub API and its Bluetooth queue. The screen itself makes no BLE calls. Other controllers still need coordinated ownership; opening this screen does not disable the existing HA integration.

Connection address and token are held only in memory for the open screen. Closing it disconnects the HTTP client and forgets the token. There is no saved credential/pairing flow yet. HTTPS uses normal certificate validation. Redirects are rejected so credentials are not forwarded elsewhere. Plain HTTP is limited to localhost/loopback for USB development; no general cleartext LAN access was enabled.

## USB development connection
Run the Python hub on the PC, initially in simulation mode, with its normal bearer token. Forward the phone's loopback port through ADB:

```text
adb -s PHONE_SERIAL reverse tcp:8765 tcp:8765
```

On the phone, open Hub control, use http://127.0.0.1:8765 and enter the hub's token. The debug APK permits cleartext only for localhost/127.0.0.1. Remove the forwarding when finished with the matching adb reverse --remove command. The test token used during development is no longer active after the simulator stops; create/use your own token for subsequent runs.

The configured Python service now supports an explicit HTTPS listener; see SERVICE_DEPLOYMENT.md. Wireless use still requires a trusted certificate/name and a reachable deployment. This build does not automatically expose the hub on the network or change firewall settings.

## State and command behavior
The screen explicitly identifies simulation versus live mode. Power/brightness/effect labels show the hub's last-sent state, not physical readback. Refresh fetches the catalog and MQTT health; there is no background polling yet. Picker/slider edits do not transmit until Apply. Brightness-only updates need a remembered static color or native effect. Purple breathing continues on the lamp after a client disconnects.

Each submission gets a unique retry key and is sent once. The client polls the returned operation ID for completion. A lost response or polling connection reports uncertain delivery and does not replay the command. Closing the screen cannot undo an already accepted hub command. Network requests have timeouts and bounded response sizes; active requests close when the screen exits.

Existing local calibration, renamed direct-BLE lights, groups, scenes and presets remain in their existing screens and are not imported into hub control. Native effects currently use the confirmed Purple mode only. Hub connection/pairing persistence, full integration into the normal app controls, background synchronization and secure wireless setup remain planned.

## Validation (2026-09-22)
Flutter analysis is clean. The four new client tests cover secure endpoint validation, bearer authentication and single command submission with completion polling, redirect refusal, and uncertain completion without replay. The existing 63 tests previously passed with the initial screen; the final full-suite result is recorded in ROADMAP.md.

On the connected Samsung phone, the debug build connected to a Python simulator over USB. On completed as simulated, applying Blue produced hub state RGB 0/0/255 at 50%, and Purple breathing produced native effect 137 at speed 35 and brightness 50. After stopping the server, the screen reported uncertain delivery and re-enabled controls. No physical light commands were sent during this Android hub test. The final layout pins command status at the bottom so it remains visible while scrolling.


Physical USB acceptance (2026-09-22): the phone's Hub control screen connected to a live hub and applied Blue at 50%. The hub recorded RGB 0/0/255 and the user confirmed the real lamp was steady blue. This verifies Android -> USB -> hub -> Bluetooth. The old HA integration was paused for the test and restored afterward. The live test process was stopped, USB forwarding removed, the temporary token removed, and the hub screen closed. No Android code or APK change was needed for this acceptance check. Wireless phone acceptance remains open.

## Hub groups and scenes (2026-09-26)
When the connected hub advertises groups/scenes, this screen also loads its configured library. Groups have All on/All off buttons; scenes have Apply. Each entry shows its member count. Selection/loading never sends a command. The same busy gate protects individual and collection actions, including duplicate callbacks before the UI rebuilds.

A collection command submits once, waits for completion (up to a 90-second polling budget plus an in-flight request timeout), and displays an expandable result for every member. Mixed delivery explicitly reports the completed count and failed/cancelled lights, with no replay. An uncertain network result asks the user to inspect the hub instead of resending. Result IDs and confirmations are validated; mismatched or malformed responses remain uncertain. Older hubs without collection capabilities keep their existing single-light UI.

Definitions come from the hub's optional library file (HUB_LIBRARY.md), not the phone's direct-BLE library. Android groups now support color, brightness and native breathing previews; hub scene-definition editing/import remains future work. These changes do not alter direct-BLE calibration or saved devices.

Validation: all 78 Flutter tests pass, analysis is clean, and the debug APK builds and verifies. Tests cover feature discovery, malformed catalogs, partial results, uncertain/mismatched responses and duplicate/busy UI actions. A standalone production Dart client also completed group Off and a mixed RGB/native scene against the real Python simulator API. The APK installed on Samsung, but the phone was locked; the new on-phone group/scene UI check remains pending. No physical BLE writes were made.

Hub color balance: each selected light now displays its configured hub RGB gains when advertised. Values are validated before display; older hubs need not provide them. The hub applies gains to static colors only. The latest Dart-to-Python simulator check verifies calibrated wire RGB while last-sent API RGB remains the logical requested color. Phone calibration is not automatically copied or changed.

## Saved pairing

Remember this hub saves the address and token only after a successful connection. Android Keystore protects an AES-GCM encrypted file in the app’s no-backup directory. Load saved hub fills the fields but requires an explicit Connect action; it does not send light commands. Forget saved hub removes the local stored pairing; token revocation is a separate hub action. Pairing is optional, and storage failure keeps the active connection temporary. Keystore loss or reinstall requires pairing again. This does not make an untrusted HTTPS certificate trusted. Native device/restart acceptance remains pending.
