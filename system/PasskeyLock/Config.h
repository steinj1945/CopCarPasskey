#pragma once

// ── Pin assignments (ESP32) ───────────────────────────────────────
// Adjust to match your specific board layout.
#define PIN_BUTTON      0   // GPIO0 — boot button, or any RTC-capable GPIO
#define PIN_RELAY       26  // GPIO26 — relay IN (HIGH = energised / open)
#define PIN_STATUS_LED  2   // GPIO2  — built-in LED on most ESP32 dev boards

// ── BLE service / characteristic UUIDs ──────────────────────────
// Must match the iOS/Watch app exactly.
#define UUID_SERVICE    "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
#define UUID_CHALLENGE  "A1B2C3D4-E5F6-7890-ABCD-EF1234567891"
#define UUID_RESPONSE   "A1B2C3D4-E5F6-7890-ABCD-EF1234567892"
#define UUID_STATUS     "A1B2C3D4-E5F6-7890-ABCD-EF1234567893"

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
#define PROV_TIMEOUT_MS       300000  // AP shuts down after 5 min if unused

// ── BLE session encryption packet size ───────────────────────────
// CHALLENGE and RESPONSE characteristics carry encrypted payloads:
//   12 bytes IV + 32 bytes ciphertext + 16 bytes GCM tag = 60 bytes
#define SESSION_PACKET_LEN  60

// g_hmac_key populated in setup(). Declared extern; defined in PasskeyLock.ino.
extern uint8_t g_hmac_key[HMAC_KEY_LEN];
#define HMAC_KEY g_hmac_key
