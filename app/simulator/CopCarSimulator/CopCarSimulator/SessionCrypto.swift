import Foundation
import CryptoKit

enum SessionCrypto {
    // ECDH(iosPriv, esp32Pub) → SHA-256 → AES-GCM key. Identical derivation to the iOS app.
    static let aesKey: SymmetricKey = {
        let iosPriv  = try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(SessionKeys.iosPrivateKeyBytes))
        let esp32Pub = try! Curve25519.KeyAgreement.PublicKey(rawRepresentation: Data(SessionKeys.esp32PublicKeyBytes))
        let shared   = try! iosPriv.sharedSecretFromKeyAgreement(with: esp32Pub)
        let keyBytes = shared.withUnsafeBytes { SHA256.hash(data: Data($0)) }
        return SymmetricKey(data: keyBytes)
    }()

    // 32-byte plaintext → 60-byte packet: [12 IV][32 ciphertext][16 tag]
    static func encrypt(_ plain: Data) throws -> Data {
        let box = try AES.GCM.seal(plain, using: aesKey)
        let iv  = box.nonce.withUnsafeBytes { Data($0) }
        return iv + box.ciphertext + box.tag
    }

    // 60-byte packet → 32-byte plaintext. Throws on bad length or tag mismatch.
    static func decrypt(_ packet: Data) throws -> Data {
        guard packet.count == 60 else { throw CryptoError.badLength }
        let nonce = try AES.GCM.Nonce(data: packet[..<12])
        let box   = try AES.GCM.SealedBox(nonce: nonce, ciphertext: packet[12..<44], tag: packet[44...])
        return try AES.GCM.open(box, using: aesKey)
    }

    enum CryptoError: Error { case badLength }
}
