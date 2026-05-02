#include <Preferences.h>
#include "Config.h"
#include "LedController.h"
#include "SessionCrypto.h"
#include "ProvisioningMode.h"
#include "StateMachine.h"

uint8_t g_hmac_key[HMAC_KEY_LEN];

void setup() {
    Serial.begin(115200);
    pinMode(PIN_BUTTON,     INPUT_PULLUP);
    pinMode(PIN_BUTTON_AUX, INPUT_PULLUP);

    led_init();
    led_set(LED_INITIALIZING);
    led_update();

    // Session crypto must be ready before provisioning (uses session_decrypt)
    if (!session_init()) {
        Serial.println("ERROR: Session key init failed. Check SessionKeys.h.");
    }

    // 5-second hold: button held LOW on boot triggers WiFi provisioning.
    // Fast-blink red (LED_AP_MODE blink rate) during the countdown so the
    // user gets visual feedback before the hold threshold is reached.
    if (digitalRead(PIN_BUTTON) == LOW) {
        uint32_t held_since = millis();
        while (digitalRead(PIN_BUTTON) == LOW) {
            led_set(LED_AP_MODE);
            led_update();
            if (millis() - held_since >= PROV_BUTTON_HOLD_MS) {
                provisioning_run();  // reboots on success; returns on timeout
                break;
            }
        }
        // Button released early or provisioning timed out — continue normal boot
        led_set(LED_INITIALIZING);
        led_update();
    }

    // Normal boot — load HMAC key from NVS
    Preferences prefs;
    prefs.begin(NVS_NAMESPACE, /*readOnly=*/true);
    size_t len = prefs.getBytes(NVS_KEY_SECRET, g_hmac_key, HMAC_KEY_LEN);
    prefs.end();

    if (len != HMAC_KEY_LEN) {
        Serial.println("ERROR: No key in NVS. Hold button 5 s to provision via iOS app.");
    }

    sm_init();
}

void loop() {
    sm_update();
}
