#include <Preferences.h>
#include "Config.h"
#include "SessionCrypto.h"
#include "ProvisioningMode.h"
#include "StateMachine.h"

uint8_t g_hmac_key[HMAC_KEY_LEN];

void setup() {
    Serial.begin(115200);
    pinMode(PIN_BUTTON, INPUT_PULLUP);
    pinMode(PIN_STATUS_LED, OUTPUT);

    // Session crypto initialised first — provisioning_run() needs session_decrypt()
    if (!session_init()) {
        Serial.println("ERROR: Session key init failed. Check SessionKeys.h.");
    }

    // 5-second hold check: button held LOW on boot triggers WiFi provisioning.
    // On deep-sleep wake the button is still physically held, so this check
    // catches both a cold boot with button held and a wake with button held.
    if (digitalRead(PIN_BUTTON) == LOW) {
        uint32_t held_since = millis();
        while (digitalRead(PIN_BUTTON) == LOW) {
            // Fast blink while counting down to provisioning mode
            digitalWrite(PIN_STATUS_LED, (millis() / 100) % 2);
            if (millis() - held_since >= PROV_BUTTON_HOLD_MS) {
                // Confirmed 5-second hold — enter provisioning
                provisioning_run();  // reboots on success; returns on timeout
                break;
            }
        }
        digitalWrite(PIN_STATUS_LED, LOW);
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
