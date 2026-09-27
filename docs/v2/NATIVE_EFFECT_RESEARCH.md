# KS03 transport and effect architecture findings

## Evidence
2026-09-21: inspected the original application installed on the connected phone: com.huaxin.smartlight, version 1.7, versionCode 9. Base APK SHA-256: aecb4df7a47d6c966892843a11e8077b4e6f36f2a5dc9441ed8e4f19babcbe8c.
APK and decompiled sources remain in work/research/kslight outside the source repository and deliverables. JADX 1.5.6 reported 84 decompilation errors overall; findings below come from readable command builders and their call sites, not an assumption that all code was recovered correctly.

## Current prototype limitations
Effects calculate quantized RGB samples on the phone at a target 150 ms interval, apply channel calibration, and write discrete static-color commands. Persistent BLE connections reduce connection overhead but do not create device-side interpolation. Breathing scales and rounds RGB channels independently while leaving packet brightness at full scale. At low levels this can alter channel ratios; it is a plausible contributor to the reported hue shift, not a measured diagnosis of the physical lamp. LED driver behavior and channel response can also contribute.

## Original application evidence (not hardware verified)
- UUIDBeanList maps KS03~ to AFD0 / AFD1 / AFD2 / AFD3. Notification/read roles must be traced before implementation.
- CmdBase.getModle builds a device effect command: 5C 00 (position+128) speed brightness 00 C5. DeviceCmd.scene and CmdAll.SendScene send that selection on user changes rather than streaming animation frames. SceneFragment references 23 effect labels (c128 through c150). Labels, range mapping and per-model dispatch still require validation before presenting choices.
- FloorBean.getSendCmd preserves RGB channels and supplies a separate brightness value in the known 5A static color packet. Confirm brightness units from resources and hardware; existing inherited byte range 0..255 must not be assumed to match the original UI scale.
- CmdBase.getState contains 5F0100F5. CmdFloor.getFloorBean parses dynamic/static mode, RGB/white, RGB channels, white, brightness, speed, effect selection and top/bottom power. This is evidence for a state query/readback path, not proof our lamp returns it.
- A speed field in a static-color builder is NOT proof that arbitrary RGB transitions support a fade duration.

## Implementation direction
1. Trace the KS03~ dispatch, effect labels/ranges, notification setup, reply framing and stop behavior. Add independent protocol fixtures and malformed-reply validation.
2. Validate one understood gradual native effect and stopping/restoration on the real light. Native effects may continue when the app disconnects; expose that lifecycle explicitly instead of inheriting foreground-streaming behavior.
3. Offer verified native effects first. Send effect/speed/brightness only on setting changes. Native presets may not support custom palettes or per-channel calibration; communicate those capabilities honestly.
4. Separate chromatic color from overall brightness for static color and software dimming. Verify brightness scale before altering user settings or calibration. Use perceptual color interpolation where useful for custom palette transitions; do not promise it fixes unknown LED response.
5. Add state readback with requested, sent and device-reported states distinguished. A device-reported value still is not an optical color measurement.
6. Keep bounded, latest-value software streaming for custom effects the device cannot perform. Measure write latency/jitter before selecting a higher rate. More packets alone cannot guarantee smooth output.

No native effect, query or newly inferred command was transmitted during this investigation. No APK update was made for these findings.


## Implemented and tested follow-up
- Original XML confirms the floor/scene slider maximum is 100. Android UI/storage stays normalized to 0..255 for compatibility; KS03~ commands now convert to 0..100 at the transport encoding boundary. Raw packet fixtures remain byte encoders, and other prefixes are unchanged.
- KS03~ single-light Effects opens On-light effects first. Nine gradual native choices are offered (0x82..0x8a); jumping/strobe modes are excluded. Apply sends power-on plus one effect command; there is no animation frame loop or automatic status polling. Subsequent settings use the open connection. Off sends the existing top-light power-off command.
- Purple breathing 0x89, speed 35, brightness 50 was sent on the user's real the test KS03 lamp. User explicitly confirmed: "It animates and is smoother". Other listed modes have APK command evidence but individual visual acceptance remains open.
- Native effects continue while the app is closed/disconnected. The page says this explicitly, offers Stop and turn off, and offers Custom effects from phone. Calibration does not modify built-in palettes. Native operations invalidate the parent's remembered power/color status rather than misrepresenting a dynamic effect as a static color.
- Software breathing on KS03~ now keeps RGB constant and varies brightness independently. This eliminates per-frame channel-ratio rounding from the breathing envelope. Hardware hue consistency remains user acceptance work.
- AFD2 is notification and AFD3 is read. State request 5F0100F5 yielded no recognized state notification; AFD3 returned the identification string ELKSHYY60HR44V22 (zero padded). Readback remains unsupported/unverified on this firmware, not a confirmed state source. Optional Read light state reports this clearly and does not block normal Apply/Off operations. No guessed state frames are accepted.
- State-query notification streams are recreated for each query, fixing a discovered single-subscription reuse failure. Query/read waits are bounded; unrelated replies are ignored and malformed state packets rejected.
- 58 Android tests pass across the suite and focused reruns, including new native packet, brightness, hue preservation, query cleanup/reuse, single-send UI and disconnect checks. Flutter analysis is clean; debug APK builds. Native Off and repeated query actions exercised on phone with no app crash. Optical Off/static replacement acceptance is separate from successful BLE writes.
