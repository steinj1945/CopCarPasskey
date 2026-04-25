#include "ProvisioningMode.h"
#include "SessionCrypto.h"
#include "Config.h"
#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>
#include "mbedtls/base64.h"
#include <Arduino.h>

void provisioning_run() {
    digitalWrite(PIN_STATUS_LED, HIGH);
    Serial.println("Provisioning mode: starting WiFi AP");

    WiFi.softAP(PROV_SSID, PROV_PASS);
    Serial.printf("AP IP: %s\n", WiFi.softAPIP().toString().c_str());
    Serial.printf("SSID: %s\n", PROV_SSID);

    WebServer server(80);
    bool done = false;

    // POST /provision — body is base64-encoded 60-byte AES-GCM packet
    server.on("/provision", HTTP_POST, [&]() {
        String body = server.arg("plain");
        if (body.length() == 0) {
            server.send(400, "text/plain", "empty body");
            return;
        }

        // Base64-decode → 60-byte encrypted packet
        uint8_t enc[SESSION_PACKET_LEN];
        size_t  olen = 0;
        int r = mbedtls_base64_decode(enc, sizeof(enc), &olen,
                    (const uint8_t*)body.c_str(), body.length());
        if (r != 0 || olen != SESSION_PACKET_LEN) {
            server.send(400, "text/plain", "bad payload");
            return;
        }

        // Decrypt → 32-byte HMAC secret
        uint8_t secret[32];
        if (!session_decrypt(enc, secret)) {
            server.send(403, "text/plain", "decryption failed");
            return;
        }

        // Write to NVS
        Preferences prefs;
        prefs.begin(NVS_NAMESPACE, /*readOnly=*/false);
        size_t written = prefs.putBytes(NVS_KEY_SECRET, secret, 32);
        prefs.end();

        if (written != 32) {
            server.send(500, "text/plain", "nvs write failed");
            return;
        }

        server.send(200, "text/plain", "OK");
        Serial.println("Provisioning complete. Rebooting.");
        done = true;
    });

    server.begin();

    uint32_t start = millis();
    while (!done && (millis() - start < PROV_TIMEOUT_MS)) {
        server.handleClient();
        digitalWrite(PIN_STATUS_LED, (millis() / 500) % 2);  // 500 ms blink
    }

    server.stop();
    WiFi.softAPdisconnect(true);

    if (done) {
        delay(200);
        ESP.restart();
    } else {
        Serial.println("Provisioning timed out. Continuing normal boot.");
        digitalWrite(PIN_STATUS_LED, LOW);
    }
}
