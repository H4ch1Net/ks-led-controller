# GitHub release plan

Prepared 2026-09-27. Scope: publish the Android-first KS Light project through GitHub. Google Play, AAB, iOS and Stream Deck Marketplace are excluded. This document is a plan; it does not create a remote branch, PR, tag, signing key or release.

## Release shape

- Repository: `H4ch1Net/ks-led-controller`.
- Source branch: the existing local `ks-light-v2-foundation`; target: `main`.
- Proposed first public candidate tag: `v1.2.1-rc.1` (verify availability before creating). Keep it a prerelease while the remaining hardware checks are open.
- Android candidate: 1.2.1/build 5; Stream Deck package: 0.5.0.
- Android usability is accepted by the user. Raspberry Pi GPIO and ESP32 integrations are explicitly **Experimental** and do not block an Android prerelease.
- Local source history includes the foundation, redesign and preset/theme work. Release assets must name the exact final source commit and their own component versions.

## 1. Finish the source handoff

- [x] Rewrite README around Android, optional hub and implemented capabilities.
- [x] Include public-safe screenshots rendered from the real Flutter widgets with synthetic data.
- [x] Add explicit experimental labels and a bounded DIY sanity report.
- [ ] Recheck GitHub write access once an authenticated path is available. The last observed connector write returned HTTP 403; local Git had no authenticated login. Those are historical observations, not a fresh permissions test.
- [ ] Fetch remote refs, compare the default branch with the local base, and resolve any new conflicts without overwriting remote work.
- [ ] Push the existing branch, then open one draft source PR using [PR_DRAFT.md](../../release/PR_DRAFT.md). Do not push directly to main or force-push over someone else's work.

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

- [ ] Let checks run on the final PR commit. Investigate failures; do not repeatedly rerun already-passing suites for documentation changes.
- [ ] Treat disposable CI signing as assembly validation only. Those APKs must never become public update assets.
- [ ] Check the README image paths and captions on GitHub, plus the release links and Android instructions.
- [ ] Review and merge only after required checks pass. A future release workflow can be added when the permanent signing setup is decided; it is not needed to plan this release.

## 3. Decide and preserve the Android signing identity

Current private APKs use the existing development certificate so the user's installed app can update in place. Public releases need a deliberately owned permanent key.

- [ ] Generate the permanent key in a private location; store its password separately and keep two protected recovery copies. Record the certificate fingerprint in release documentation, never the private key/password.
- [ ] Choose a migration before publishing. A new unrelated certificate cannot update the current package in place. Preserve the user's development install; do not silently uninstall it or clear its data. Verify export/import coverage for settings that need migration before recommending a reinstall.
- [ ] Build the public candidate from the final reviewed commit with explicit signing. Confirm package ID, version/code, certificate fingerprint and absence of the debuggable flag.
- [ ] Test installation and a subsequent same-key upgrade on an appropriate device. Permanent signing is a public-release gate; private sideloading can continue with the current certificate.

Do not treat signing-key ownership as solved by putting a key in GitHub secrets. If automated signing is later chosen, use an explicitly approved release environment and keep untrusted PR jobs away from signing credentials.

## 4. Focused device acceptance

- [x] Android usability accepted for 1.2.1.
- [ ] Finish the short lamp/phone pass: preset apply, custom breathing, shortcuts and reconnect behavior. Fix failures only; prior successful paths need not be retested wholesale.
- [ ] Stream Deck: install the packaged 0.5.0 plugin when desktop interaction is available, create a new temporary test profile without altering existing profiles, configure the simulator first, then verify a deliberate lamp action. Use dials only if the attached model has them.
- [ ] Record physical Stream Deck results separately from its already-passing simulator/package checks. The user reports it plugged in; Windows sees an Elgato device and Stream Deck is running, but the KS Light plugin is not installed.
- [ ] Multiple lights, Pi/ESP32 boards and always-on deployments remain deferred hardware coverage; list that honestly rather than blocking the Android prerelease on unavailable equipment.

## 5. Assemble a draft GitHub prerelease

After the PR is merged and the signing/device gates are satisfied:

- [ ] Verify the proposed tag is unused; tag the exact reviewed source commit.
- [ ] Create a **draft prerelease** using [RELEASE_NOTES_DRAFT.md](../../release/RELEASE_NOTES_DRAFT.md).
- [ ] Attach the signed Android APK, Stream Deck 0.5.0 installer, reviewed source ZIP, SHA-256 checksums and a build receipt with source commit, versions, certificate fingerprint and verification results.
- [ ] Keep configured ESP32 firmware, Wi-Fi credentials, hub tokens, key files, SDK caches and personal phone captures out of assets. Ship experimental DIY source/examples only.
- [ ] Verify asset hashes after download and inspect the draft page. Publishing the reviewed draft is the final external step, not part of this planning request.

## Completion criteria

README and screenshots match the shipped app; release notes distinguish implemented, user-accepted and unverified hardware behavior; the APK has a stable signing identity; hosted checks pass on the released source; every asset is traceable to its build/source; no private data is included. A clear experimental label is sufficient for the optional DIY adapters until hardware is available.
