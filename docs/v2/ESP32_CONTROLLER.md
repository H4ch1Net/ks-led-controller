# ESP32/Arduino controller

Implemented 2026-09-26 in `apps/esp32`. A classic ESP32 DevKit uses four momentary GPIO buttons for On, Off, reading color and Purple breathing. It connects to the existing hub over authenticated, certificate-verified HTTPS. BLE remains owned by the hub.

Start with `apps/esp32/README.md` in the source bundle for wiring, configuration and PlatformIO build instructions. The default firmware is a no-network dry-run. A separate build variant checks network linking with placeholder credentials; no board was flashed.

Inputs continue sampling during requests. Stable-edge debounce prevents switch bounce and held-button repeats, including buttons held at startup. Busy/offline presses are discarded. Each action submits once, checks the matching operation and distinguishes simulator success, unconfirmed transport completion, failure and unknown delivery. No command retries or reconnect replay occur. A 20-second polling budget and individual network timeouts are not a strict wall-clock deadline for an in-flight request.

Portable C++ host tests pass for debounce, held startup, timer rollover, outcomes, bad/mismatched operation IDs and no retries. A Python contract test passed all four actual firmware payloads through the authenticated simulator hub and verified bounded Content-Length HTTP/1.0 responses. These are not physical ESP32 network/TLS tests. The CI workflow repeats host tests and firmware compilation; remote CI has not been run here.

Pending acceptance: board wiring, TLS and trusted CA setup, Wi-Fi reconnect, NTP/clock failure, busy presses during slow delivery, physical lamp results and resource use under repeated operations. Optional Sending, Completed and Error LEDs are implemented, with pin validation and nonblocking two-second result feedback. Their physical wiring and operation remain pending. Optional full-cycle rotary action selection with press-to-send is implemented. Runtime pairing/configuration and continuous dimming remain future work. Configured binaries contain credentials; only source and the unconfigured example should be shared.

Build validation: both PlatformIO environments compiled successfully locally. The network variant uses 927,317 bytes of flash (70.7%) and 46,988 bytes of static RAM (14.3%); those linker totals do not establish runtime heap/stack stability. The dry-run build also passes.

LED checks: portable tests cover disabled outputs, invalid/duplicate/button-conflicting pins, sending protection during rejected presses, terminal outcomes and timeout across timer rollover. Both firmware variants compile; the network variant enables all three LEDs. Completion feedback includes dry-run/simulation and does not prove physical state.

Rotary host checks pass for direction, reversible bounce, invalid transitions, partial startup and busy-boundary discard. Firmware samples with a 1 ms loop delay; real encoder detent direction, bounce, fast turns and press behavior remain pending. All configured pins are checked for button/LED/encoder conflicts before GPIO setup.
