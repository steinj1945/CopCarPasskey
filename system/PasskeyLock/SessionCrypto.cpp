#include "SessionCrypto.h"
#include "SessionKeys.h"
#include "mbedtls/ecp.h"
#include "mbedtls/ecdh.h"
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

    int ret = mbedtls_ecp_group_load(&grp, MBEDTLS_ECP_DP_CURVE25519);
    if (ret == 0) ret = mbedtls_mpi_read_binary(&d, ESP32_PRIVATE_KEY, 32);
    // Curve25519 public key is the u-coordinate (32 bytes, little-endian in X25519)
    if (ret == 0) ret = mbedtls_mpi_read_binary(&Q.X, IOS_PUBLIC_KEY, 32);
    if (ret == 0) ret = mbedtls_mpi_lset(&Q.Z, 1);
    if (ret == 0) ret = mbedtls_ecdh_compute_shared(&grp, &z, &Q, &d, NULL, NULL);

    uint8_t shared[32] = {};
    if (ret == 0) mbedtls_mpi_write_binary(&z, shared, sizeof(shared));

    mbedtls_ecp_group_free(&grp);
    mbedtls_mpi_free(&d);
    mbedtls_mpi_free(&z);
    mbedtls_ecp_point_free(&Q);

    if (ret != 0) {
        Serial.printf("session_init: ECDH failed (mbedtls -0x%04x)\n", -ret);
        return false;
    }

    mbedtls_sha256(shared, 32, s_aes_key, /*is224=*/0);
    s_ready = true;
    Serial.println("Session key init OK.");
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
    if (!s_ready) return false;

    mbedtls_gcm_context gcm;
    mbedtls_gcm_init(&gcm);
    int ret = mbedtls_gcm_setkey(&gcm, MBEDTLS_CIPHER_ID_AES, s_aes_key, 256);
    if (ret == 0) {
        ret = mbedtls_gcm_auth_decrypt(
            &gcm,
            SESSION_PLAIN_LEN,  // ciphertext length
            in60, 12,           // IV, IV length
            NULL, 0,            // no AAD
            in60 + 44, 16,      // tag, tag length
            in60 + 12,          // ciphertext input
            plain32             // plaintext output
        );
    }
    mbedtls_gcm_free(&gcm);
    return ret == 0;
}
