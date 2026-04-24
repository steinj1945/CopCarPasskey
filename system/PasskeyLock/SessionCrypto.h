#pragma once
#include <stdint.h>
#include <stdbool.h>

#define SESSION_PLAIN_LEN  32
#define SESSION_PACKET_LEN 60  // 12 (IV) + 32 (ciphertext) + 16 (GCM tag)

// Derive AES-256 session key via ECDH(ESP32_PRIVATE_KEY, IOS_PUBLIC_KEY).
// Call once in setup() after loading the HMAC key from NVS.
// Returns false and logs an error if ECDH fails; device will refuse to unlock.
bool session_init();

// Encrypt 32 bytes of plaintext into a 60-byte packet: [12-byte IV][32-byte CT][16-byte tag].
// Returns false if session_init() has not succeeded.
bool session_encrypt(const uint8_t *plain32, uint8_t *out60);

// Decrypt a 60-byte packet back to 32 bytes of plaintext.
// Returns false on auth failure (wrong key / tampered ciphertext) or if not initialised.
bool session_decrypt(const uint8_t *in60, uint8_t *plain32);
