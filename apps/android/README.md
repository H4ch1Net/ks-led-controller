# KS Light Android prototype

See ../../docs/v2/ANDROID.md for toolchain versions, supported prototype flows and remaining hardware acceptance.

Run flutter analyze and flutter test from this directory. Tests read the shared repository fixtures, so keep the repository layout intact.

Build with flutter build apk --debug. Starts in demo mode. Disabling demo and scanning requests Bluetooth permissions. No light changes until an explicit power or Apply action.

This is a debug prototype, not a store release. Branding and release signing remain unconfigured.
