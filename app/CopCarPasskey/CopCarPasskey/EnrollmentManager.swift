import Foundation

@MainActor
final class EnrollmentManager: ObservableObject {
    @Published private(set) var isEnrolled: Bool = false
    @Published private(set) var enrolledLabel: String = ""
    @Published var enrollmentError: String?

    init() {
        refresh()
    }

    func refresh() {
        isEnrolled   = SecretStore.load() != nil
        enrolledLabel = UserDefaults.standard.string(forKey: "enrolledLabel") ?? ""
    }

    /// Called when the user scans the QR code deep-link.
    /// URL format: CopCarpasskey://enroll?secret=<hex64>&label=<name>
    func enroll(from url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw EnrollmentError.badScheme(url.scheme)
        }
        guard components.scheme == DeepLink.scheme else {
            throw EnrollmentError.badScheme(components.scheme)
        }
        guard components.host == DeepLink.enrollHost else {
            throw EnrollmentError.badHost(components.host)
        }
        guard let secretHex = components.queryItems?.first(where: { $0.name == "secret" })?.value else {
            throw EnrollmentError.missingSecret
        }
        guard let label = components.queryItems?.first(where: { $0.name == "label" })?.value else {
            throw EnrollmentError.missingLabel
        }
        guard let secretData = Data(hexString: secretHex) else {
            throw EnrollmentError.badSecretHex
        }

        do {
            try SecretStore.save(secretData)
        } catch {
            throw EnrollmentError.keychainFailed(error)
        }
        UserDefaults.standard.set(label, forKey: "enrolledLabel")
        refresh()
    }

    func removeKey() {
        SecretStore.delete()
        UserDefaults.standard.removeObject(forKey: "enrolledLabel")
        refresh()
    }

    enum EnrollmentError: LocalizedError {
        case badScheme(String?)
        case badHost(String?)
        case missingSecret
        case missingLabel
        case badSecretHex
        case keychainFailed(Error)

        var errorDescription: String? {
            switch self {
            case .badScheme(let s):   return "Bad URL scheme: \(s ?? "nil") (expected \(DeepLink.scheme))"
            case .badHost(let h):     return "Bad URL host: \(h ?? "nil") (expected \(DeepLink.enrollHost))"
            case .missingSecret:      return "URL missing 'secret' parameter"
            case .missingLabel:       return "URL missing 'label' parameter"
            case .badSecretHex:       return "Secret is not valid hex"
            case .keychainFailed(let e): return "Keychain save failed: \(e.localizedDescription)"
            }
        }
    }
}

private extension Data {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespaces)
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
