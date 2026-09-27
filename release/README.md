# Source packaging and build pins

`source-files.json` is the explicit reviewed source inventory. New or removed Git-visible files require updating this list; the packager fails instead of silently omitting new code. The inventory includes itself. Review additions before updating it, especially JSON configuration. Private credentials, signing keys, local SDK paths, dependency caches and generated application builds do not belong in the list.

From the repository root:

```sh
python -m ks_light.build_toolchain
python -m ks_light.source_package --check-inventory
python -m ks_light.source_package --output dist/ks-light-source-candidate.zip
python -m ks_light.source_package --verify dist/ks-light-source-candidate.zip
```

These commands use only Python's standard library; creating from a checkout also checks its Git-visible inventory. The exported source can be packaged again without Git using its included inventory. Choose a new output name if one already exists. A successful export creates a ZIP plus a `.sha256` companion. Verification reads the archive without extracting or executing it. Compare the companion hash from your trusted copy when checking a transferred archive: the embedded manifest alone does not authenticate its publisher.

ZIP entries have fixed ordering, timestamps and permissions. Text uses UTF-8 with LF, Windows batch launchers use CRLF, and PNG/JAR files retain exact bytes. Stored ZIP entries avoid compressor-version differences. `SOURCE_MANIFEST.json` contains the normalized byte size and SHA-256 of every included file plus an identity for that inventory. The Gradle shell launcher has executable permissions in the archive. Metadata such as local usernames, current timestamps and Git status does not enter the generated manifest.

To review/update the inventory, compare `git ls-files --cached --others --exclude-standard` with the JSON list and add only intended public source files. Generated archives belong in ignored `dist/` or an external output directory. A list edit cannot bypass the private-path, size and linked-file checks. Files added through the normal Git working tree cannot be silently dropped from the archive.

Source reproducibility is separate from application build reproducibility. This ZIP contains no current APK, Stream Deck installer, configured ESP32 binary or release signing key. Rebuild those candidates from a chosen source identity using `docs/v2/RELEASE_CHECKLIST.md`, record their hashes and validation, and complete hardware/signing gates before distribution.

`android-toolchain.json` records the reviewed Gradle wrapper/distribution hashes and official-repository provenance for platform-specific dependency artifacts. `python -m ks_light.build_toolchain` checks these local pins before Gradle executes. Gradle's own verification metadata covers the resolved plugin/library artifacts. Review both files when intentionally changing toolchain versions.
