#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <esp_system.h>
#include <time.h>
#include "controller_core.h"
#include "status_feedback.h"
#include "rotary.h"
#include "dimmer.h"
#include <driver/gpio.h>
#if __has_include("ks_config.h")
#include "ks_config.h"
#else
#include "config.example.h"
#endif

// Defaults keep existing local configuration headers compatible.
#ifndef KS_LED_SENDING
#define KS_LED_SENDING -1
#endif
#ifndef KS_LED_COMPLETED
#define KS_LED_COMPLETED -1
#endif
#ifndef KS_LED_ERROR
#define KS_LED_ERROR -1
#endif
#ifndef KS_ROTARY_A
#define KS_ROTARY_A -1
#endif
#ifndef KS_ROTARY_B
#define KS_ROTARY_B -1
#endif
#ifndef KS_ROTARY_PRESS
#define KS_ROTARY_PRESS -1
#endif

#include "runtime_config.h"
RuntimeConfig connection{WIFI_SSID, WIFI_PASSWORD, HUB_ORIGIN, HUB_TOKEN, LIGHT_ID, HUB_CA, NTP_HOST};
bool storedConfigValid = true;
#ifndef KS_ROTARY_DIMMER
#define KS_ROTARY_DIMMER 0
#endif
#ifndef KS_ROTARY_DIM_ACTION
#define KS_ROTARY_DIM_ACTION 2
#endif
static_assert(KS_ROTARY_DIM_ACTION == 2 || KS_ROTARY_DIM_ACTION == 3, "Dimmer needs reading color (2) or native breathing (3)");
constexpr int ROTARY_PINS[] = {KS_ROTARY_A, KS_ROTARY_B, KS_ROTARY_PRESS};
constexpr bool ROTARY_ENABLED = KS_ROTARY_A != -1;
ks::Rotary rotary;
ks::Button rotaryPress(false, 0);
uint8_t selection = 0;
bool sending = false;
bool sendingDimmer = false;
ks::Dimmer dimmer;
constexpr int LED_PINS[] = {KS_LED_SENDING, KS_LED_COMPLETED, KS_LED_ERROR};
ks::Feedback feedback;
bool ledsReady = false;

bool setupIndicators() {
    // Validate every pin before configuring any output. Never reuse button pins.
    if (!ks::buttonPins(BUTTON_PINS) || !ks::indicatorPins(LED_PINS, BUTTON_PINS) ||
        !ks::indicatorPins(ROTARY_PINS, BUTTON_PINS) ||
        !ks::indicatorPins(ROTARY_PINS, LED_PINS)) return false;
    for (const int pin : ROTARY_PINS) if ((pin != -1) != ROTARY_ENABLED) return false;
    for (unsigned i = 0; i < 3; ++i) {
        const int pin = LED_PINS[i];
        if (pin == -1) continue;
        if (!GPIO_IS_VALID_OUTPUT_GPIO(pin)) return false;
        for (const int button : BUTTON_PINS) if (pin == button) return false;
        for (unsigned j = 0; j < i; ++j) if (pin == LED_PINS[j]) return false;
    }
    for (const int pin : LED_PINS) if (pin != -1) {
        digitalWrite(pin, LOW);
        pinMode(pin, OUTPUT);
    }
    return true;
}

void updateIndicators() {
    if (!ledsReady) return;
    const auto state = feedback.sample(millis());
    const ks::Indicator roles[] = {ks::Indicator::Sending, ks::Indicator::Completed, ks::Indicator::Error};
    for (unsigned i = 0; i < 3; ++i)
        if (LED_PINS[i] != -1) digitalWrite(LED_PINS[i], state == roles[i] ? HIGH : LOW);
}

