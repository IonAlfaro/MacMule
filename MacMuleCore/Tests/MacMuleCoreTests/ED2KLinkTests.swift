import XCTest
@testable import MacMuleCore

final class ED2KLinkTests: XCTestCase {
    func testParsesFileLink() throws {
        let link = try ED2KLinkParser.parseFileLink(
            "ed2k://|file|Ubuntu%2026.04%20Desktop.iso|5812142080|A41D8CD98F00B204E9800998ECF8427E|/"
        )

        XCTAssertEqual(link.fileName, "Ubuntu 26.04 Desktop.iso")
        XCTAssertEqual(link.sizeInBytes, 5_812_142_080)
        XCTAssertEqual(link.hash, "A41D8CD98F00B204E9800998ECF8427E")
        XCTAssertNil(link.rootHash)
    }

    func testParsesOptionalRootHash() throws {
        let link = try ED2KLinkParser.parseFileLink(
            "ed2k://|file|Sample.zip|1024|0CC175B9C0F1B6A831C399E269772661|h=900150983CD24FB0D6963F7D28E17F72|/"
        )

        XCTAssertEqual(link.rootHash, "900150983CD24FB0D6963F7D28E17F72")
    }

    func testParsesPartHashes() throws {
        let link = try ED2KLinkParser.parseFileLink(
            "ed2k://|file|Sample.zip|2048|0CC175B9C0F1B6A831C399E269772661|p=900150983CD24FB0D6963F7D28E17F72:d41d8cd98f00b204e9800998ecf8427e|h=A41D8CD98F00B204E9800998ECF8427E|/"
        )

        XCTAssertEqual(
            link.partHashes,
            [
                "900150983CD24FB0D6963F7D28E17F72",
                "D41D8CD98F00B204E9800998ECF8427E"
            ]
        )
        XCTAssertEqual(link.rootHash, "A41D8CD98F00B204E9800998ECF8427E")
    }

    func testRejectsInvalidScheme() {
        XCTAssertThrowsError(try ED2KLinkParser.parseFileLink("https://example.com/file")) { error in
            XCTAssertEqual(error as? ED2KLinkParseError, .invalidScheme)
        }
    }

    func testRejectsUnsupportedKind() {
        XCTAssertThrowsError(try ED2KLinkParser.parseFileLink("ed2k://|server|127.0.0.1|4661|/")) { error in
            XCTAssertEqual(error as? ED2KLinkParseError, .unsupportedLinkKind("server"))
        }
    }

    func testRejectsInvalidSize() {
        XCTAssertThrowsError(
            try ED2KLinkParser.parseFileLink("ed2k://|file|Sample.zip|zero|0CC175B9C0F1B6A831C399E269772661|/")
        ) { error in
            XCTAssertEqual(error as? ED2KLinkParseError, .invalidSize("zero"))
        }
    }

    func testRejectsInvalidHash() {
        XCTAssertThrowsError(try ED2KLinkParser.parseFileLink("ed2k://|file|Sample.zip|1024|not-a-hash|/")) { error in
            XCTAssertEqual(error as? ED2KLinkParseError, .invalidHash("not-a-hash"))
        }
    }

    func testRejectsInvalidPartHash() {
        XCTAssertThrowsError(
            try ED2KLinkParser.parseFileLink(
                "ed2k://|file|Sample.zip|1024|0CC175B9C0F1B6A831C399E269772661|p=not-a-part-hash|/"
            )
        ) { error in
            XCTAssertEqual(error as? ED2KLinkParseError, .invalidHash("not-a-part-hash"))
        }
    }

    func testBuildsCanonicalURL() throws {
        let link = ED2KFileLink(
            fileName: "Sample File.zip",
            sizeInBytes: 1024,
            hash: "0cc175b9c0f1b6a831c399e269772661"
        )

        XCTAssertEqual(
            link.canonicalURL,
            "ed2k://|file|Sample%20File.zip|1024|0CC175B9C0F1B6A831C399E269772661|/"
        )
    }

    func testBuildsCanonicalURLWithPartHashes() throws {
        let link = ED2KFileLink(
            fileName: "Sample File.zip",
            sizeInBytes: 1024,
            hash: "0cc175b9c0f1b6a831c399e269772661",
            rootHash: "900150983cd24fb0d6963f7d28e17f72",
            partHashes: [
                "a41d8cd98f00b204e9800998ecf8427e",
                "d41d8cd98f00b204e9800998ecf8427e"
            ]
        )

        XCTAssertEqual(
            link.canonicalURL,
            "ed2k://|file|Sample%20File.zip|1024|0CC175B9C0F1B6A831C399E269772661|p=A41D8CD98F00B204E9800998ECF8427E:D41D8CD98F00B204E9800998ECF8427E|h=900150983CD24FB0D6963F7D28E17F72|/"
        )
    }
}
