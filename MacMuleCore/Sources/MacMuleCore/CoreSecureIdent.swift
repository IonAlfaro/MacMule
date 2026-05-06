import Foundation
import CryptoKit

public final class CoreSecureIdent: @unchecked Sendable {
    private let privateKey: Curve25519.Signing.PrivateKey
    public let publicKeyData: Data
    
    public init() {
        self.privateKey = Curve25519.Signing.PrivateKey()
        self.publicKeyData = privateKey.publicKey.rawRepresentation
    }
    
    public init(privateKeyData: Data) throws {
        self.privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
        self.publicKeyData = privateKey.publicKey.rawRepresentation
    }
    
    public func sign(_ data: Data) -> Data {
        try! privateKey.signature(for: Data(SHA256.hash(data: data)))
    }
    
    public static func verify(signature: Data, data: Data, publicKeyData: Data) -> Bool {
        guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            return false
        }
        return publicKey.isValidSignature(signature, for: Data(SHA256.hash(data: data)))
    }
    
    public static func generateKeyPair() -> (privateKey: Data, publicKey: Data) {
        let key = Curve25519.Signing.PrivateKey()
        return (key.rawRepresentation, key.publicKey.rawRepresentation)
    }
    
    public static func computeSharedSecret(privateKeyData: Data, publicKeyData: Data) throws -> Data {
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKeyData)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        return sharedSecret.withUnsafeBytes { Data($0) }
    }
}
