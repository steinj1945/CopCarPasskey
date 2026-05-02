#pragma once
#include <stdint.h>

// HMAC-SHA256 computed entirely on-device.
// Returns true if the 32-byte response matches HMAC-SHA256(nonce, key).
bool hmac_verify(const uint8_t *nonce,    uint8_t nonce_len,
                 const uint8_t *response, uint8_t response_len,
                 const uint8_t *key,      uint8_t key_len);

// Fill buf with random bytes using the AVR's analog noise.
void random_nonce(uint8_t *buf, uint8_t len);