struct Action { const char* name; const char* method; const char* suffix; const char* body; };
struct Command { uint8_t index; uint8_t brightness; }; // zero means use the action's own brightness
constexpr Action ACTIONS[] = {
    {"on", "PATCH", "/state", R"({"power":true})"},
    {"off", "PATCH", "/state", R"({"power":false})"},
    {"reading", "PATCH", "/state", R"({"power":true,"rgb":[255,190,120],"brightness":50})"},
    {"purple-breathing", "POST", "/effects/native", R"({"effect":137,"speed":35,"brightness":50})"}
};
static_assert(sizeof(BUTTON_PINS)/sizeof(BUTTON_PINS[0]) == 4, "Configure four button pins");
ks::Button buttons[] = {{false,0}, {false,0}, {false,0}, {false,0}};
QueueHandle_t mailbox;
QueueHandle_t results;
SemaphoreHandle_t available;
bool configured = false;

class HubTransport {
    const Action& action;
    String payload;
    ks::Response request(const char* method, const String& path, const char* body = nullptr) {
        ks::Response result;
        if (WiFi.status() != WL_CONNECTED || time(nullptr) < 1700000000) return result;
        WiFiClientSecure tls;
        tls.setCACert(connection.ca.c_str());
        tls.setHandshakeTimeout(3);
        HTTPClient http;
        http.setConnectTimeout(3000);
        http.setTimeout(3000);
        http.setReuse(false);
        http.useHTTP10(true); // Bounded Content-Length, no unbounded response allocation.
        http.setFollowRedirects(HTTPC_DISABLE_FOLLOW_REDIRECTS);
        if (!http.begin(tls, connection.origin + "/api/v1" + path)) return result;
        http.addHeader("Authorization", String("Bearer ") + connection.token);
        if (body) {
            http.addHeader("Content-Type", "application/json");
            char key[40];
            snprintf(key, sizeof(key), "%08lx%08lx%08lx%08lx", (unsigned long)esp_random(),
                (unsigned long)esp_random(), (unsigned long)esp_random(), (unsigned long)esp_random());
            http.addHeader("Idempotency-Key", key);
        }
        const int code = http.sendRequest(method, body ? String(body) : String());
        const int length = http.getSize();
        if (code != (body ? 202 : 200) || length <= 0 || length > 2048) { http.end(); return result; }
        char response[2049];
        auto& stream = http.getStream();
        stream.setTimeout(3000);
        const size_t count = stream.readBytes(response, length);
        http.end();
        if (count != size_t(length)) return result;
        response[count] = 0;
        StaticJsonDocument<3072> doc;
        if (deserializeJson(doc, response, count)) return result;
        if (!doc["operation_id"].is<const char*>() || !doc["status"].is<const char*>()) return result;
        result.ok = true;
        result.operation = doc["operation_id"].as<const char*>();
        result.status = doc["status"].as<const char*>();
        if (doc["confirmation"].is<const char*>()) result.confirmation = doc["confirmation"].as<const char*>();
        return result;
    }
public:
    explicit HubTransport(const Command& command) : action(ACTIONS[command.index]), payload(action.body) {
        if (command.brightness) {
            StaticJsonDocument<256> doc;
            deserializeJson(doc, action.body);
            doc["brightness"] = command.brightness;
            payload = "";
            serializeJson(doc, payload);
        }
    }
    uint32_t now() { return millis(); }
    void wait(uint32_t ms) { vTaskDelay(pdMS_TO_TICKS(ms)); }
    ks::Response submit() { return request(action.method, String("/lights/") + connection.light + action.suffix, payload.c_str()); }
    ks::Response poll(const std::string& id) { return request("GET", String("/operations/") + id.c_str()); }
};

void worker(void*) {
    Command command;
    for (;;) {
        if (xQueueReceive(mailbox, &command, portMAX_DELAY) != pdTRUE) continue;
        HubTransport transport(command);
        const auto result = ks::execute(transport);
        const char* status = result == ks::Outcome::Simulated ? "simulated" :
            result == ks::Outcome::Unconfirmed ? "sent; physical state unconfirmed" :
            result == ks::Outcome::Failed ? "failed; not retried" : "delivery unknown; not retried";
        Serial.printf("%s: %s\n", ACTIONS[command.index].name, status);
        xQueueSend(results, &result, portMAX_DELAY);
    }
}

