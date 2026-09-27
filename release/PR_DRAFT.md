# Proposed title

Add Android lighting app, optional hub integrations and release documentation

# Proposed body

KS Light expands from a Bluetooth CLI into an Android-first controller with saved devices/defaults, color presets, calibration, rooms/scenes, effects, shortcuts and appearance themes. An optional authenticated hub connects Home Assistant, Stream Deck and keyboard actions without multiple clients competing for the lamp's Bluetooth connection.

The README now describes the implemented app and includes app-rendered demo screenshots. Raspberry Pi GPIO and classic ESP32 controller examples are explicitly experimental. Distribution is APK sideloading through GitHub; Google Play/AAB and iOS are outside this release.

Validation includes targeted Android checks and phone visual review, user usability acceptance, previous hub/CLI/Stream Deck simulator/build evidence, and 24 fresh GPIO/ESP32 host sanity checks. Physical Pi/ESP32, multiple-light and full Stream Deck acceptance remain open. Hosted workflows must pass on this PR before merge; local results do not substitute for that run.

Public APK signing and the release itself remain separate gates. No private configuration, signing key, configured firmware or personal phone screenshot belongs in this PR.
