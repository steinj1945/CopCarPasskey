#include "SessionCrypto.h"
#include "SessionKeys.h"
#include "mbedtls/version.h"
#include "mbedtls/ecp.h"
#include "mbedtls/ecdh.h"
// mbedTLS 2.x has public struct members; 3.x hides them behind MBEDTLS_PRIVATE()
#ifndef MBEDTLS_PRIVATE
#define MBEDTLS_PRIVATE(member) member
#endif
#include "mbedtls/gcm.h"
#include "mbedtls/sha256.h"
#include <esp_random.h>
#include <Arduino.h>
#include <string.h>

static uint8_t s_aes_key[32];
static bool    s_ready = false;

bool session_init() {
    mbedtls_ecp_group grp;
    mbedtls_mpi       d, z;
    mbedtls_ecp_point Q;

    mbedtls_ecp_group_init(&grp);
    mbedtls_mpi_init(&d);
    mbedtls_mpi_init(&z);
    mbedtls_ecp_point_init(&Q);

#if MBEDTLS_VERSION_MAJOR < 3
    // mbedTLS 2.x uses the generic Montgomery ladder which treats the MPI as a
    // big-endian integer. mbedTLS 3.x routes Curve25519 through the PSA/X25519
    // path which consumes key bytes directly as little-endian (RFC 7748). Reverse
    // both inputs so the scalar and u-coordinate integer values are identical
    // between the two versions, producing the same shared secret.
    uint8_t priv_be[32], pub_be[32];
    for (int i = 0; i < 32; i++) {
        priv_be[i] = ESP32_PRIVATE_KEY[31 - i];
        pub_be[i]  = IOS_PUBLIC_KEY[31 - i];
    }
    const uint8_t *priv_bytes = priv_be;
    const uint8_t *pub_bytes  = pub_be;
#else
    const uint8_t *priv_bytes = ESP32_PRIVATE_KEY;
    const uint8_t *pub_bytes  = IOS_PUBLIC_KEY;
#endif

    int ret = mbedtls_ecp_group_load(&grp, MBEDTLS_ECP_DP_CURVE25519);
    if (ret == 0) ret = mbedtls_mpi_read_binary(&d, priv_bytes, 32);
    if (ret == 0) ret = mbedtls_mpi_read_binary(&Q.MBEDTLS_PRIVATE(X), pub_bytes, 32);
    if (ret == 0) ret = mbedtls_mpi_lset(&Q.MBEDTLS_PRIVATE(Z), 1);
    if (ret == 0) ret = mbedtls_ecdh_compute_shared(&grp, &z, &Q, &d, NULL, NULL);

    uint8_t shared[32] = {};
    if (ret == 0) mbedtls_mpi_write_binary(&z, shared, sizeof(shared));

    mbedtls_ecp_group_free(&grp);
    mbedtls_mpi_free(&d);
    mbedtls_mpi_free(&z);
    mbedtls_ecp_point_free(&Q);

    if (ret != 0) {
        Serial.printf("[SessionCrypto] ECDH failed (mbedtls -0x%04x)\n", -ret);
        return false;
    }

#if MBEDTLS_VERSION_MAJOR < 3
    // mbedtls_mpi_write_binary always emits big-endian bytes, but iOS CryptoKit
    // returns the X25519 shared secret little-endian (RFC 7748). Reverse so both
    // sides feed the same byte string into SHA-256.
    for (int i = 0, j = 31; i < j; i++, j--) {
        uint8_t t = shared[i]; shared[i] = shared[j]; shared[j] = t;
    }
#endif

    Serial.print("[SessionCrypto] ECDH shared secret: ");
    for (int i = 0; i < 32; i++) Serial.printf("%02x", shared[i]);
    Serial.println();

    mbedtls_sha256(shared, 32, s_aes_key, /*is224=*/0);

    Serial.print("[SessionCrypto] AES-256 key (SHA-256 of shared): ");
    for (int i = 0; i < 32; i++) Serial.printf("%02x", s_aes_key[i]);
    Serial.println();

    s_ready = true;
    Serial.println("[SessionCrypto] Session key init OK.");
    return true;
}

bool session_encrypt(const uint8_t *plain32, uint8_t *out60) {
    if (!s_ready) return false;

    // First 12 bytes of out60 are the AES-GCM IV (hardware RNG)
    esp_fill_random(out60, 12);

    mbedtls_gcm_context gcm;
    mbedtls_gcm_init(&gcm);
    int ret = mbedtls_gcm_setkey(&gcm, MBEDTLS_CIPHER_ID_AES, s_aes_key, 256);
    if (ret == 0) {
        ret = mbedtls_gcm_crypt_and_tag(
            &gcm, MBEDTLS_GCM_ENCRYPT,
            SESSION_PLAIN_LEN,  // plaintext length
            out60, 12,          // IV, IV length
            NULL, 0,            // no AAD
            plain32,            // input
            out60 + 12,         // ciphertext output (32 bytes)
            16,                 // tag length
            out60 + 44          // tag output (16 bytes)
        );
    }
    mbedtls_gcm_free(&gcm);
    return ret == 0;
}

bool session_decrypt(const uint8_t *in60, uint8_t *plain32) {
    if (!s_ready) {
        Serial.println("[SessionCrypto] decrypt: session not initialised");
        return false;
    }

    Serial.print("[SessionCrypto] decrypt IV:  ");
    for (int i = 0; i < 12; i++) Serial.printf("%02x", in60[i]);
    Serial.println();
    Serial.print("[SessionCrypto] decrypt CT:  ");
    for (int i = 12; i < 44; i++) Serial.printf("%02x", in60[i]);
    Serial.println();
    Serial.print("[SessionCrypto] decrypt tag: ");
    for (int i = 44; i < 60; i++) Serial.printf("%02x", in60[i]);
    Serial.println();

    mbedtls_gcm_context gcm;
    mbedtls_gcm_init(&gcm);
    int ret = mbedtls_gcm_setkey(&gcm, MBEDTLS_CIPHER_ID_AES, s_aes_key, 256);
    if (ret != 0) {
        Serial.printf("[SessionCrypto] gcm_setkey failed: -0x%04x\n", -ret);
        mbedtls_gcm_free(&gcm);
        return false;
    }
    ret = mbedtls_gcm_auth_decrypt(
        &gcm,
        SESSION_PLAIN_LEN,  // ciphertext length
        in60, 12,           // IV, IV length
        NULL, 0,            // no AAD
        in60 + 44, 16,      // tag, tag length
        in60 + 12,          // ciphertext input
        plain32             // plaintext output
    );
    mbedtls_gcm_free(&gcm);

    if (ret != 0) {
        Serial.printf("[SessionCrypto] auth_decrypt failed: -0x%04x (likely wrong key or tampered packet)\n", -ret);
    } else {
        Serial.println("[SessionCrypto] decrypt OK");
    }
    return ret == 0;
}