bool validSetup() {
    return storedConfigValid && connection.valid();
}

void setupSerialCommand(const char* line) {
    DynamicJsonDocument doc(12288);
    if (deserializeJson(doc, line) || !doc["command"].is<const char*>()) {
        Serial.println("KS_SETUP invalid"); return;
    }
    const String command = doc["command"].as<const char*>();
    if (command == "status") {
        Serial.println(DRY_RUN ? "KS_SETUP dry-run" : !validSetup() ? "KS_SETUP unconfigured" :
            sending ? "KS_SETUP busy" : WiFi.status() == WL_CONNECTED ? "KS_SETUP connected" : "KS_SETUP offline");
        return;
    }
    if (sending) { Serial.println("KS_SETUP busy"); return; }
    if (command == "configure") {
        if (!saveRuntimeConfig(doc["settings"].as<JsonVariantConst>())) { Serial.println("KS_SETUP invalid-or-unsaved"); return; }
    } else if (command == "forget") {
        // Save a disabled record instead of revealing an older compiled-in connection.
        Preferences store;
        if (!store.begin("ks-light", false)) { Serial.println("KS_SETUP storage-failed"); return; }
        const bool saved = store.putString("config", "{}") == 2;
        store.end();
        if (!saved) { Serial.println("KS_SETUP storage-failed"); return; }
    } else { Serial.println("KS_SETUP invalid"); return; }
    Serial.println(command == "forget" ? "KS_SETUP forgotten" : "KS_SETUP saved");
    Serial.flush();
    ESP.restart();
}

void readSetupSerial() {
    static char line[8193];
    static size_t length = 0;
    static bool discard = false;
    static uint32_t started = 0;
    if (length && uint32_t(millis() - started) > 10000) {
        memset(line, 0, sizeof(line)); length = 0; discard = true;
        Serial.println("KS_SETUP expired");
    }
    // Bound work per loop so setup input cannot starve buttons/encoder sampling.
    for (unsigned i = 0; i < 64 && Serial.available(); ++i) {
        const char c = char(Serial.read());
        if (c == '\n') {
            if (discard) Serial.println("KS_SETUP invalid");
            else if (length) { line[length] = 0; setupSerialCommand(line); }
            memset(line, 0, sizeof(line)); length = 0; discard = false;
        } else if (c != '\r' && !discard) {
            if (length == 8192 || c == '\0') { discard = true; memset(line, 0, sizeof(line)); length = 0; }
            else { if (!length) started = millis(); line[length++] = c; }
        }
    }
}

void setup() {
    Serial.begin(115200);
    storedConfigValid = loadRuntimeConfig(connection);
    ledsReady = setupIndicators();
    if (!ledsReady) { Serial.println("Invalid or conflicting controller pins; controls disabled"); return; }
    for (unsigned i = 0; i < 4; ++i) {
        pinMode(BUTTON_PINS[i], INPUT_PULLUP);
        buttons[i] = ks::Button(digitalRead(BUTTON_PINS[i]) == LOW, millis());
    }
    if (ROTARY_ENABLED) {
        for (const int pin : ROTARY_PINS) pinMode(pin, INPUT_PULLUP);
        rotary = ks::Rotary((digitalRead(KS_ROTARY_A) << 1) | digitalRead(KS_ROTARY_B));
        rotaryPress = ks::Button(digitalRead(KS_ROTARY_PRESS) == LOW, millis());
        if (KS_ROTARY_DIMMER) Serial.println("Dimmer: 50% preview; turn to send, press to resume after errors");
        else Serial.printf("Selected: %s (press to send)\n", ACTIONS[selection].name);
    }
    if (DRY_RUN) { configured = true; Serial.println("Dry-run: buttons only; Wi-Fi and hub disabled"); return; }
    if (!validSetup()) { Serial.println("Configure credentials and trusted HTTPS first; controls disabled"); return; }
    mailbox = xQueueCreate(1, sizeof(Command));
    results = xQueueCreate(1, sizeof(ks::Outcome));
    available = xSemaphoreCreateBinary();
    if (!mailbox || !results || !available || xTaskCreate(worker, "ks-hub", 16384, nullptr, 1, nullptr) != pdPASS) {
        Serial.println("Worker unavailable; controls disabled"); return;
    }
    xSemaphoreGive(available);
    WiFi.persistent(false);
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.begin(connection.ssid.c_str(), connection.password.c_str());
    configTime(0, 0, connection.ntp.c_str());
    configured = true;
    Serial.println("Ready; waiting for Wi-Fi and clock. Presses are never replayed.");
}

