import Foundation

@MainActor
final class ProvisioningManager: ObservableObject {
    enum State: Equatable {
        case idle
        case waitingForWifi
        case sending
        case success
        case failed(String)
    }

    @Published var state: State = .idle

    func beginProvisioning() {
        state = .waitingForWifi
    }

    func sendKey(secret: Data) async {
        state = .sending
        do {
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
