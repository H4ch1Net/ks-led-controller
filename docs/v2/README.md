# KS Light 2.0 planning pack
Date: 2026-09-21
Status: approved direction from conversation; detailed contracts are draft until implemented and tested.

Start with PRODUCT.md, then ARCHITECTURE.md and ROADMAP.md.
These documents are maintained in docs/v2 in the working repository. This exported pack is a snapshot.

- PRODUCT.md: scope, user experience, feature priorities, deferred work.
- ARCHITECTURE.md: runtime boundaries, ownership, persistence, platform decisions.
- API.md: proposed local API and event semantics.
- INTEGRATIONS.md: Home Assistant, MQTT, Stream Deck, keyboards, DIY hardware.
- PROTOCOL_AND_TESTING.md: evidence policy, compatibility, automated and physical tests.
- ROADMAP.md: ordered deliverables, acceptance gates and outstanding inputs.
- DEVELOPMENT.md: checkout handoff, verified environment, test commands and next work.
- CLI_GUIDE.md: implemented commands, remembered settings and limitations.
- QUEUE_AND_SIMULATOR.md: scheduler semantics, simulator, dependency baseline and CI.
- ANDROID.md: mobile prototype, toolchain and physical-phone acceptance.

Source baseline: H4ch1Net/ks-led-controller commit 458eccb686f07ef937f1e073007f6d4c6b138258.
No hardware compatibility is newly certified by these documents.

- PHONE_TEST.md: physical phone test evidence and remaining acceptance.

- [Android rooms, groups and scenes](ROOMS_AND_SCENES.md)

- [Android foreground effects](EFFECTS.md)

- [Current implementation and remaining work](CURRENT_STATUS.md)
- [Hub groups and scenes](HUB_LIBRARY.md)
