import Foundation
import CryptoKit

enum SessionCrypto {
    // Derived once at first use — ECDH(ios_private, esp32_public), then SHA-256.
    // Matches session_init() in SessionCrypto.cpp on the ESP32 side.
    static let aesKey: SymmetricKey = {
        let iosPriv = try! Curve25519.KeyAgreement.PrivateKey(
            rawRepresentation: Data(SessionKeys.iosPrivateKeyBytes))
        let esp32Pub = try! Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: Data(SessionKeys.esp32PublicKeyBytes))
        let shared = try! iosPriv.sharedSecretFromKeyAgreement(with: esp32Pub)
        // SHA-256(shared_bytes) — same derivation as ESP32 mbedtls_sha256()
        let keyBytes = shared.withUnsafeBytes { SHA256.hash(data: Data($0)) }
        return SymmetricKey(data: keyBytes)
    }()

    // Encrypt 32 bytes → 60-byte packet: [12-byte nonce][32-byte ciphertext][16-byte tag]
    static func encrypt(_ plain: Data) throws -> Data {
        let box = try AES.GCM.seal(plain, using: aesKey)
        let iv  = box.nonce.withUnsafeBytes { Data($0) }
        return iv + box.ciphertext + box.tag
    }

    // Decrypt a 60-byte packet → 32 bytes of plaintext.
    // Throws if the packet is malformed or the GCM tag fails (tampered/wrong key).
    static func decrypt(_ packet: Data) throws -> Data {
        guard packet.count == 60 else { throw CryptoError.badLength }
        let nonce  = try AES.GCM.Nonce(data: packet[..<12])
        let box    = try AES.GCM.SealedBox(nonce: nonce,
                                            ciphertext: packet[12..<44],
                                            tag: packet[44...])
        return try AES.GCM.open(box, using: aesKey)
    }

    enum CryptoError: Error { case badLength }
}
