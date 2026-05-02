#include "CryptoAuth.h"
#include "mbedtls/md.h"
#include <Arduino.h>
#include <esp_random.h>
#include <string.h>

static void hmac_sha256(const uint8_t *key, size_t klen,
                        const uint8_t *msg, size_t mlen,
                        uint8_t *out32) {
    const mbedtls_md_info_t *info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    mbedtls_md_hmac(info, key, klen, msg, mlen, out32);
}

bool hmac_verify(const uint8_t *nonce,    uint8_t nonce_len,
                 const uint8_t *response, uint8_t response_len,
                 const uint8_t *key,      uint8_t key_len) {
    if (response_len != 32) {
        Serial.printf("[Auth] bad response_len=%u (expected 32)\n", response_len);
        return false;
    }

    uint8_t expected[32];
    hmac_sha256(key, key_len, nonce, nonce_len, expected);

    Serial.print("[Auth] nonce:    ");
    for (int i = 0; i < nonce_len; i++) Serial.printf("%02x", nonce[i]);
    Serial.println();
    Serial.print("[Auth] expected: ");
    for (int i = 0; i < 32; i++) Serial.printf("%02x", expected[i]);
    Serial.println();
    Serial.print("[Auth] received: ");
    for (int i = 0; i < 32; i++) Serial.printf("%02x", response[i]);
    Serial.println();

    uint8_t diff = 0;
    for (int i = 0; i < 32; i++) diff |= expected[i] ^ response[i];
    bool ok = (diff == 0);
    Serial.printf("[Auth] HMAC verify: %s\n", ok ? "PASS" : "FAIL");
    return ok;
}

void random_nonce(uint8_t *buf, uint8_t len) {
    esp_fill_random(buf, len);
}
