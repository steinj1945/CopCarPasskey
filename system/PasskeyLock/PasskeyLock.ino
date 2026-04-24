#include <Preferences.h>
#include "Config.h"
#include "SessionCrypto.h"
#include "StateMachine.h"

uint8_t g_hmac_key[HMAC_KEY_LEN];

void setup() {
    Serial.begin(115200);

    // Load 32-byte secret from NVS (written once by Provisioning.ino)
    Preferences prefs;
    prefs.begin(NVS_NAMESPACE, /*readOnly=*/true);
    size_t len = prefs.getBytes(NVS_KEY_SECRET, g_hmac_key, HMAC_KEY_LEN);
    prefs.end();

    if (len != HMAC_KEY_LEN) {
        Serial.println("ERROR: No key in NVS. Flash Provisioning.ino first.");
    }

    if (!session_init()) {
        Serial.println("ERROR: Session key init failed. Check SessionKeys.h.");
    }

    sm_init();
}

void loop() {
    sm_update();
}
