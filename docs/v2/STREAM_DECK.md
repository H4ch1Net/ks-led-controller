# Stream Deck plugin 0.6.1

## Current status

Version **0.6.1** includes separate **Power**, **Set Color**, **Effect**, **Brightness** and **Scene** actions. Drag an action from KS Light in Stream Deck's sidebar and choose its target/settings. All five share one hub connection. If a single existing legacy connection is visible, the first new settings panel adopts it automatically. Otherwise configure **Shared hub connection** once; per-key paths are no longer required. Existing advanced named-action keys and dials remain compatible.

- **Power:** Toggle, On or Off. The icon highlights the hub's last-sent On state. Toggle requires a known, non-restored state; use explicit On/Off after unknown state or a hub restart.
- **Set Color:** native color picker, editable hex, swatches, brightness and Color response. Balanced (gamma 2.2) and Stronger saturation (gamma 2.5) compensate intermediate RGB levels before hub calibration; Raw RGB preserves legacy output. Existing keys without a response setting stay Raw; new empty color keys default to Balanced. The user's orange example motivated Stronger saturation: picker `#FF7800` maps to `#FF2700`. This is adjustable perceptual compensation, not measured display/lamp color matching. The key displays its selected picker color. Settings save automatically; only a physical press sends them.
- **Effect:** Breathing with separate built-in color selection, seven-color fade or RGB fade, speed and brightness. These run smoothly on the lamp. Arbitrary RGB breathing is not a native capability exposed by this hub.
- **Brightness:** set a level using the last color/effect; turns the lamp on. The hub rejects it when no color/effect is known.
- **Scene:** choose an existing hub scene. Empty or incompatible catalogs do not substitute another device.

Live labels distinguish Sim/Saved/Sent; they are not physical readback. Full RGB/effect identifiers stay in the hub; keys show compact Color/FX + brightness. Status refreshes do not replay commands. Configuring a key never sends a lamp command.

## Local device setup and evidence (2026-09-27)

**Accepted:** the user confirmed the final compensated color works great and considers this Stream Deck work complete. Power/Color/Effect, faster repeat delivery and adjusted color response are accepted for the current lamp.

A separate **KS Light** profile is installed on the 15-key Stream Deck: Power toggle, Color, Effect, Brightness and explicit Off. Existing personal profiles were preserved. The connection was adopted from the prior named-action setup and persisted across app restart. Color swatches/hex/brightness were visually inspected, and changing to blue saved without any new hub operation. Power icons and compact last-sent labels were inspected after restart.

The user physically accepted the earlier Reading/Off/Purple keys, including lamp Off and purple breathing. Reading looked white even after an amber adjustment; no warm-color accuracy claim is made. The hub is using neutral calibration, separate from phone-local calibration. The user then confirmed new Power/Color/Effect controls work, but reported slow/intermittent delivery and washed colors. The hub transport was subsequently changed to retain at most two connections for 30 seconds of idle time, use the Android 100 ms packet spacing, and discard a failed session without replay. Earlier operation durations were about 2.2–10 seconds. Four connection lifecycle checks pass; 22 existing hub/controller checks also passed. Post-patch hub evidence: first command 1.879 seconds, next ten 0.113–0.232 seconds, all succeeded; these exclude Stream Deck client startup. User confirmed speed is great. Color still required overcompensation, so 0.6.1 adds selectable response curves; exact matching remains lamp-dependent. The RGB packet layout remains the one found in the original app.

Focused validation: 15 Node runner/status checks and 5 Python bridge/status checks passed. The bundled SDK smoke passed direct RGB packet bytes, power toggle, native effect and brightness through Python and the simulator, including no writes on action appearance. Existing named keys/dials remained passing in that smoke. A focused response-curve check also verifies legacy/raw compatibility, primary endpoints and the orange mapping. Build and official manifest validation passed. No broad Android or unrelated regression run was performed.