void sendAction(uint8_t index, uint8_t brightness = 0) {
    if (sending) { Serial.println("Busy; press discarded"); return; }
    // An explicit button takes priority over pending automatic dimming.
    if (!brightness && KS_ROTARY_DIMMER) dimmer.cancel();
    if (DRY_RUN) {
        Serial.printf("%s: dry-run%s", ACTIONS[index].name, brightness ? " brightness=" : "\n");
        if (brightness) Serial.println(brightness);
        if (brightness) dimmer.complete(ks::Outcome::Simulated);
        feedback.finish(ks::Outcome::Simulated, millis());
        return;
    }
    if (WiFi.status() != WL_CONNECTED || time(nullptr) < 1700000000) {
        Serial.println("Offline or clock unavailable; press discarded");
        feedback.reject(millis());
        if (brightness) dimmer.cancel();
        return;
    }
    if (xSemaphoreTake(available, 0) != pdTRUE) { Serial.println("Busy; press discarded"); return; }
    sending = true;
    sendingDimmer = brightness != 0;
    feedback.start();
    const Command command{index, brightness};
    if (xQueueSend(mailbox, &command, 0) != pdTRUE) {
        sending = false;
        feedback.finish(ks::Outcome::Failed, millis());
        if (brightness) dimmer.cancel();
        xSemaphoreGive(available);
    }
}

void loop() {
    readSetupSerial();
    if (!configured) { delay(10); return; }
    // Consume rotary motion while busy before releasing the command gate.
    // A turn begun during a request cannot be replayed after its completion.
    if (ROTARY_ENABLED) {
        const int turn = rotary.sample((digitalRead(KS_ROTARY_A) << 1) | digitalRead(KS_ROTARY_B),
            !sending || (KS_ROTARY_DIMMER && sendingDimmer));
        if (turn) {
            if (KS_ROTARY_DIMMER) {
                dimmer.turn(turn, millis());
                Serial.printf("Brightness: %d%%%s\n", dimmer.value(), dimmer.isPaused() ? " (paused; press to send)" : "");
            } else {
                selection = uint8_t((int(selection) + turn + 4) % 4);
                Serial.printf("Selected: %s (press to send)\n", ACTIONS[selection].name);
            }
        }
        if (rotaryPress.sample(digitalRead(KS_ROTARY_PRESS) == LOW, millis()) && !sending) {
            if (KS_ROTARY_DIMMER) sendAction(KS_ROTARY_DIM_ACTION, dimmer.start());
            else sendAction(selection);
        }
    }
    for (uint8_t i = 0; i < 4; ++i)
        if (buttons[i].sample(digitalRead(BUTTON_PINS[i]) == LOW, millis())) sendAction(i);
    ks::Outcome result;
    if (results && xQueueReceive(results, &result, 0) == pdTRUE) {
        feedback.finish(result, millis());
        if (sendingDimmer) dimmer.complete(result);
        sending = false;
        sendingDimmer = false;
        xSemaphoreGive(available);
    }
    if (ROTARY_ENABLED && KS_ROTARY_DIMMER && !sending && dimmer.due(millis()))
        sendAction(KS_ROTARY_DIM_ACTION, dimmer.start());
    updateIndicators();
    delay(1); // Poll encoder contacts while worker performs HTTPS; fast turns may be missed.
}
