import Foundation
import CommonCrypto

public final class CoreObfuscationLayer: @unchecked Sendable {
    private var cryptor: CCCryptorRef?
    private let lock = NSLock()
    
    public init() {}
    
    public func startEncryption(key: Data) {
        lock.lock()
        defer { lock.unlock() }
        _ = createCryptor(operation: CCOperation(kCCEncrypt), key: key)
    }
    
    public func startDecryption(key: Data) {
        lock.lock()
        defer { lock.unlock() }
        _ = createCryptor(operation: CCOperation(kCCDecrypt), key: key)
    }
    
    public func process(_ data: Data) -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard let cryptor = cryptor else { return data }
        
        var outputLength = data.count
        var output = Data(count: outputLength)
        
        _ = output.withUnsafeMutableBytes { outputBuf in
            data.withUnsafeBytes { inputBuf in
                CCCryptorUpdate(cryptor, inputBuf.baseAddress, data.count,
                               outputBuf.baseAddress, outputLength, &outputLength)
            }
        }
        
        return output
    }
    
    public func processInPlace(_ data: inout Data) {
        data = process(data)
    }
    
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        if let cryptor = cryptor {
            CCCryptorRelease(cryptor)
            self.cryptor = nil
        }
    }
    
    deinit {
        if let cryptor = cryptor {
            CCCryptorRelease(cryptor)
        }
    }
    
    private func createCryptor(operation: CCOperation, key: Data) -> CCCryptorStatus {
        if let existing = cryptor {
            CCCryptorRelease(existing)
        }
        
        var cryptor: CCCryptorRef?
        let status = key.withUnsafeBytes { keyBuf in
            CCCryptorCreate(operation, CCAlgorithm(kCCAlgorithmRC4), CCOptions(0),
                          keyBuf.baseAddress, key.count, nil, &cryptor)
        }
        self.cryptor = cryptor
        return status
    }
}

// MARK: - eMule protocol obfuscation support

public extension CoreObfuscationLayer {
    static func createObfuscationKey(userHash: Data, challenge: Data) -> Data {
        var key = Data()
        key.append(userHash)
        key.append(challenge)
        // RC4 key derivation per eMule spec: MD4(userHash + challenge)
        let md4 = MD4Hash(key)
        return md4
    }
}

private func MD4Hash(_ data: Data) -> Data {
    var message = data
    let bitLength = UInt64(message.count) * 8
    message.append(0x80)
    while message.count % 64 != 56 {
        message.append(0)
    }
    message.append(contentsOf: withUnsafeBytes(of: bitLength.littleEndian) { Data($0) })
    
    var h0: UInt32 = 0x67452301
    var h1: UInt32 = 0xEFCDAB89
    var h2: UInt32 = 0x98BADCFE
    var h3: UInt32 = 0x10325476
    
    message.withUnsafeBytes { buf in
        let words = buf.bindMemory(to: UInt32.self)
        for chunkStart in stride(from: 0, to: words.count, by: 16) {
            var x = [UInt32](repeating: 0, count: 16)
            for j in 0..<16 {
                x[j] = words[chunkStart + j].littleEndian
            }
            
            var a = h0, b = h1, c = h2, d = h3
            let s: [UInt32] = [3, 7, 11, 19]
            
            for j in 0..<16 {
                let k = j % 4
                let f: UInt32
                if j < 4 {
                    f = (b & c) | (~b & d)
                } else if j < 8 {
                    f = (b & c) | (b & d) | (c & d)
                } else if j < 12 {
                    f = b ^ c ^ d
                } else {
                    f = c ^ (b | ~d)
                }
                a = a &+ f &+ x[j]
                let shift = s[k]
                a = (a << shift) | (a >> (32 - shift))
                (a, b, c, d) = (d, a, b, c)
            }
            
            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
        }
    }
    
    var result = Data(count: 16)
    result.withUnsafeMutableBytes { buf in
        let ptr = buf.bindMemory(to: UInt32.self)
        ptr[0] = h0.littleEndian
        ptr[1] = h1.littleEndian
        ptr[2] = h2.littleEndian
        ptr[3] = h3.littleEndian
    }
    return result
}
