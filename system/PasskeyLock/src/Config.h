#pragma once
#include <stdint.h>

// ── Pin assignments (ESP32) ───────────────────────────────────────
#define PIN_BUTTON      32  // GPIO32 — primary button (RTC-capable; wakes deep sleep)
#define PIN_BUTTON_AUX  33  // GPIO33 — auxiliary button (wired, reserved for future use)
#define PIN_RELAY       14  // GPIO14 — relay IN (HIGH = energised / open)
#define PIN_LED_RED     25  // GPIO25 — red   LED
#define PIN_LED_YELLOW  26  // GPIO26 — yellow LED
#define PIN_LED_GREEN   27  // GPIO27 — green  LED

// ── BLE service / characteristic UUIDs ──────────────────────────
// Must match the iOS/Watch app exactly.
#define UUID_SERVICE    "6CEC9D24-598B-40CF-AA8F-A2BE12A626A6"
#define UUID_CHALLENGE  "FE879FA1-26CE-4CEB-AC6A-0FAE75D25E03"
#define UUID_RESPONSE   "8EDE1ACC-39C6-4600-A06D-2D431C78ECB9"
#define UUID_STATUS     "84962402-30AF-4AD3-A1AB-55696CFE1AB4"

// ── Timing (ms) ──────────────────────────────────────────────────
#define SCAN_TIMEOUT_MS         15000   // Give up scanning after 15 s
#define CONNECT_TIMEOUT_MS       8000   // Give up connecting after 8 s
#define AUTH_TIMEOUT_MS          5000   // Give up waiting for HMAC after 5 s
#define UNLOCK_AUTO_CLOSE_MS   300000   // Auto-relock after 5 min

// ── RSSI proximity threshold ─────────────────────────────────────
// -70 dBm ≈ 5 m  (standard proximity)
// -50 dBm ≈ 0.3 m (NFC-style Watch tap)
#define RSSI_THRESHOLD          -70

// ── HMAC key (32 bytes, loaded from NVS at boot) ─────────────────
// Written by the iOS app via WiFi provisioning (hold button 5 s to activate).
#define HMAC_KEY_LEN    32
#define NVS_NAMESPACE   "passkey"
#define NVS_KEY_SECRET  "secret"

// ── WiFi SoftAP provisioning ──────────────────────────────────────
// Hold PIN_BUTTON for PROV_BUTTON_HOLD_MS on boot to enter provisioning mode.
// The ESP32 becomes an AP; the iOS app connects and POSTs the encrypted secret.
#define PROV_SSID             "CopCar-Setup"
#define PROV_PASS             "copcar1234"
#define PROV_BUTTON_HOLD_MS   5000    // ms button must be held to trigger
#define PROV_TIMEOUT_MS       150000  // AP shuts down after 2.5 min if unused

// ── BLE session encryption packet size ───────────────────────────
// CHALLENGE and RESPONSE characteristics carry encrypted payloads:
//   12 bytes IV + 32 bytes ciphertext + 16 bytes GCM tag = 60 bytes
#define SESSION_PACKET_LEN  60

// g_hmac_key populated in setup(). Declared extern; defined in PasskeyLock.ino.
extern uint8_t g_hmac_key[HMAC_KEY_LEN];
#define HMAC_KEY g_hmac_key
