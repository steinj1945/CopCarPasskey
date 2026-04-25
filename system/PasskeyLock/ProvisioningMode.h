#pragma once

// Enter WiFi SoftAP provisioning mode.
// Blocks until the iOS app delivers and the ESP32 writes the HMAC secret to NVS,
// then calls ESP.restart(). Only returns if provisioning times out (PROV_TIMEOUT_MS),
// in which case normal boot continues.
void provisioning_run();
