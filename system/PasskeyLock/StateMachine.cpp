#include "StateMachine.h"
#include "BluetoothManager.h"
#include "RelayController.h"
#include "CryptoAuth.h"
#include "SessionCrypto.h"
#include "Config.h"
#include <Arduino.h>
#include <esp_sleep.h>

volatile bool g_button_pressed = false;

static State    s_state       = State::SLEEP;
static uint32_t s_state_enter = 0;
static uint8_t  s_nonce[32];

static void enter(State next) {
    // State-entry actions
    if (next == State::SCANNING) bt_scan_start();

    s_state       = next;
    s_state_enter = millis();
}

static bool timed_out(uint32_t limit_ms) {
    return (millis() - s_state_enter) >= limit_ms;
}

static void go_sleep() {
    relay_off();
    bt_disconnect();
    g_button_pressed = false;
    digitalWrite(PIN_STATUS_LED, LOW);

    // ESP32 deep sleep — woken by button (active LOW on PIN_BUTTON).
    // Unlike AVR sleep, deep sleep is a full CPU restart; execution
    // resumes at setup(), not here. sm_init() detects the wakeup cause
    // and skips straight to SCANNING.
    esp_sleep_enable_ext0_wakeup((gpio_num_t)PIN_BUTTON, LOW);
    esp_deep_sleep_start();
}

void sm_init() {
    pinMode(PIN_BUTTON, INPUT_PULLUP);

    // In normal (non-sleep-wake) running, catch button presses via interrupt
    // for the UNLOCKED → SLEEP transition.
    attachInterrupt(digitalPinToInterrupt(PIN_BUTTON), []() {
        g_button_pressed = true;
    }, FALLING);

    relay_init();
    bt_init();

    // If we woke from deep sleep via the button, skip SLEEP and scan immediately.
    if (esp_sleep_get_wakeup_cause() == ESP_SLEEP_WAKEUP_EXT0) {
        enter(State::SCANNING);
    } else {
        enter(State::SLEEP);
    }
}

void sm_update() {
    switch (s_state) {

    case State::SLEEP:
        go_sleep();
        // Does not return — ESP32 restarts after button wakes it.
        break;

    case State::SCANNING:
        // Slow blink while scanning
        digitalWrite(PIN_STATUS_LED, (millis() / 400) % 2);
        if (g_button_pressed) { g_button_pressed = false; enter(State::SLEEP); break; }
        if (timed_out(SCAN_TIMEOUT_MS))               { enter(State::SLEEP);    break; }
        if (bt_scan_found()) {
            bt_connect();           // blocking ~1-3 s
            enter(State::CONNECTING);
        }
        break;

    case State::CONNECTING:
        // Fast blink while negotiating
        digitalWrite(PIN_STATUS_LED, (millis() / 100) % 2);
        if (timed_out(CONNECT_TIMEOUT_MS))  { enter(State::SCANNING); break; }
        if (!bt_connected())                { break; }
        // Connection and characteristic discovery are done — send encrypted challenge
        random_nonce(s_nonce, sizeof(s_nonce));
        {
            uint8_t enc_challenge[SESSION_PACKET_LEN];
            if (!session_encrypt(s_nonce, enc_challenge)) { enter(State::SLEEP); break; }
            bt_send_challenge(enc_challenge, SESSION_PACKET_LEN);
        }
        enter(State::AUTHENTICATING);
        break;

    case State::AUTHENTICATING:
        if (timed_out(AUTH_TIMEOUT_MS)) { enter(State::SLEEP); break; }
        if (!bt_response_ready())       { break; }
        {
            uint8_t enc_response[SESSION_PACKET_LEN];
            uint8_t response[32];
            bt_read_response(enc_response, sizeof(enc_response));
            if (!session_decrypt(enc_response, response)) { enter(State::SLEEP); break; }
            if (hmac_verify(s_nonce, sizeof(s_nonce),
                            response, sizeof(response),
                            HMAC_KEY, HMAC_KEY_LEN)) {
                relay_on();
                bt_notify_status(0x01);
                digitalWrite(PIN_STATUS_LED, HIGH);
                enter(State::UNLOCKED);
            } else {
                bt_notify_status(0x00);
                enter(State::SLEEP);
            }
        }
        break;

    case State::UNLOCKED:
        if (g_button_pressed || timed_out(UNLOCK_AUTO_CLOSE_MS)) {
            g_button_pressed = false;
            bt_notify_status(0x00);
            enter(State::SLEEP);
        }
        break;
    }
}
