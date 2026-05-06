import Foundation
import XCTest
@testable import MacMuleCore

final class ED2KHashTests: XCTestCase {
    func testMD4VectorsUsedByED2KSmallFiles() {
        XCTAssertEqual(ED2KHash.hash(data: Data()), "31D6CFE0D16AE931B73C59D7E0C089C0")
        XCTAssertEqual(ED2KHash.hash(data: Data("a".utf8)), "BDE52CB31DE33E46245E05FBDBD6FB24")
        XCTAssertEqual(ED2KHash.hash(data: Data("abc".utf8)), "A448017AAF21D8525FC10AE87AA6729D")
    }

    func testFileHashMatchesDataHash() throws {
        let data = Data("MacMule".utf8)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacMuleHashTest-\(UUID().uuidString)")
        try data.write(to: fileURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }

        XCTAssertEqual(try ED2KHash.hash(fileAt: fileURL), ED2KHash.hash(data: data))
    }
}
