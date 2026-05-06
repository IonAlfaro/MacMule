import Foundation

public enum ED2KHash {
    public static let standardChunkSize: UInt64 = 9_728_000

    public static func hash(data: Data, chunkSize: UInt64 = standardChunkSize) -> String {
        guard UInt64(data.count) > chunkSize else {
            return MD4.hash(data).hexString
        }

        var chunkDigests = Data()
        var offset = 0

        while offset < data.count {
            let endIndex = min(offset + Int(chunkSize), data.count)
            chunkDigests.append(MD4.hash(data.subdata(in: offset..<endIndex)))
            offset = endIndex
        }

        return MD4.hash(chunkDigests).hexString
    }

    public static func hash(fileAt url: URL, chunkSize: UInt64 = standardChunkSize) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer {
            try? fileHandle.close()
        }

        let fileSize = try fileHandle.seekToEnd()
        try fileHandle.seek(toOffset: 0)

        guard fileSize > chunkSize else {
            return try MD4.hash(fileHandle.readToEnd() ?? Data()).hexString
        }

        var chunkDigests = Data()

        while true {
            let chunk = try fileHandle.read(upToCount: Int(chunkSize))
            guard let chunk, chunk.isEmpty == false else {
                break
            }

            chunkDigests.append(MD4.hash(chunk))
        }

        return MD4.hash(chunkDigests).hexString
    }
}

private enum MD4 {
    static func hash(_ data: Data) -> Data {
        var message = data
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)

        while message.count % 64 != 56 {
            message.append(0)
        }

        withUnsafeBytes(of: bitLength.littleEndian) { bytes in
            message.append(contentsOf: bytes)
        }

        var a: UInt32 = 0x67452301
        var b: UInt32 = 0xefcdab89
        var c: UInt32 = 0x98badcfe
        var d: UInt32 = 0x10325476

        for chunkOffset in stride(from: 0, to: message.count, by: 64) {
            let chunk = message[chunkOffset..<(chunkOffset + 64)]
            var words = [UInt32](repeating: 0, count: 16)

            for index in 0..<16 {
                let wordOffset = chunk.index(chunk.startIndex, offsetBy: index * 4)
                words[index] = UInt32(chunk[wordOffset])
                    | (UInt32(chunk[chunk.index(after: wordOffset)]) << 8)
                    | (UInt32(chunk[chunk.index(wordOffset, offsetBy: 2)]) << 16)
                    | (UInt32(chunk[chunk.index(wordOffset, offsetBy: 3)]) << 24)
            }

            let savedA = a
            let savedB = b
            let savedC = c
            let savedD = d

            round1(&a, b, c, d, words[0], 3)
            round1(&d, a, b, c, words[1], 7)
            round1(&c, d, a, b, words[2], 11)
            round1(&b, c, d, a, words[3], 19)
            round1(&a, b, c, d, words[4], 3)
            round1(&d, a, b, c, words[5], 7)
            round1(&c, d, a, b, words[6], 11)
            round1(&b, c, d, a, words[7], 19)
            round1(&a, b, c, d, words[8], 3)
            round1(&d, a, b, c, words[9], 7)
            round1(&c, d, a, b, words[10], 11)
            round1(&b, c, d, a, words[11], 19)
            round1(&a, b, c, d, words[12], 3)
            round1(&d, a, b, c, words[13], 7)
            round1(&c, d, a, b, words[14], 11)
            round1(&b, c, d, a, words[15], 19)

            round2(&a, b, c, d, words[0], 3)
            round2(&d, a, b, c, words[4], 5)
            round2(&c, d, a, b, words[8], 9)
            round2(&b, c, d, a, words[12], 13)
            round2(&a, b, c, d, words[1], 3)
            round2(&d, a, b, c, words[5], 5)
            round2(&c, d, a, b, words[9], 9)
            round2(&b, c, d, a, words[13], 13)
            round2(&a, b, c, d, words[2], 3)
            round2(&d, a, b, c, words[6], 5)
            round2(&c, d, a, b, words[10], 9)
            round2(&b, c, d, a, words[14], 13)
            round2(&a, b, c, d, words[3], 3)
            round2(&d, a, b, c, words[7], 5)
            round2(&c, d, a, b, words[11], 9)
            round2(&b, c, d, a, words[15], 13)

            round3(&a, b, c, d, words[0], 3)
            round3(&d, a, b, c, words[8], 9)
            round3(&c, d, a, b, words[4], 11)
            round3(&b, c, d, a, words[12], 15)
            round3(&a, b, c, d, words[2], 3)
            round3(&d, a, b, c, words[10], 9)
            round3(&c, d, a, b, words[6], 11)
            round3(&b, c, d, a, words[14], 15)
            round3(&a, b, c, d, words[1], 3)
            round3(&d, a, b, c, words[9], 9)
            round3(&c, d, a, b, words[5], 11)
            round3(&b, c, d, a, words[13], 15)
            round3(&a, b, c, d, words[3], 3)
            round3(&d, a, b, c, words[11], 9)
            round3(&c, d, a, b, words[7], 11)
            round3(&b, c, d, a, words[15], 15)

            a = a &+ savedA
            b = b &+ savedB
            c = c &+ savedC
            d = d &+ savedD
        }

        var digest = Data()
        [a, b, c, d].forEach { word in
            withUnsafeBytes(of: word.littleEndian) { bytes in
                digest.append(contentsOf: bytes)
            }
        }
        return digest
    }

    private static func f(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        (x & y) | (~x & z)
    }

    private static func g(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        (x & y) | (x & z) | (y & z)
    }

    private static func h(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 {
        x ^ y ^ z
    }

    private static func round1(_ a: inout UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, _ x: UInt32, _ s: UInt32) {
        a = (a &+ f(b, c, d) &+ x).rotatedLeft(by: s)
    }

    private static func round2(_ a: inout UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, _ x: UInt32, _ s: UInt32) {
        a = (a &+ g(b, c, d) &+ x &+ 0x5a827999).rotatedLeft(by: s)
    }

    private static func round3(_ a: inout UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32, _ x: UInt32, _ s: UInt32) {
        a = (a &+ h(b, c, d) &+ x &+ 0x6ed9eba1).rotatedLeft(by: s)
    }
}

private extension UInt32 {
    func rotatedLeft(by amount: UInt32) -> UInt32 {
        (self << amount) | (self >> (32 - amount))
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}
