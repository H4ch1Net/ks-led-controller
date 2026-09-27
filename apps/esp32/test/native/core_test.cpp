#include "../../include/controller_core.h"
#include "../../include/status_feedback.h"
#include "../../include/rotary.h"
#include "../../include/dimmer.h"
#include <cassert>
#include <iostream>
#include <vector>

struct Fake {
    uint32_t clock = 0;
    int submissions = 0, polls = 0;
    ks::Response submitted{true, "op_test", "queued", ""};
    std::vector<ks::Response> replies{{true, "op_test", "succeeded", "simulated"}};
    uint32_t now() { return clock; }
    void wait(uint32_t ms) { clock += ms; }
    ks::Response submit() { ++submissions; return submitted; }
    ks::Response poll(const std::string&) {
        size_t index = size_t(polls++);
        return replies[index < replies.size() ? index : replies.size() - 1];
    }
};
int main() {
    ks::Dimmer dimmer;
    assert(dimmer.value() == 50 && !dimmer.due(10000));
    dimmer.turn(1, 10); dimmer.turn(1, 150);
    assert(!dimmer.due(209) && dimmer.due(210)); // window is not reset by every tick
    assert(dimmer.start() == 60);
    dimmer.turn(1, 220); dimmer.turn(1, 230);
    dimmer.complete(ks::Outcome::Unconfirmed);
    assert(dimmer.due(420) && dimmer.start() == 70); // only latest value survives a busy request
    dimmer.turn(-1, 430); dimmer.turn(1, 440);
    dimmer.complete(ks::Outcome::Simulated);
    assert(!dimmer.due(1000)); // returning to the sent level needs no duplicate write
    dimmer.turn(1, 1001); dimmer.start(); dimmer.turn(1, 1002);
    dimmer.complete(ks::Outcome::Unknown);
    dimmer.turn(1, 2000);
    assert(dimmer.isPaused() && !dimmer.due(5000));
    assert(dimmer.start() == 85 && !dimmer.isPaused()); // explicit press rearms
    dimmer.cancel(); dimmer.turn(-1, 5001);
    assert(!dimmer.due(10000)); // an Off/button action cannot be overwritten by old motion
    for (int i = 0; i < 100; ++i) dimmer.turn(-1, 10000);
    assert(dimmer.value() == 1);
    dimmer.start();
    for (int i = 0; i < 100; ++i) dimmer.turn(1, UINT32_MAX - 100);
    assert(dimmer.value() == 100 && !dimmer.due(98) && dimmer.due(99));
    ks::Rotary rotary;
    for (int state : {2,0,1}) assert(rotary.sample(uint8_t(state)) == 0);
    assert(rotary.sample(3) == 1);
    for (int state : {1,0,2}) assert(rotary.sample(uint8_t(state)) == 0);
    assert(rotary.sample(3) == -1);
    // Contact bounce and reversal do not invent detents.
    for (int state : {2,3,2,0,2,0,1}) assert(rotary.sample(uint8_t(state)) == 0);
    assert(rotary.sample(3) == 1);
    for (int state : {2,0,2,3,3,3}) assert(rotary.sample(uint8_t(state)) == 0);
    // Illegal two-contact jump loses the turn and realigns at rest.
    for (int state : {0,1,3}) assert(rotary.sample(uint8_t(state)) == 0);
    ks::Rotary startup(0);
    for (int state : {1,3,2,0,1}) assert(startup.sample(uint8_t(state)) == 0);
    assert(startup.sample(3) == 1);
    // Busy input is consumed, including turns spanning the busy boundary.
    assert(rotary.sample(2, false) == 0);
    for (int state : {0,1,3}) assert(rotary.sample(uint8_t(state)) == 0);
    for (int state : {2,0,1,3}) assert(rotary.sample(uint8_t(state), false) == 0);
    for (int state : {2,0,1}) assert(rotary.sample(uint8_t(state)) == 0);
    assert(rotary.sample(3) == 1);
    const int pins[] = {18,19,21,22};
    assert(ks::buttonPins(pins));
    const int duplicateButtons[] = {18,18,21,22}, missingButton[] = {18,19,21,-1};
    const int reservedButton[] = {18,19,21,6};
    assert(!ks::buttonPins(duplicateButtons));
    assert(!ks::buttonPins(missingButton));
    assert(!ks::buttonPins(reservedButton));
    const int enabled[] = {23,25,26}, disabled[] = {-1,-1,-1};
    const int duplicate[] = {23,23,-1}, collision[] = {18,25,26};
    assert(ks::indicatorPins(enabled, pins));
    assert(ks::indicatorPins(disabled, pins));
    assert(!ks::indicatorPins(duplicate, pins));
    assert(!ks::indicatorPins(collision, pins));
    for (int invalid : {-2,0,1,6,12,34,99}) {
        const int bad[] = {invalid,-1,-1};
        assert(!ks::indicatorPins(bad, pins));
    }
    ks::Feedback lights;
    assert(lights.sample(0) == ks::Indicator::Idle);
    lights.start();
    lights.reject(100);
    assert(lights.sample(100000) == ks::Indicator::Sending);
    lights.finish(ks::Outcome::Unconfirmed, 100000);
    assert(lights.sample(101999) == ks::Indicator::Completed);
    assert(lights.sample(102000) == ks::Indicator::Idle);
    for (auto result : {ks::Outcome::Unknown, ks::Outcome::Failed}) {
        lights.start(); lights.finish(result, UINT32_MAX - 1000);
        assert(lights.sample(998) == ks::Indicator::Error);
        assert(lights.sample(999) == ks::Indicator::Idle);
    }
    lights.finish(ks::Outcome::Simulated, 2000);
    assert(lights.sample(2000) == ks::Indicator::Completed);
    lights.start();
    assert(lights.sample(5000) == ks::Indicator::Sending);
    lights.finish(ks::Outcome::Unconfirmed, 5000);
    lights.reject(6000);
    assert(lights.sample(6000) == ks::Indicator::Error);
    ks::Button button(false, 0);
    assert(!button.sample(true, 10));
    assert(!button.sample(false, 20));
    assert(!button.sample(true, 30));
    assert(!button.sample(true, 60));
    assert(button.sample(true, 81));
    assert(!button.sample(true, 900));
    assert(!button.sample(false, 1000));
    assert(!button.sample(false, 1060));
    assert(!button.sample(true, 1100));
    assert(button.sample(true, 1160));
    ks::Button held(true, 0);
    assert(!held.sample(true, 5000));
    assert(!held.sample(false, 5010));
    assert(!held.sample(false, 5070));
    assert(!held.sample(true, 5080));
    assert(held.sample(true, 5140));
    ks::Button wrap(false, UINT32_MAX - 20);
    assert(!wrap.sample(true, UINT32_MAX - 10));
    assert(wrap.sample(true, 45));
    assert(!ks::identifier("../elsewhere", 128));
    assert(!ks::identifier("", 128));
    assert(!ks::identifier(std::string(129, 'a'), 128));
    for (const auto* confirmation : {"simulated", "unconfirmed"}) {
        Fake f;
        f.replies = {{true,"op_test","queued",""}, {true,"op_test","succeeded",confirmation}};
        assert(ks::execute(f) == (std::string(confirmation) == "simulated" ? ks::Outcome::Simulated : ks::Outcome::Unconfirmed));
        assert(f.submissions == 1 && f.polls == 2);
    }
    for (const auto* status : {"failed", "cancelled"}) {
        Fake f; f.replies[0].status = status;
        assert(ks::execute(f) == ks::Outcome::Failed && f.submissions == 1);
    }
    { Fake f; f.submitted.ok = false;
      assert(ks::execute(f) == ks::Outcome::Unknown && f.submissions == 1 && f.polls == 0); }
    { Fake f; f.submitted.operation = "../invalid";
      assert(ks::execute(f) == ks::Outcome::Unknown && f.polls == 0); }
    { Fake f; f.replies[0].ok = false;
      assert(ks::execute(f) == ks::Outcome::Unknown && f.submissions == 1 && f.polls == 1); }
    { Fake f; f.replies[0].operation = "op_someone_else";
      assert(ks::execute(f) == ks::Outcome::Unknown && f.submissions == 1); }
    { Fake f; f.replies[0].status = "surprise";
      assert(ks::execute(f) == ks::Outcome::Unknown && f.submissions == 1); }
    { Fake f; f.replies[0].confirmation = "";
      assert(ks::execute(f) == ks::Outcome::Unknown); }
    { Fake f; f.clock = UINT32_MAX - 100; f.replies[0].status = "queued";
      assert(ks::execute(f, 500) == ks::Outcome::Unknown && f.submissions == 1 && f.polls == 3); }
    std::cout << "ESP32 core checks passed: debounce, startup hold, rollover, terminal outcomes, malformed responses, no retries.\n";
}
