#include "LedController.h"
#include "Config.h"
#include <Arduino.h>

static LedPattern s_pattern = LED_INITIALIZING;

static void set_rgb(bool r, bool y, bool g) {
    digitalWrite(PIN_LED_RED,    r ? HIGH : LOW);
    digitalWrite(PIN_LED_YELLOW, y ? HIGH : LOW);
    digitalWrite(PIN_LED_GREEN,  g ? HIGH : LOW);
}

void led_init() {
    pinMode(PIN_LED_RED,    OUTPUT);
    pinMode(PIN_LED_YELLOW, OUTPUT);
    pinMode(PIN_LED_GREEN,  OUTPUT);
    set_rgb(false, false, false);
}

void led_set(LedPattern pattern) {
    s_pattern = pattern;
}

void led_update() {
    uint32_t now = millis();
    switch (s_pattern) {
        case LED_INITIALIZING:
            set_rgb(true, false, false);
            break;
        case LED_AP_MODE:
            { bool on = (now / 500) % 2;
              set_rgb(on, false, false); }
            break;
        case LED_READY:
            set_rgb(false, true, false);
            break;
        case LED_SEARCHING:
            { bool on = (now / 400) % 2;
              set_rgb(false, on, false); }
            break;
        case LED_FOUND:
            { bool on = (now / 200) % 2;
              set_rgb(false, true, on); }
            break;
        case LED_AUTH_PASS:
            set_rgb(false, false, true);
            break;
        case LED_AUTH_FAIL:
            { bool on = (now / 200) % 2;
              set_rgb(on, true, false); }
            break;
        case LED_ENGAGED:
            set_rgb(false, false, true);
            break;
    }
}
