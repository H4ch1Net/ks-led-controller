#pragma once
#include "controller_core.h"

namespace ks {
// Main-loop owned; one latest value, never a queue of intermediate brightnesses.
class Dimmer {
    int level = 50, sent = 50;
    bool pending = false, paused = false;
    uint32_t since = 0;
public:
    int value() const { return level; }
    bool isPaused() const { return paused; }
    void turn(int direction, uint32_t now) {
        const int next = level + (direction > 0 ? 5 : direction < 0 ? -5 : 0);
        const int bounded = next < 1 ? 1 : next > 100 ? 100 : next;
        if (bounded == level) return;
        level = bounded;
        if (!paused) {
            if (!pending) since = now;
            pending = true;
        }
    }
    bool due(uint32_t now) const { return pending && !paused && uint32_t(now - since) >= 200; }
    int start() { paused = false; pending = false; sent = level; return sent; }
    void cancel() { pending = false; paused = true; }
    void complete(Outcome result) {
        if (result != Outcome::Simulated && result != Outcome::Unconfirmed) cancel();
        else if (level == sent) pending = false;
    }
};
}
