#pragma once
#include <stdint.h>

// Initialise the ESP32 BLE stack as a central (client).
void bt_init();

// Begin an async BLE scan for peripherals advertising UUID_SERVICE.
// Returns immediately; poll bt_scan_found() for results.
void bt_scan_start();

// Returns true once a device with RSSI >= RSSI_THRESHOLD is found.
bool bt_scan_found();

// Connect to the found device and discover GATT characteristics.
// Blocking — typically completes in 1–3 s.
void bt_connect();

bool bt_connected();
void bt_disconnect();

// Write the 60-byte encrypted nonce packet to the CHALLENGE characteristic.
void bt_send_challenge(const uint8_t *nonce, uint8_t len);

// Returns true when the peripheral has notified the RESPONSE characteristic.
bool bt_response_ready();

// Copy the 60-byte encrypted HMAC response packet into buf.
void bt_read_response(uint8_t *buf, uint8_t len);

// Write a 1-byte status value to the STATUS characteristic.
void bt_notify_status(uint8_t status);
