import Foundation
import CoreBluetooth
import Combine

/// Runs as a BLE peripheral — advertises the CopCar Passkey service and
/// responds to Arduino challenge-response requests without user interaction.
@MainActor
final class PasskeyPeripheral: NSObject, ObservableObject {
    @Published private(set) var isAdvertising = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var lastEvent: String = "Idle"

    private var manager: CBPeripheralManager!
    private var challengeChar: CBCharacteristic?
    private var responseChar: CBMutableCharacteristic!
    private var statusChar: CBMutableCharacteristic!

    // Chunked response state — notifications are capped at ATT_MTU-3 (20 bytes
    // at default MTU), so we send 60 bytes as 3 x 20-byte chunks.
    private var pendingResponse: Data?
    private var pendingOffset: Int = 0
    private let notifyChunkSize = 20

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .global(qos: .background),
                                      options: [CBPeripheralManagerOptionRestoreIdentifierKey: "com.copcar.passkey.peripheral"])
    }

    func startAdvertising() {
        guard manager.state == .poweredOn else {
            log("startAdvertising called but BT not powered on (state=\(manager.state.rawValue))")
            return
        }
        setupServices()
    }

    func stopAdvertising() {
        manager.stopAdvertising()
        isAdvertising = false
        log("advertising stopped")
    }

    private func setupServices() {
        if manager.isAdvertising {
            manager.stopAdvertising()
            log("stopped stale advertising before reconfiguring")
        }
        manager.removeAllServices()

        responseChar = CBMutableCharacteristic(
            type:       BLEConstants.responseUUID,
            properties: [.notify],
            value:      nil,
            permissions: .readable)

        statusChar = CBMutableCharacteristic(
            type:       BLEConstants.statusUUID,
            properties: [.writeWithoutResponse],
            value:      nil,
            permissions: .writeable)

        // CHALLENGE: Arduino writes here using write-with-response so the
        // ESP-IDF stack can fragment payloads > MTU-3 via Prepare Write.
        let challengeChar = CBMutableCharacteristic(
            type:       BLEConstants.challengeUUID,
            properties: [.write],
            value:      nil,
            permissions: .writeable)

        let service = CBMutableService(type: BLEConstants.serviceUUID, primary: true)
        service.characteristics = [challengeChar, responseChar, statusChar]
        manager.add(service)
        log("service added, waiting for BLE stack confirmation")
    }

    private func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("[PasskeyPeripheral \(ts)] \(msg)")
    }
}