Private files and **Start KS Light Hub** shortcut are in `.hub-local/streamdeck/` (ignored). The physical hub runs on authenticated loopback; startup at login is not enabled. Keep it running for these keys and avoid a second direct-Bluetooth owner for the lamp. Idle hub sessions release after 30 seconds; stop using the keys before switching to phone-direct BLE. This installation is a development link, so keep the checkout path stable. The standalone installer is in `outputs/ks-light-streamdeck-0.6.1/` outside the repository.

## Action keys
The Windows plugin provides **KS Light > Run light action**, a property inspector and per-key completion feedback. It uses the shared Python controller from CONTROLLER_ACTIONS.md, so it does not open a second Bluetooth connection. Configure separate keys for explicit On, Off, static colors or native effects.

Keys show the action name, Sending, then Sent or Simulated. Failures show Failed and the Stream Deck alert. Sent means a completed hub operation, not physical readback. Simulated explicitly identifies no physical delivery. Version 0.5.0 offers optional last-sent status through the hub; this is not physical lamp readback. Repeated presses on a busy key are ignored; separate keys still use the hub's bounded queue. Settings changes and disappearance/reappearance prevent stale completion from overwriting the new key display. Delivery is never automatically retried.

## Install and configure
Requires Windows 10+, Stream Deck 7.1+, the KS Light checkout with its Python virtual environment, and a running configured hub. The plugin bundles its JavaScript dependencies; Node does not need installing separately for normal Stream Deck operation. It is a local development build, not a Marketplace release.

1. Install `dev.kslight.controller.streamDeckPlugin` by opening it in Stream Deck.
2. Drag **KS Light > Run light action** onto a key.
3. Enter absolute paths for the checkout's Python executable, repository folder and controller JSON, plus the named action, then select **Save key**.
4. Press the key. Test with the simulator first; expect Simulated.

The inspector stores only these paths and the action name. Credentials remain in the separately protected token file referenced by the controller configuration. Process arguments are passed without a command shell; child stderr is drained without exposing its contents in Stream Deck. The client has a bounded timeout, and the plugin stops waiting after 125 seconds. Timeout/cancellation cannot retract a command already accepted by the hub.

Action and brightness dials plus shared connection setup are implemented; see the versioned sections below. Multi-actions are not advertised. Credentials remain in the protected controller token file. Hardware setup added only the separate KS Light profile. Existing personal profiles, keyboard bindings, startup tasks and firewall rules were preserved.

## Build and verify
From `apps/streamdeck`:
```powershell
npm ci
npm test
npm run build
npm run validate
npm run pack -- --force
```
Node 20.20.0 was used locally; exact npm dependencies and lockfile are checked into source. The manifest requests Stream Deck's Node 20 runtime. From the repository root, run the end-to-end smoke test after building:
```powershell
$env:PYTHONPATH=(Get-Location).Path
.venv/Scripts/python.exe apps/streamdeck/test/smoke.py
```

Validation: eight Node tests passed, Elgato CLI manifest validation and packaging passed, and a simulated Stream Deck WebSocket host successfully launched the actual bundled backend, registered the SDK, issued a key event, ran the real Python controller against the simulated hub and received showOk. An invalid action produced showAlert with no additional write. The smoke test uses no physical BLE. Real Stream Deck installation, property inspector appearance and physical button/lamp response remain deferred. Android APK unchanged.

