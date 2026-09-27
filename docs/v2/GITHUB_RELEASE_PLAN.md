# GitHub release plan

Prepared 2026-09-27. Scope: publish the Android-first KS Light project through GitHub. Google Play, AAB, iOS and Stream Deck Marketplace are excluded. Source delivery is in PR #1 and a draft prerelease exists. The source and Stream Deck assets are uploaded; public APK signing and publication remain pending.

## Release shape

- Repository: `H4ch1Net/ks-led-controller`.
- Source branch: the existing local `ks-light-v2-foundation`; target: `main`.
- Proposed first public candidate tag: `v1.2.1-rc.1` (verify availability before creating). Keep it a prerelease while the remaining hardware checks are open.
- Android source candidate: 1.2.1/build 6 (launcher artwork update after accepted build 5); Stream Deck package: 0.6.1.
- Android usability is accepted by the user. Raspberry Pi GPIO and ESP32 integrations are explicitly **Experimental** and do not block an Android prerelease.
- Local source history includes the foundation, redesign and preset/theme work. Release assets must name the exact final source commit and their own component versions.

## 1. Finish the source handoff

- [x] Rewrite README around Android, optional hub and implemented capabilities.
- [x] Include public-safe screenshots rendered from the real Flutter widgets with synthetic data.
- [x] Add explicit experimental labels and a bounded DIY sanity report.
- [x] Rechecked 2026-09-27: connector branch writes still return HTTP 403, but Git push authentication works with the existing H4ch1Net credential selected explicitly.
- [x] Fetched remote refs: local history contains the remote base with no divergent remote commits.
- [x] Pushed the existing branch and opened [draft PR #1](https://github.com/H4ch1Net/ks-led-controller/pull/1). Main and remote history were preserved.

The README's candidate notice must remain until a release exists. Remove the local-only branch warning after the source PR lands. Keep compatibility claims tied to physical evidence, and keep private addresses/configuration outside the PR.

## 2. Run the hosted checks once on the PR

Existing workflows already cover the required areas:

| Workflow | Purpose |
| --- | --- |
| `tests.yml` | Python/controller checks on Windows/Linux and Python 3.10/3.12; simulator |
| `android.yml` | Pinned toolchain, Flutter analysis/tests, native shortcut tests, debug and disposable-key release assembly |
| `streamdeck.yml` | Node checks, plugin build/validation, simulator smoke and installer packaging |
| `esp32.yml` | Portable C++ logic and all three firmware compile configurations |
| `source-package.yml` | Source inventory/package checks and equal Windows/Linux archive bytes |

- [x] All five workflows passed on `881d7366ee45b5b7b7579ffb476b3ad4a8e0cd7a`. The post-merge documentation cleanup changes no application/build code and does not repeat those suites.
- [ ] Treat disposable CI signing as assembly validation only. Those APKs must never become public update assets.
- [x] Verified the remote README and all seven image files against local bytes; visually reviewed the icon and six screenshots.
- [x] PR #1 merged after checks passed. Public APK signing and publication remain separate.

## 3. Decide and preserve the Android signing identity

Current private APKs use the existing development certificate so the user's installed app can update in place. Public releases need a deliberately owned permanent key.

- [ ] Generate the permanent key in a private location; store its password separately and keep two protected recovery copies. Record the certificate fingerprint in release documentation, never the private key/password.
- [ ] Choose a migration before publishing. A new unrelated certificate cannot update the current package in place. Preserve the user's development install; do not silently uninstall it or clear its data. Verify export/import coverage for settings that need migration before recommending a reinstall.
- [ ] Build the public candidate from the final reviewed commit with explicit signing. Confirm package ID, version/code, certificate fingerprint and absence of the debuggable flag.
- [ ] Test installation and a subsequent same-key upgrade on an appropriate device. Permanent signing is a public-release gate; private sideloading can continue with the current certificate.

Do not treat signing-key ownership as solved by putting a key in GitHub secrets. If automated signing is later chosen, use an explicitly approved release environment and keep untrusted PR jobs away from signing credentials.

## 4. Focused device acceptance

- [x] Android usability accepted for 1.2.1.
- [x] User confirmed app testing is all good on 2026-09-27. No broad repeat phone pass is required.
- [x] Stream Deck: install the development plugin in a separate KS Light profile; verify a physical simulator press followed by deliberate BLE lamp actions. The connected 15-key model has no dials. Version 0.6.1 adds typed controls, shared setup and color response; installer is packaged separately.
- [x] User accepted Stream Deck 0.6.1 Power/Color/Effect, repeat delivery speed and final compensated color. Details are in DEFERRED_HARDWARE_CHECKS.md.
- [ ] Multiple lights, Pi/ESP32 boards and always-on deployments remain deferred hardware coverage; list that honestly rather than blocking the Android prerelease on unavailable equipment.

## 5. Assemble a draft GitHub prerelease

A draft with source and Stream Deck assets is prepared before publication. Update it to the reviewed source commit after the PR is merged; add the public APK only after signing gates are satisfied.

- [ ] Verify the proposed tag is unused; tag the exact reviewed source commit.
- [x] Created draft prerelease `v1.2.1-rc.1`; it is not published. Source ZIP, Stream Deck 0.6.1, checksums and a receipt are uploaded and downloaded hashes were verified.
- [ ] Attach the signed Android APK, Stream Deck 0.6.1 installer, reviewed source ZIP, SHA-256 checksums and a build receipt with source commit, versions, certificate fingerprint and verification results.
- [ ] Keep configured ESP32 firmware, Wi-Fi credentials, hub tokens, key files, SDK caches and personal phone captures out of assets. Ship experimental DIY source/examples only.
- [ ] Verify asset hashes after download and inspect the draft page. Publishing the reviewed draft is the final external step, not part of this planning request.

## Completion criteria

README and screenshots match the shipped app; release notes distinguish implemented, user-accepted and unverified hardware behavior; the APK has a stable signing identity; hosted checks pass on the released source; every asset is traceable to its build/source; no private data is included. A clear experimental label is sufficient for the optional DIY adapters until hardware is available.
