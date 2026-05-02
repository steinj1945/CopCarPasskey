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
        let entry = SecretStore.loadEntry()
        isEnrolled    = entry != nil
        enrolledLabel = entry?.label ?? ""
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
            try SecretStore.save(secretData, label: label)
        } catch {
            throw EnrollmentError.keychainFailed(error)
        }
        refresh()
    }

    func removeKey() {
        SecretStore.delete()
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
