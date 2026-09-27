#pragma once
// Copy to ks_config.h locally. Never distribute a configured firmware image.
#ifndef KS_DRY_RUN
#define KS_DRY_RUN 1
#endif
constexpr bool DRY_RUN = KS_DRY_RUN;
constexpr char WIFI_SSID[] = "CHANGE_ME";
constexpr char WIFI_PASSWORD[] = "CHANGE_ME";
constexpr char HUB_ORIGIN[] = "https://hub.example.invalid"; // No path or trailing slash.
constexpr char HUB_TOKEN[] = "CHANGE_ME";
constexpr char LIGHT_ID[] = "desk";
constexpr char NTP_HOST[] = "pool.ntp.org";
constexpr char HUB_CA[] = R"PEM(-----BEGIN CERTIFICATE-----
REPLACE_WITH_YOUR_TRUSTED_CA_CERTIFICATE
-----END CERTIFICATE-----
)PEM";
// Classic ESP32 DevKit: normally-open buttons to GND. Check your board pinout.
constexpr int BUTTON_PINS[] = {18, 19, 21, 22};

// Optional active-high external LEDs, each with its own current-limiting resistor.
// -1 disables an output. Example GPIOs: sending 23, completed 25, error 26.
// Check board availability; never share button pins or reserved board connections.
#ifndef KS_LED_SENDING
#define KS_LED_SENDING -1
#endif
#ifndef KS_LED_COMPLETED
#define KS_LED_COMPLETED -1
#endif
#ifndef KS_LED_ERROR
#define KS_LED_ERROR -1
#endif

// Optional full-cycle rotary selector (A, B and press to GND; internal pull-ups).
// Enable all three together, for example GPIO 32, 33, 27. -1 disables the selector.
#ifndef KS_ROTARY_A
#define KS_ROTARY_A -1
#endif
#ifndef KS_ROTARY_B
#define KS_ROTARY_B -1
#endif
#ifndef KS_ROTARY_PRESS
#define KS_ROTARY_PRESS -1
#endif

// Optional continuous brightness instead of action selection. Start at 50%,
// 5% per detent; press explicitly resumes after a failure or a button action.
#ifndef KS_ROTARY_DIMMER
#define KS_ROTARY_DIMMER 0
#endif
// 2 = reading color, 3 = Purple breathing. Power-only actions cannot be dimmed.
#ifndef KS_ROTARY_DIM_ACTION
#define KS_ROTARY_DIM_ACTION 2
#endif
