import Foundation
import Security

/// Thread-safe read/write of the 32-byte shared secret in the iOS Keychain.
/// The label is stored alongside the secret as kSecAttrLabel so both
/// survive app reinstall and sync to iCloud Keychain together.
enum SecretStore {
    static func save(_ secret: Data, label: String) throws {
        let deleteQuery: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        KeychainKeys.sharedSecret,
            kSecAttrSynchronizable: kCFBooleanTrue!
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        KeychainKeys.sharedSecret,
            kSecAttrLabel:          label,
            kSecValueData:          secret,
            kSecAttrAccessible:     kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable: kCFBooleanTrue!
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Returns the secret bytes only. Used by PasskeyPeripheral during BLE auth.
    static func load() -> Data? {
        loadEntry()?.secret
    }

    /// Returns both the secret and the enrolled label. Used by EnrollmentManager
    /// and WatchSyncManager so the label survives reinstalls via iCloud Keychain.
    static func loadEntry() -> (secret: Data, label: String)? {
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        KeychainKeys.sharedSecret,
            kSecAttrSynchronizable: kCFBooleanTrue!,
            kSecReturnData:         true,
            kSecReturnAttributes:   true,
            kSecMatchLimit:         kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let dict   = result as? [CFString: Any],
              let secret = dict[kSecValueData] as? Data else { return nil }
        let label = dict[kSecAttrLabel] as? String ?? ""
        return (secret, label)
    }

    static func delete() {
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        KeychainKeys.sharedSecret,
            kSecAttrSynchronizable: kCFBooleanTrue!
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case saveFailed(OSStatus)
    }
}
