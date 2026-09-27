#pragma once
#include "controller_core.h"

namespace ks {
// Conservative external-output set for this classic DevKit example.
inline bool indicatorPin(int pin) {
    return pin == -1 || pin == 18 || pin == 19 || pin == 21 || pin == 22 ||
        pin == 23 || pin == 25 || pin == 26 || pin == 27 || pin == 32 || pin == 33;
}
template<size_t N>
bool buttonPins(const int (&pins)[N]) {
    for (size_t i = 0; i < N; ++i) {
        if (pins[i] == -1 || !indicatorPin(pins[i])) return false;
        for (size_t j = 0; j < i; ++j) if (pins[i] == pins[j]) return false;
    }
    return true;
}
template<size_t N>
bool indicatorPins(const int (&leds)[3], const int (&buttons)[N]) {
    for (unsigned i = 0; i < 3; ++i) {
        if (!indicatorPin(leds[i])) return false;
        if (leds[i] == -1) continue;
        for (const int button : buttons) if (leds[i] == button) return false;
        for (unsigned j = 0; j < i; ++j) if (leds[i] == leds[j]) return false;
    }
    return true;
}
enum class Indicator { Idle, Sending, Completed, Error };
// Main-loop owned. A result is shown for two seconds; busy presses cannot hide it.
class Feedback {
    Indicator current = Indicator::Idle;
    uint32_t since = 0;
public:
    void start() { current = Indicator::Sending; }
    void finish(Outcome outcome, uint32_t now) {
        current = outcome == Outcome::Simulated || outcome == Outcome::Unconfirmed
            ? Indicator::Completed : Indicator::Error;
        since = now;
    }
    void reject(uint32_t now) {
        if (current != Indicator::Sending) finish(Outcome::Failed, now);
    }
    Indicator sample(uint32_t now) {
        if (current != Indicator::Sending && uint32_t(now - since) >= 2000)
            current = Indicator::Idle;
        return current;
    }
};
}
