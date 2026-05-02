#include "BluetoothManager.h"
#include "Config.h"
#include <BLEDevice.h>
#include <BLEScan.h>
#include <BLEClient.h>
#include <BLERemoteCharacteristic.h>
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

// ── Callbacks ─────────────────────────────────────────────────────

class ScanCallback : public BLEAdvertisedDeviceCallbacks {
    void onResult(BLEAdvertisedDevice dev) override {
        if (s_found) return;
        if (!dev.haveServiceUUID()) return;
        if (!dev.isAdvertisingService(BLEUUID(UUID_SERVICE))) return;
        if (dev.getRSSI() < RSSI_THRESHOLD) return;

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
    if (len == SESSION_PACKET_LEN) {
        memcpy(s_response_buf, data, SESSION_PACKET_LEN);
        s_response_ready = true;
    }
}

// ── Public API ────────────────────────────────────────────────────

void bt_init() {
    BLEDevice::init("CopCarLock");

    s_scan = BLEDevice::getScan();
    s_scan->setAdvertisedDeviceCallbacks(new ScanCallback());
    s_scan->setActiveScan(true);
    s_scan->setInterval(100);   // ms
    s_scan->setWindow(99);      // must be <= interval
}

void bt_scan_start() {
    s_found          = false;
    s_connected      = false;
    s_response_ready = false;

    if (s_target) { delete s_target; s_target = nullptr; }
    if (s_client) { s_client->disconnect(); s_client = nullptr; }

    s_scan->clearResults();
    // duration=0 → scan until stopped by callback; async (non-blocking)
    s_scan->start(0, nullptr, false);
}

bool bt_scan_found() {
    return s_found;
}

void bt_connect() {
    if (!s_target) return;

    s_client = BLEDevice::createClient();
    s_client->setClientCallbacks(new ClientCallback());

    if (!s_client->connect(s_target)) {
        delete s_client;
        s_client    = nullptr;
        s_connected = false;
        return;
    }

    BLERemoteService* svc = s_client->getService(BLEUUID(UUID_SERVICE));
    if (!svc) {
        s_client->disconnect();
        s_connected = false;
        return;
    }

    s_challengeChar = svc->getCharacteristic(BLEUUID(UUID_CHALLENGE));
    s_responseChar  = svc->getCharacteristic(BLEUUID(UUID_RESPONSE));
    s_statusChar    = svc->getCharacteristic(BLEUUID(UUID_STATUS));

    if (s_responseChar && s_responseChar->canNotify())
        s_responseChar->registerForNotify(onResponseNotify);

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
    // writeValue takes non-const ptr; safe to cast — value is copied internally
    s_challengeChar->writeValue(const_cast<uint8_t*>(nonce), len,
                                /*response=*/false);
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
