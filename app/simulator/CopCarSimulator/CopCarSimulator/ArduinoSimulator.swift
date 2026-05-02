import Foundation
import Combine
import CoreBluetooth

@MainActor
final class ArduinoSimulator: NSObject, ObservableObject {
    @Published var status: SimStatus = .idle
    @Published var eventLog: [LogEntry] = []
    var sharedSecret: Data = Data()

    enum SimStatus: Equatable {
        case idle
        case bluetoothUnavailable
        case scanning
        case connecting(String)
        case authenticating
        case unlocked
        case authFailed(String)

        var isIdle: Bool {
            switch self {
            case .idle, .unlocked, .authFailed: return true
            default: return false
            }
        }
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let time: String
        let message: String
    }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var challengeChar: CBCharacteristic?
    private var responseChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?
    private var pendingNonce: Data?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func triggerAuth() {
        guard status.isIdle else { return }
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        clearPeripheral()
        guard central.state == .poweredOn else {
            status = .bluetoothUnavailable
            log("Bluetooth not available")
            return
        }
        status = .scanning
        log("Scanning for CopCarPasskey…")
        central.scanForPeripherals(withServices: [BLEConstants.serviceUUID])
    }

    func reset() {
        central.stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        clearPeripheral()
        status = .idle
        log("Reset")
    }

    private func clearPeripheral() {
        peripheral = nil
        challengeChar = nil
        responseChar = nil
        statusChar = nil
        pendingNonce = nil
    }

    private func sendChallenge() {
        guard let p = peripheral, let char = challengeChar else { return }
        let nonce = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        pendingNonce = nonce
        guard let packet = try? SessionCrypto.encrypt(nonce) else {
            log("Encryption failed")
            status = .authFailed("Encryption failed")
            return
        }
        log("Sending challenge (\(packet.count)-byte encrypted packet)")
        status = .authenticating
        p.writeValue(packet, for: char, type: .withoutResponse)
    }

    func log(_ message: String) {
        let ts = Date().formatted(date: .omitted, time: .shortened)
        eventLog.insert(LogEntry(time: ts, message: message), at: 0)
    }
}

extension ArduinoSimulator: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:  log("Bluetooth ready")
            case .poweredOff: status = .bluetoothUnavailable; log("Bluetooth is off")
            default:          status = .bluetoothUnavailable; log("Bluetooth unavailable (\(central.state.rawValue))")
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        Task { @MainActor in
            central.stopScan()
            self.peripheral = peripheral
            peripheral.delegate = self
            let name = peripheral.name ?? "Unknown"
            log("Found: \(name) (RSSI \(RSSI) dBm)")
            status = .connecting(name)
            central.connect(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            log("Connected — discovering services…")
            peripheral.discoverServices([BLEConstants.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            log("Connection failed: \(error?.localizedDescription ?? "unknown")")
            status = .authFailed("Connection failed")
            clearPeripheral()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            if case .authenticating = status {
                log("Disconnected during auth")
                status = .authFailed("Disconnected")
            } else {
                log("Disconnected")
            }
            clearPeripheral()
        }
    }
}

extension ArduinoSimulator: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard error == nil, let services = peripheral.services else {
                log("Service discovery failed: \(error?.localizedDescription ?? "none")")
                status = .authFailed("Service discovery failed")
                return
            }
            for service in services where service.uuid == BLEConstants.serviceUUID {
                log("Found CopCar service — discovering characteristics…")
                peripheral.discoverCharacteristics(
                    [BLEConstants.challengeUUID, BLEConstants.responseUUID, BLEConstants.statusUUID],
                    for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        Task { @MainActor in
            guard error == nil, let chars = service.characteristics else {
                log("Characteristic discovery failed: \(error?.localizedDescription ?? "none")")
                status = .authFailed("Characteristic discovery failed")
                return
            }
            for char in chars {
                switch char.uuid {
                case BLEConstants.challengeUUID:
                    challengeChar = char
                    log("Found CHALLENGE characteristic")
                case BLEConstants.responseUUID:
                    responseChar = char
                    log("Found RESPONSE characteristic — subscribing…")
                    peripheral.setNotifyValue(true, for: char)
                case BLEConstants.statusUUID:
                    statusChar = char
                    log("Found STATUS characteristic")
                default:
                    break
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor in
            guard error == nil else {
                log("Subscription failed: \(error!.localizedDescription)")
                status = .authFailed("Subscription failed")
                return
            }
            if characteristic.uuid == BLEConstants.responseUUID && characteristic.isNotifying {
                log("Subscribed to RESPONSE — sending challenge…")
                sendChallenge()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor in
            guard error == nil,
                  characteristic.uuid == BLEConstants.responseUUID,
                  let packet = characteristic.value else { return }

            guard let nonce = pendingNonce else {
                log("Got RESPONSE but no pending nonce — ignoring")
                return
            }
            pendingNonce = nil

            guard let plainResponse = try? SessionCrypto.decrypt(packet) else {
                log("Failed to decrypt RESPONSE packet")
                status = .authFailed("Decryption failed")
                writeStatus(0x00, to: peripheral)
                return
            }

            guard !sharedSecret.isEmpty else {
                log("No shared secret configured — cannot verify HMAC")
                status = .authFailed("No secret")
                writeStatus(0x00, to: peripheral)
                return
            }

            let valid = HMACAuth.verify(nonce: nonce, response: plainResponse, secret: sharedSecret)
            if valid {
                log("HMAC verified — UNLOCKED!")
                status = .unlocked
                writeStatus(0x01, to: peripheral)
            } else {
                log("HMAC mismatch — authentication FAILED")
                status = .authFailed("HMAC mismatch")
                writeStatus(0x00, to: peripheral)
            }
        }
    }

    private func writeStatus(_ byte: UInt8, to peripheral: CBPeripheral) {
        guard let char = statusChar else { return }
        peripheral.writeValue(Data([byte]), for: char, type: .withoutResponse)
        log("Wrote STATUS = 0x\(String(byte, radix: 16, uppercase: true)) to peripheral")
    }
}
