import Foundation
import CoreBluetooth
import Combine

/// Runs as a BLE peripheral — advertises the CopCar Passkey service and
/// responds to Arduino challenge-response requests without user interaction.
@MainActor
final class PasskeyPeripheral: NSObject, ObservableObject {
    @Published private(set) var isAdvertising = false
    @Published private(set) var lastEvent: String = "Idle"

    private var manager: CBPeripheralManager!
    private var challengeChar: CBCharacteristic?
    private var responseChar: CBMutableCharacteristic!
    private var statusChar: CBMutableCharacteristic!

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .global(qos: .background),
                                      options: [CBPeripheralManagerOptionRestoreIdentifierKey: "com.copcar.passkey.peripheral"])
    }

    func startAdvertising() {
        guard manager.state == .poweredOn else { return }
        setupServices()
    }

    func stopAdvertising() {
        manager.stopAdvertising()
        isAdvertising = false
    }

    private func setupServices() {
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

        // CHALLENGE: Arduino writes here (we subscribe to be notified)
        let challengeChar = CBMutableCharacteristic(
            type:       BLEConstants.challengeUUID,
            properties: [.writeWithoutResponse],
            value:      nil,
            permissions: .writeable)

        let service = CBMutableService(type: BLEConstants.serviceUUID, primary: true)
        service.characteristics = [challengeChar, responseChar, statusChar]
        manager.add(service)
    }
}

extension PasskeyPeripheral: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ p: CBPeripheralManager) {
        if p.state == .poweredOn {
            Task { @MainActor in startAdvertising() }
        }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else { return }
        p.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLEConstants.serviceUUID],
            CBAdvertisementDataLocalNameKey: "CopCarPasskey"
        ])
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ p: CBPeripheralManager, error: Error?) {
        Task { @MainActor in isAdvertising = error == nil }
    }

    // Arduino wrote a challenge to the CHALLENGE characteristic
    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard request.characteristic.uuid == BLEConstants.challengeUUID,
                  let nonce = request.value,
                  nonce.count == 60 else { continue }

            Task { @MainActor in handleChallenge(nonce, peripheral: p) }
        }
    }

    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       willRestoreState dict: [String: Any]) {
        // State restoration after app is killed and relaunched by iOS BT subsystem
    }

    @MainActor
    private func handleChallenge(_ encPacket: Data, peripheral: CBPeripheralManager) {
        guard let secret = SecretStore.load() else {
            lastEvent = "No key enrolled"
            return
        }
        guard let plainNonce = try? SessionCrypto.decrypt(encPacket) else {
            lastEvent = "Decryption failed"
            return
        }
        let mac = HMACAuth.response(for: plainNonce, secret: secret)
        guard let encResponse = try? SessionCrypto.encrypt(mac) else { return }
        peripheral.updateValue(encResponse, for: responseChar, onSubscribedCentrals: nil)
        lastEvent = "Challenge answered – \(Date().formatted(date: .omitted, time: .shortened))"
    }

    // Arduino sent a STATUS notification (0x01 = unlocked, 0x00 = locked)
    nonisolated func peripheralManager(_ p: CBPeripheralManager,
                                       didReceiveRead request: CBATTRequest) {}
}