extension PasskeyPeripheral: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ p: CBPeripheralManager) {
        let stateName: String
        switch p.state {
        case .poweredOn:  stateName = "poweredOn"
        case .poweredOff: stateName = "poweredOff"
        case .resetting:  stateName = "resetting"
        case .unauthorized: stateName = "unauthorized"
        case .unsupported:  stateName = "unsupported"
        case .unknown:    stateName = "unknown"
        @unknown default: stateName = "unknown(\(p.state.rawValue))"
        }
        Task { @MainActor in
            log("BT state → \(stateName)")
            if p.state == .poweredOn { startAdvertising() }
        }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        Task { @MainActor in
            if let err = error {
                log("didAdd service ERROR: \(err.localizedDescription)")
                return
            }
            log("service registered OK — starting advertising")
            p.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [BLEConstants.serviceUUID],
                CBAdvertisementDataLocalNameKey: "CopCarPasskey"
            ])
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ p: CBPeripheralManager, error: Error?) {
        Task { @MainActor in
            if let err = error {
                log("advertising start ERROR: \(err.localizedDescription)")
                isAdvertising = false
            } else {
                log("advertising started")
                isAdvertising = true
            }
        }
    }

    // Device connected and subscribed to the response notify characteristic
    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       central: CBCentral,
                                       didSubscribeTo characteristic: CBCharacteristic) {
        Task { @MainActor in
            log("central \(central.identifier) subscribed to \(characteristic.uuid)")
            lastEvent = "Device connected"
        }
    }

    // Device unsubscribed (disconnected)
    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       central: CBCentral,
                                       didUnsubscribeFrom characteristic: CBCharacteristic) {
        Task { @MainActor in
            log("central \(central.identifier) unsubscribed from \(characteristic.uuid)")
            isAuthenticating = false
            lastEvent = "Device disconnected"
        }
    }

    // Arduino wrote a challenge to the CHALLENGE characteristic
    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       didReceiveWrite requests: [CBATTRequest]) {
        Task { @MainActor in
            log("didReceiveWrite: \(requests.count) request(s)")
            for (i, request) in requests.enumerated() {
                let uuid  = request.characteristic.uuid
                let count = request.value?.count ?? -1
                log("  request[\(i)]: uuid=\(uuid) valueLen=\(count)")

                guard uuid == BLEConstants.challengeUUID else {
                    log("  → wrong characteristic UUID, skipping")
                    p.respond(to: request, withResult: .requestNotSupported)
                    continue
                }
                guard let nonce = request.value, nonce.count == 60 else {
                    log("  → bad payload: value=\(request.value?.count ?? -1) bytes (need 60)")
                    p.respond(to: request, withResult: .attributeNotLong)
                    continue
                }
                // Acknowledge the write before processing so the ESP32 isn't
                // blocked waiting for the ATT response.
                p.respond(to: request, withResult: .success)
                log("  → challenge OK (\(nonce.count) bytes): \(nonce.hexString)")
                handleChallenge(nonce, peripheral: p)
            }
        }
    }

    nonisolated func peripheralManagerIsReady(toUpdateSubscribers p: CBPeripheralManager) {
        Task { @MainActor in
            guard pendingResponse != nil else { return }
            log("transmit queue ready — resuming from offset \(pendingOffset)")
            sendNextChunk(peripheral: p)
        }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       willRestoreState dict: [String: Any]) {
        Task { @MainActor in log("willRestoreState") }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       didReceiveRead request: CBATTRequest) {}

    // MARK: – Auth logic

    @MainActor
    private func handleChallenge(_ encPacket: Data, peripheral: CBPeripheralManager) {
        isAuthenticating = true
        lastEvent = "Authenticating…"

        guard let secret = SecretStore.load() else {
            log("ERROR: no secret in keychain — cannot authenticate")
            isAuthenticating = false
            lastEvent = "No key enrolled"
            return
        }
        log("secret loaded from keychain (\(secret.count) bytes)")

        guard let plainNonce = try? SessionCrypto.decrypt(encPacket) else {
            log("ERROR: SessionCrypto.decrypt failed — key mismatch or corrupted packet")
            isAuthenticating = false
            lastEvent = "Decryption failed"
            return
        }
        log("nonce decrypted (\(plainNonce.count) bytes): \(plainNonce.hexString)")

        let mac = HMACAuth.response(for: plainNonce, secret: secret)
        log("HMAC computed (\(mac.count) bytes): \(mac.hexString)")

        guard let encResponse = try? SessionCrypto.encrypt(mac) else {
            log("ERROR: SessionCrypto.encrypt failed")
            isAuthenticating = false
            lastEvent = "Encrypt failed"
            return
        }
        log("response encrypted (\(encResponse.count) bytes): \(encResponse.hexString)")

        sendResponse(encResponse, peripheral: peripheral)
        isAuthenticating = false
        lastEvent = "Response sent – \(Date().formatted(date: .omitted, time: .shortened))"
    }

    @MainActor
    private func sendResponse(_ data: Data, peripheral: CBPeripheralManager) {
        let total = (data.count + notifyChunkSize - 1) / notifyChunkSize
        log("sending response: \(data.count) bytes in \(total) chunk(s) of ≤\(notifyChunkSize)")
        pendingResponse = data
        pendingOffset   = 0
        sendNextChunk(peripheral: peripheral)
    }

    // Sends one chunk, then schedules the next after a short delay so the BLE
    // stack has time to actually transmit before we queue another notification.
    @MainActor
    private func sendNextChunk(peripheral: CBPeripheralManager) {
        guard let data = pendingResponse else { return }
        let off = pendingOffset
        guard off < data.count else {
            log("all chunks sent (\(data.count) bytes total)")
            pendingResponse = nil
            pendingOffset   = 0
            return
        }

        let end   = min(off + notifyChunkSize, data.count)
        let chunk = data[off..<end]
        let ok    = peripheral.updateValue(Data(chunk), for: responseChar, onSubscribedCentrals: nil)

        if !ok {
            log("WARNING: queue full at offset \(off) — will retry when ready")
            // pendingOffset stays; peripheralManagerIsReady will call sendNextChunk
            return
        }

        log("chunk sent: bytes \(off)–\(end - 1) [\(end - off) bytes]")
        pendingOffset = end

        // Wait 50 ms before sending the next chunk so the BLE stack drains the
        // current notification out over the air before we queue another.
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            await MainActor.run { self.sendNextChunk(peripheral: peripheral) }
        }
    }
}

// MARK: – Hex helper

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
