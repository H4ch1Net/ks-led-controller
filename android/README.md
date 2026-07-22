# 📱 KS LED — Android App

A native Android app for controlling KS Bluetooth LED lights, built with **Kotlin**
and **Jetpack Compose**. It speaks the exact same reverse-engineered BLE protocol as
the Python tools in the parent repo, so it works with the same devices.

<div align="center">

**Scan → Connect → Colour wheel · Presets · Effects · Brightness**

</div>

---

## ✨ Features

| | |
|---|---|
| 🔍 **Auto-discovery** | Scans for and lists nearby KS lights (KS01–KS15 families) with signal strength |
| 🎨 **Colour wheel** | Interactive HSV wheel — drag to pick hue + saturation |
| 🎚️ **Sliders** | Independent hue, saturation and brightness sliders |
| 💾 **Presets** | 12 built-in presets; save your own, long-press to delete (persisted on device) |
| ✨ **Effects** | Rainbow, Breathe, Strobe, Colour Flash, Fire, Candle, Ocean — with a speed control |
| 🔦 **Power & brightness** | One-tap on/off; brightness applies live, even during animations |
| 🏷️ **Nicknames** | Rename each light; names persist per device address |
| 🔒 **Offline & private** | No accounts, no cloud, no analytics — everything is local BLE |

---

## 🧱 Requirements

- **Android 7.0 (API 24)** or newer
- A device with **Bluetooth Low Energy**
- **Android Studio** (Ladybug / 2024.2+ recommended) with the Android SDK

## 🚀 Build & Run

### Android Studio (easiest)

1. Open the `android/` folder as a project in Android Studio.
2. Let Gradle sync (it will create `local.properties` pointing at your SDK).
3. Plug in a phone with USB debugging enabled and press **Run** ▶.

### Command line

```bash
cd android

# Tell Gradle where your Android SDK lives (or set ANDROID_HOME)
echo "sdk.dir=/path/to/Android/Sdk" > local.properties

# Build a debug APK
./gradlew assembleDebug

# Install onto a connected device
./gradlew installDebug
```

The APK lands in `app/build/outputs/apk/debug/app-debug.apk`.

---

## 📡 How it works

The app is a thin, well-structured wrapper around the same commands documented in the
root [`README.md`](../README.md):

| Action | Command (hex) |
|--------|---------------|
| ON / OFF | `5BF001B5` / `5B0F01B5` |
| Colour — floor lamps (5A) | `5A0001 RRGGBB 00 BB 00A5` (`BB` = brightness) |
| Colour — strip/ceiling (7E) | `7E070503 RRGGBB 00EF` (brightness folded into RGB) |
| Brightness (white, 5A lamps) | `5A000200000000 BB 00A5` |

Device name prefixes are mapped to their GATT service / write-characteristic UUIDs in
[`KsModels.kt`](app/src/main/java/com/ksled/controller/ble/KsModels.kt).

> **Effects note:** KS firmware exposes no native animation commands, so effects are
> generated on the phone by streaming colour frames over BLE. Keep the light within
> good BLE range for the smoothest results.

## 🗂️ Project layout

```
app/src/main/java/com/ksled/controller/
├── MainActivity.kt              # Compose entry point + permission gate
├── ble/
│   ├── KsProtocol.kt            # Command byte builders
│   ├── KsModels.kt              # Device prefix → UUID / style registry
│   └── KsBleManager.kt          # Scanning, GATT connection, serialised write queue
├── data/
│   ├── Models.kt                # Preset model + defaults
│   └── AppRepository.kt         # DataStore persistence (presets, nicknames)
├── vm/
│   ├── ControllerViewModel.kt   # UI state + animation engine
│   └── Animations.kt            # Effect definitions
└── ui/
    ├── KsApp.kt                 # Scan screen + navigation
    ├── ControlScreen.kt         # Colour / Presets / Effects tabs
    ├── ColorWheel.kt            # Custom HSV wheel canvas
    ├── PermissionsGate.kt       # Runtime BLE permission handling
    └── theme/Theme.kt           # Material 3 dark theme
```

## 🔐 Permissions

- **Android 12+:** `BLUETOOTH_SCAN` (with `neverForLocation`) and `BLUETOOTH_CONNECT`.
- **Android 11 and below:** `ACCESS_FINE_LOCATION` (required by the OS for BLE scans).

No location data is ever collected or used — the flag is declared purely to satisfy the
scan API on older releases.

---

*Not affiliated with KeepSmile or KS Smart Light. Reverse-engineered for personal use.*
