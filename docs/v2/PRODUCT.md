# Product specification
## Outcome
An offline-first KS lighting system: Android direct control plus an optional always-on KS Hub, with multi-light scenes, effects, an open local API, Home Assistant, Stream Deck, programmable keyboards and DIY physical controllers. iOS is deferred because no iOS test device is available.

## Agreed scope
Android can operate independently over BLE. A hub can run on a Raspberry Pi or supported computer and owns its assigned Bluetooth devices. Phones and integrations route through the hub for those devices. No cloud service or account is required for core operation. Retain and improve the existing Python CLI.
Public distribution, monetization, final name and store publishing are undecided. Do not add payments, analytics or publish anything based on these documents.

## First complete release
- Discover, name, identify, connect and control supported lights.
- Power, RGB, color-preserving brightness where supported, and capability-aware white controls.
- Rooms, groups, favorites, recent colors, ordered light layouts and multi-light scenes.
- Six initial software effects: breathing, candle, sunset, rainbow cycle, color drift and palette wave.
- Palette, speed, intensity and transition controls; stop and optional restore.
- Android Bluetooth and hub modes with clear connection/permission recovery.
- Hub REST and WebSocket API, MQTT and Home Assistant discovery.
- Stream Deck keys and compatible dials; Windows shortcuts and CLI invocation.
- Raspberry Pi service and GPIO examples; a tested ESP32 button and rotary controller.

## Experience
Home shows rooms, lights and quick actions. A light screen shows supported controls only. Scenes store per-light values, not just one value applied to all. Effects expose simple parameters before a timeline editor.
A manual adjustment stops the affected software effect on that light. For a coordinated group run, default to stopping the whole run so choreography does not silently change; offer an explicit detach-one-light action later.
Master brightness scales original scene values instead of repeatedly scaling rounded output.
Identify is a short temporary pulse, then restores last known requested settings; warn when true prior state is unavailable.
Every surface distinguishes unavailable, pending, last requested and device-confirmed state.
No fake success indication just because a network request was accepted.

## Later work
Timeline editor; microphone music response; device-native effects and timers after protocol research; per-light calibration; Tasker actions; widgets and Quick Settings; sensor recipes; native Home Assistant BLE integration; standalone ESP32 BLE remotes; iOS.
Exact synchronization, individually addressable pixels, firmware updates, Matter and away-from-home control are not first-release promises.
Phone-hosted schedules/effects require appropriate lifecycle support. Reliable unattended scheduling belongs on the hub or a verified device timer.

## Quality targets
- No effect leaves an unbounded command backlog.
- Stop takes priority over pending effect frames.
- Multiple integrations do not race independently for a BLE connection.
- One offline light does not prevent a group operation reporting the others' results.
- Restart never silently resumes a flashing effect.
- User exports exclude API tokens, logs with credentials and device identifiers unless explicitly included.
- Accessible labels, scalable text, adequate contrast and usable touch targets.
