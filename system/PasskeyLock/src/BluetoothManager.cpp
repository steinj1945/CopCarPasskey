#include "BluetoothManager.h"
#include "Config.h"
#include <BLEDevice.h>
#include <BLEScan.h>
#include <BLEClient.h>
#include <BLERemoteCharacteristic.h>
#include <Arduino.h>
#include <string.h>

// ── State shared between callbacks and main loop ──────────────────
static volatile bool s_found          = false;
static volatile bool s_connected      = false;
static volatile bool s_response_ready = false;

static BLEScan*               s_scan          = nullptr;
static BLEAdvertisedDevice*   s_target        = nullptr;
static BLEClient*             s_client        = nullptr;
static BLERemoteCharacteristic* s_challengeChar = nullptr;
static BLERemoteCharacteristic* s_responseChar  = nullptr;
static BLERemoteCharacteristic* s_statusChar    = nullptr;
static uint8_t                s_response_buf[SESSION_PACKET_LEN];
static uint16_t               s_response_received = 0;  // bytes accumulated so far

// ── Callbacks ─────────────────────────────────────────────────────

class ScanCallback : public BLEAdvertisedDeviceCallbacks {
    void onResult(BLEAdvertisedDevice dev) override {
        if (s_found) return;
        if (!dev.haveServiceUUID()) return;
        if (!dev.isAdvertisingService(BLEUUID(UUID_SERVICE))) return;
        int rssi = dev.getRSSI();
        if (rssi < RSSI_THRESHOLD) {
            Serial.printf("[BLE] device seen but RSSI %d < threshold %d — too far\n",
                          rssi, RSSI_THRESHOLD);
            return;
        }
        Serial.printf("[BLE] target found: %s  RSSI=%d\n",
                      dev.getAddress().toString().c_str(), rssi);
        s_scan->stop();
        if (s_target) delete s_target;
        s_target = new BLEAdvertisedDevice(dev);
        s_found  = true;
    }
};

class ClientCallback : public BLEClientCallbacks {
    void onConnect(BLEClient*)    override { s_connected = true;  }
    void onDisconnect(BLEClient*) override { s_connected = false; }
};

static void onResponseNotify(BLERemoteCharacteristic*, uint8_t* data,
                             size_t len, bool /*isNotify*/) {
    Serial.printf("[BLE] response chunk: %u bytes (have %u/%d)\n",
                  len, s_response_received + len, SESSION_PACKET_LEN);

    if (s_response_received + len > SESSION_PACKET_LEN) {
        Serial.println("[BLE] response overflow — discarding");
        s_response_received = 0;
        return;
    }

    memcpy(s_response_buf + s_response_received, data, len);
    s_response_received += len;

    if (s_response_received == SESSION_PACKET_LEN) {
        Serial.println("[BLE] response complete (60 bytes)");
        s_response_ready    = true;
        s_response_received = 0;
    }
}

// ── Public API ────────────────────────────────────────────────────

void bt_init() {
    BLEDevice::init("CopCarLock");
    // Request 185-byte MTU so writeWithoutResponse can carry the full 60-byte
    // session packet (default ATT_MTU=23 only allows 20 bytes of payload).
    BLEDevice::setMTU(185);

    s_scan = BLEDevice::getScan();
    s_scan->setAdvertisedDeviceCallbacks(new ScanCallback());
    s_scan->setActiveScan(true);
    s_scan->setInterval(100);   // ms
    s_scan->setWindow(99);      // must be <= interval
}

void bt_scan_start() {
    s_found             = false;
    s_connected         = false;
    s_response_ready    = false;
    s_response_received = 0;

    if (s_target) { delete s_target; s_target = nullptr; }
    if (s_client) { s_client->disconnect(); s_client = nullptr; }

    s_scan->clearResults();
    // duration=0 → scan until stopped by callback; async (non-blocking)
    s_scan->start(0, nullptr, false);
    Serial.println("[BLE] scan started");
}

bool bt_scan_found() {
    return s_found;
}

void bt_connect() {
    if (!s_target) return;

    Serial.printf("[BLE] connecting to %s\n", s_target->getAddress().toString().c_str());

    s_client = BLEDevice::createClient();
    s_client->setClientCallbacks(new ClientCallback());

    if (!s_client->connect(s_target)) {
        Serial.println("[BLE] connect failed");
        delete s_client;
        s_client    = nullptr;
        s_connected = false;
        return;
    }
    Serial.println("[BLE] connected");

    BLERemoteService* svc = s_client->getService(BLEUUID(UUID_SERVICE));
    if (!svc) {
        Serial.println("[BLE] service not found on device");
        s_client->disconnect();
        s_connected = false;
        return;
    }
    Serial.println("[BLE] service found");

    s_challengeChar = svc->getCharacteristic(BLEUUID(UUID_CHALLENGE));
    s_responseChar  = svc->getCharacteristic(BLEUUID(UUID_RESPONSE));
    s_statusChar    = svc->getCharacteristic(BLEUUID(UUID_STATUS));

    Serial.printf("[BLE] characteristics: challenge=%s response=%s status=%s\n",
                  s_challengeChar ? "OK" : "MISSING",
                  s_responseChar  ? "OK" : "MISSING",
                  s_statusChar    ? "OK" : "MISSING");

    if (s_responseChar && s_responseChar->canNotify()) {
        s_responseChar->registerForNotify(onResponseNotify);
        Serial.println("[BLE] subscribed to response notifications");
    } else {
        Serial.println("[BLE] WARNING: response char missing or cannot notify");
    }

    // s_connected is set true by ClientCallback::onConnect, but connect()
    // is synchronous so it's already set by now.
}

bool bt_connected() {
    return s_connected && s_client && s_client->isConnected();
}

void bt_disconnect() {
    if (s_client) {
        s_client->disconnect();
        // client is managed by BLEDevice; don't delete
        s_client    = nullptr;
        s_connected = false;
    }
    s_challengeChar = nullptr;
    s_responseChar  = nullptr;
    s_statusChar    = nullptr;
}

void bt_send_challenge(const uint8_t* nonce, uint8_t len) {
    if (!s_challengeChar) return;
    // response=true: ESP-IDF automatically uses Prepare Write + Execute Write
    // for payloads > MTU-3, so the full 60-byte packet arrives as one unit on
    // iOS regardless of the negotiated MTU.
    s_challengeChar->writeValue(const_cast<uint8_t*>(nonce), len,
                                /*response=*/true);
    Serial.printf("[BLE] challenge write-with-response sent (%d bytes)\n", len);
}

bool bt_response_ready() {
    return s_response_ready;
}

void bt_read_response(uint8_t* buf, uint8_t len) {
    uint8_t copy = (len < SESSION_PACKET_LEN) ? len : SESSION_PACKET_LEN;
    memcpy(buf, s_response_buf, copy);
    s_response_ready = false;
}

void bt_notify_status(uint8_t status) {
    if (!s_statusChar) return;
    s_statusChar->writeValue(&status, 1, /*response=*/false);
}
