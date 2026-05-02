#include "RelayController.h"
#include "Config.h"
#include <Arduino.h>

static bool s_state = false;

void relay_init() {
    pinMode(PIN_RELAY, OUTPUT);
    digitalWrite(PIN_RELAY, LOW);
}

void relay_on() {
    s_state = true;
    digitalWrite(PIN_RELAY, HIGH);
}

void relay_off() {
    s_state = false;
    digitalWrite(PIN_RELAY, LOW);
}

bool relay_state() {
    return s_state;
}