References: [Elgato manifest](https://docs.elgato.com/streamdeck/sdk/references/manifest/), [key feedback](https://docs.elgato.com/streamdeck/sdk/guides/keys/).


## Shared connection setup (0.2.0, 2026-09-26)

Keys can now opt into one shared Python executable, repository path and controller configuration path. In the property inspector, enable **Use shared connection for this key**, enter the three paths, choose **Save shared connection**, then choose the action name and **Save key**. Shared connection edits affect all opted-in keys; action names remain per key. Token contents remain in the existing separate token file, not plugin settings.

Existing keys remain local unless explicitly opted in. Switching back restores retained per-key paths, which can be edited before saving. Missing or invalid shared setup does not fall back to old local paths or send a command. A shared update refreshes opted-in keys only and invalidates stale completion feedback from an earlier configuration; commands already submitted cannot be cancelled by changing settings. Each new press snapshots the effective connection. Disappeared keys are removed from the refresh registry.

Validation: 14 Node tests pass, including legacy opt-in behavior, shared path resolution, stale feedback, property-inspector save order, unsaved edits, Windows path validation and disconnected saves. The bundled SDK-to-Python-to-hub simulator smoke passed legacy and shared delivery, invalidated shared settings without a write, and recovery using per-key settings. Build and official manifest validation pass. Real Stream Deck installation, visual settings layout and physical key acceptance remain deferred while the desktop is in use. Dials and continuous last-sent status remain planned.

Run the end-to-end check from the repository root with `python -m apps.streamdeck.test.smoke`.


## Dials (0.3.0, 2026-09-26)

Two Stream Deck+ actions are available:

- **Choose light action:** enter 1..32 unique, comma-separated controller action names. Turn to preview choices, press the dial to run the selected action. Rotation alone never sends. Selection wraps in either direction and resets to the first action when the action appears or settings change.
- **Choose brightness:** choose a named color action with explicit power=true and RGB, or a native-effect action. Turn in 5-point steps to preview 1..100%, then press to apply that configured color/effect at the chosen level. Preview starts at 50% on appearance/settings changes. It is not current lamp brightness. Pressing reapplies the named preset, including its color/effect; it does not adjust an unknown external state. The controller configuration file is never edited.

Both support shared connection setup. Busy rotations and repeated presses are discarded. Failed/uncertain delivery is not retried. Changing setup or hiding the dial suppresses completion feedback from the old view. The touch strip reports Sent, Simulated or failure; it does not claim physical readback. Touch taps do not send commands in this version.

Validation: 21 Node tests pass; official manifest validation and packaging pass. The bundled SDK-to-client-to-hub simulator smoke exercised both dial types, preview without writes, success/failure feedback, and brightness delivery at 55% while the stored action remained 20%. A Windows CI workflow now repeats these checks; remote CI execution is not claimed. Physical Stream Deck+ layout, touch-strip readability and hardware acceptance remain deferred. Continuously refreshed hub state remains planned.

The implementation uses Elgato's [dial events and touch-strip feedback](https://docs.elgato.com/streamdeck/sdk/guides/dials/) with the built-in A1 layout.

## Continuous dimming (0.4.0)

Enable Apply brightness while turning on a brightness dial. It combines turns over 200 ms and retains only the latest absolute level while a command is in flight. There is no command backlog. Failed or uncertain delivery clears pending work and pauses automatic sending; inspect the hub, then deliberately press to send and resume. Hiding or reconfiguring a dial cancels pending work. Default preview/press behavior remains unchanged. The level starts at 50% and applies the configured action, not an unknown lamp state. 25 Node tests, manifest validation and packaging pass; physical dial testing remains pending.

## Live last-sent display (unreleased source)

On a Run light action key, enable **Show hub's last-sent state** and save. The key displays the target's last reported power, color/effect and brightness. Group and scene actions summarize their members: matching labels are shown directly; differing labels show Mixed. This does not claim that a scene is active. Unknown, unavailable, hub offline, simulated (Sim), restored from disk (Saved) and last sent (Sent) remain distinct.

Visible opted-in keys with identical Python/repository/config paths share one read-only Python process and HTTP session. The reader uses hub event long polling, refreshes at most once per second during bursts, reloads changed connection/token/CA files, and backs off on errors. No polling process runs for unselected keys; the last disappearing key releases its reader. A silent/crashed reader reports offline and may restart; only GET requests are repeated. Light commands are never replayed by status recovery. Sending feedback takes priority over status updates, and changed/disappeared keys reject stale feedback. Dials keep their preview/delivery feedback.

Validation: 21 focused Node checks covering the runner, inspector and shared status reader passed; two Python status checks include a simulator command made outside the reader and verify the reader submits no commands. The plugin bundle builds. The 0.5.0 installer was subsequently packaged and checked; desktop/physical acceptance remains deferred.
