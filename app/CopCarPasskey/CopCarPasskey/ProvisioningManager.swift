import Foundation
import NetworkExtension

@MainActor
final class ProvisioningManager: ObservableObject {
    enum State: Equatable {
        case idle
        case connectingToAP
        case sending
        case success
        case failed(String)
    }

    @Published var state: State = .idle

    func provision(secret: Data) async {
        state = .connectingToAP
        do {
            // Ask iOS to join the ESP32 provisioning AP.
            // joinOnce = true means iOS removes the config automatically when done.
            let config = NEHotspotConfiguration(
                ssid: ProvisioningConstants.ssid,
                passphrase: ProvisioningConstants.password,
                isWEP: false)
            config.joinOnce = true
            try await NEHotspotConfigurationManager.shared.apply(config)

            state = .sending

            // Encrypt the 32-byte secret with the session AES key (same key used for BLE)
            let encrypted = try SessionCrypto.encrypt(secret)

            var request = URLRequest(
                url: URL(string: ProvisioningConstants.url)!,
                timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            request.httpBody = encrypted.base64EncodedData()

            let (_, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw ProvisioningError.badResponse
            }

            // Remove the AP config so iOS reconnects to its normal network
            NEHotspotConfigurationManager.shared
                .removeConfiguration(forSSID: ProvisioningConstants.ssid)

            state = .success
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reset() { state = .idle }

    private enum ProvisioningError: LocalizedError {
        case badResponse
        var errorDescription: String? { "Device returned an unexpected response." }
    }
}
