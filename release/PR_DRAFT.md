# Proposed title

Add Android lighting app, optional hub integrations and release documentation

# Proposed body

KS Light expands from a Bluetooth CLI into an Android-first controller with saved devices/defaults, color presets, calibration, rooms/scenes, effects, shortcuts and appearance themes. An optional authenticated hub connects Home Assistant, Stream Deck and keyboard actions without multiple clients competing for the lamp's Bluetooth connection.

The README now describes the implemented app and includes app-rendered demo screenshots. Raspberry Pi GPIO and classic ESP32 controller examples are explicitly experimental. Distribution is APK sideloading through GitHub; Google Play/AAB and iOS are outside this release.

The launcher uses a KS Light bulb icon with legacy, adaptive and themed variants. The README has no em dashes and includes six screenshots of app widgets with demo data.

Validation includes targeted Android checks and phone review, completed user app acceptance, physical Stream Deck power/color/effect acceptance including improved delivery speed and color response, previous hub/CLI simulator/build evidence, and 24 GPIO/ESP32 host sanity checks. Physical Pi/ESP32, multiple-light and Stream Deck+ dial coverage remain deferred. Hosted workflows must pass on this PR before merge; local results do not substitute for that run.

Public APK signing and the release itself remain separate gates. No private configuration, signing key, configured firmware or personal phone screenshot belongs in this PR.
