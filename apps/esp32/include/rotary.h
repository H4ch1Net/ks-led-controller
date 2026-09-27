#pragma once
#include <cstdint>

namespace ks {
// Full-cycle mechanical encoder: detents at both contacts HIGH (state 3).
// Invalid transitions lose a partial turn; they never invent a selection.
class Rotary {
    uint8_t previous;
    int progress = 0;
    bool aligned;
public:
    explicit Rotary(uint8_t initial = 3) : previous(initial & 3), aligned(previous == 3) {}
    int sample(uint8_t state, bool enabled = true) {
        state &= 3;
        const uint8_t old = previous;
        previous = state;
        if (!enabled) { progress = 0; aligned = state == 3; return 0; }
        if (!aligned || (old ^ state) == 3) {
            progress = 0;
            aligned = state == 3;
            return 0;
        }
        // 3 -> 2 -> 0 -> 1 -> 3 increments; reversal cancels bounce.
        static constexpr int steps[] = {0,1,-1,0, -1,0,0,1, 1,0,0,-1, 0,-1,1,0};
        progress += steps[(old << 2) | state];
        if (state != 3) return 0;
        const int result = progress == 4 ? 1 : progress == -4 ? -1 : 0;
        progress = 0;
        return result;
    }
};
}
