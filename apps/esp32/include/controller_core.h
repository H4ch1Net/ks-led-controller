#pragma once
#include <cstdint>
#include <string>

namespace ks {
class Button {
    bool stable, candidate;
    uint32_t since, debounce;
public:
    Button(bool pressed, uint32_t now, uint32_t delay = 50)
        : stable(pressed), candidate(pressed), since(now), debounce(delay) {}
    bool sample(bool pressed, uint32_t now) {
        if (candidate != pressed) { candidate = pressed; since = now; }
        if (stable != candidate && uint32_t(now - since) >= debounce) {
            stable = candidate;
            return stable;
        }
        return false;
    }
};
inline bool identifier(const std::string& value, size_t limit) {
    if (value.empty() || value.size() > limit) return false;
    for (char c : value) {
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '_' || c == '-')) return false;
    }
    return true;
}
struct Response {
    bool ok = false;
    std::string operation, status, confirmation;
};
enum class Outcome { Simulated, Unconfirmed, Failed, Unknown };
// Each request also has timeouts; an in-flight request may outlive the polling budget.
template<class Transport>
Outcome execute(Transport& transport, uint32_t budget = 20000) {
    const uint32_t start = transport.now();
    const auto submitted = transport.submit(); // Exactly once, even on malformed responses.
    if (!submitted.ok || !identifier(submitted.operation, 128)) return Outcome::Unknown;
    while (uint32_t(transport.now() - start) < budget) {
        const auto reply = transport.poll(submitted.operation);
        if (!reply.ok || reply.operation != submitted.operation) return Outcome::Unknown;
        if (reply.status == "succeeded") {
            if (reply.confirmation == "simulated") return Outcome::Simulated;
            if (reply.confirmation == "unconfirmed") return Outcome::Unconfirmed;
            return Outcome::Unknown;
        }
        if (reply.status == "failed" || reply.status == "cancelled") return Outcome::Failed;
        if (reply.status != "queued" && reply.status != "running") return Outcome::Unknown;
        transport.wait(200);
    }
    return Outcome::Unknown;
}
}
