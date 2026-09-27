#pragma once
#include <Preferences.h>
#include <ArduinoJson.h>
#include "controller_core.h"

// One bounded NVS record. Configuration is immutable until an explicit reboot.
struct RuntimeConfig {
    String ssid, password, origin, token, light, ca, ntp;
    bool read(JsonVariantConst value) {
        if (!value.is<JsonObjectConst>()) return false;
        const auto object = value.as<JsonObjectConst>();
        const char* fields[] = {"wifi_ssid", "wifi_password", "hub_origin", "hub_token", "light_id", "hub_ca", "ntp_host"};
        if (object.size() != 7) return false;
        for (const auto field : fields) if (!object[field].is<const char*>()) return false;
        ssid = object["wifi_ssid"].as<const char*>(); password = object["wifi_password"].as<const char*>();
        origin = object["hub_origin"].as<const char*>(); token = object["hub_token"].as<const char*>();
        light = object["light_id"].as<const char*>(); ca = object["hub_ca"].as<const char*>(); ntp = object["ntp_host"].as<const char*>();
        // Do not accept embedded NULs that would silently truncate a field.
        for (const auto field : fields)
            if (object[field].as<JsonString>().size() != strlen(object[field].as<const char*>())) return false;
        return valid();
    }
    bool valid() const {
        if (ssid.isEmpty() || ssid.length() > 32 || password.length() > 63 || ssid == "CHANGE_ME" ||
            token.length() < 32 || token.length() > 512 || !ks::identifier(light.c_str(), 64) ||
            !origin.startsWith("https://") || origin.length() <= 8 || origin.length() > 256 ||
            origin.indexOf('/', 8) >= 0 || origin.indexOf('@') >= 0 || origin.indexOf('?') >= 0 || origin.indexOf('#') >= 0 ||
            ca.length() > 4096 || !ca.startsWith("-----BEGIN CERTIFICATE-----") || ca.indexOf("-----END CERTIFICATE-----") < 0 ||
            ca.indexOf("REPLACE_") >= 0 || ntp.isEmpty() || ntp.length() > 253) return false;
        for (const String* text : {&token, &origin, &ntp})
            for (unsigned i = 0; i < text->length(); ++i) if ((*text)[i] <= ' ' || (*text)[i] >= 127) return false;
        return true;
    }
};

// Returns false for corrupt/unreadable stored data; never silently uses an old compiled target.
inline bool loadRuntimeConfig(RuntimeConfig& config) {
    Preferences store;
    // Opening read/write creates the namespace on the first boot.
    if (!store.begin("ks-light", false)) return false;
    if (!store.isKey("config")) { store.end(); return true; }
    const String raw = store.getString("config", "");
    store.end();
    if (raw.isEmpty() || raw.length() > 8192) return false;
    DynamicJsonDocument doc(12288);
    return !deserializeJson(doc, raw) && config.read(doc.as<JsonVariantConst>());
}

inline bool saveRuntimeConfig(JsonVariantConst value) {
    RuntimeConfig candidate;
    if (!candidate.read(value)) return false;
    String raw;
    if (serializeJson(value, raw) == 0 || raw.length() > 8192) return false;
    Preferences store;
    if (!store.begin("ks-light", false)) return false;
    const bool saved = store.putString("config", raw) == raw.length();
    store.end();
    return saved;
}
