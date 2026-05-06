import XCTest
@testable import MacMuleCore

final class CoreTransferStoreTests: XCTestCase {
    func testChunkMapSplitsFilesIntoED2KChunks() {
        let chunkSize = CoreChunkMap.ed2kChunkSize
        let chunkMap = CoreChunkMap(fileSizeInBytes: (chunkSize * 2) + 5)

        XCTAssertEqual(chunkMap.chunks.count, 3)
        XCTAssertEqual(chunkMap.chunks[0].length, chunkSize)
        XCTAssertEqual(chunkMap.chunks[1].length, chunkSize)
        XCTAssertEqual(chunkMap.chunks[2].length, 5)
        XCTAssertEqual(chunkMap.chunks.map(\.status), [.missing, .missing, .missing])
    }

    func testWriteBlockUpdatesChunkMapWithoutDoubleCountingOverlap() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|4096|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = snapshot.transfers[0].id

        _ = try store.writeBlock(transferID: id, offset: 0, data: Data(repeating: 1, count: 1024))
        _ = try store.writeBlock(transferID: id, offset: 512, data: Data(repeating: 2, count: 512))
        let record = try store.writeBlock(transferID: id, offset: 1024, data: Data(repeating: 3, count: 512))

        XCTAssertEqual(record.chunkMap.completedBytes, 1536)
        XCTAssertEqual(record.transfer.completedBytes, 1536)
        XCTAssertEqual(record.chunkMap.writtenRanges, [CoreByteRange(offset: 0, length: 1536)])
        XCTAssertEqual(record.chunkMap.chunks[0].status, .partial)

        let partData = try Data(contentsOf: store.partFileURL(for: id))
        XCTAssertEqual(partData[0], 1)
        XCTAssertEqual(partData[512], 2)
        XCTAssertEqual(partData[1024], 3)
    }

    func testWriteBlockMarksTransferComplete() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let data = Data([1, 2, 3, 4])
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|4|\(ED2KHash.hash(data: data))|/"
        )
        let id = snapshot.transfers[0].id

        let record = try store.writeBlock(transferID: id, offset: 0, data: data)

        XCTAssertEqual(record.transfer.completedBytes, 4)
        XCTAssertEqual(record.transfer.status, .completed)
        XCTAssertEqual(record.verifiedHash, ED2KHash.hash(data: data))
        XCTAssertEqual(record.chunkMap.chunks.map(\.status), [.complete])
    }

    func testCompletedTransferMovesPartFileIntoIncoming() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let data = Data([1, 2, 3, 4])
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|4|\(ED2KHash.hash(data: data))|/"
        )
        let id = snapshot.transfers[0].id

        let record = try store.writeBlock(transferID: id, offset: 0, data: data)
        let completedFileURL = try XCTUnwrap(store.completedFileURL(for: record))

        XCTAssertEqual(record.completedFileName, "Sample.zip")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.partFileURL(for: id).path))
        XCTAssertEqual(try Data(contentsOf: completedFileURL), data)
    }

    func testCompletedTransferUsesUniqueIncomingFileName() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let data = Data([1, 2, 3, 4])
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|4|\(ED2KHash.hash(data: data))|/"
        )
        let id = snapshot.transfers[0].id
        try Data([9]).write(to: store.incomingDirectory.appendingPathComponent("Sample.zip"))

        let record = try store.writeBlock(transferID: id, offset: 0, data: data)

        XCTAssertEqual(record.completedFileName, "Sample 2.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.incomingDirectory.appendingPathComponent("Sample.zip").path))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(store.completedFileURL(for: record))), data)
    }

    func testCompletedTransferCanUseOverriddenIncomingDirectory() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacMuleCoreTests-\(UUID().uuidString)", isDirectory: true)
        let incomingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacMuleIncomingTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
            try? FileManager.default.removeItem(at: incomingURL)
        }

        let store = CoreTransferStore(rootDirectory: rootURL, incomingDirectory: incomingURL)
        let service = MacMuleCoreService(transferStore: store)
        let data = Data([1, 2, 3, 4])
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|4|\(ED2KHash.hash(data: data))|/"
        )
        let id = snapshot.transfers[0].id

        let record = try store.writeBlock(transferID: id, offset: 0, data: data)
        let completedFileURL = try XCTUnwrap(store.completedFileURL(for: record))

        XCTAssertTrue(completedFileURL.path.hasPrefix(incomingURL.path))
        XCTAssertFalse(completedFileURL.path.hasPrefix(rootURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.metadataURL(for: id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.partFileURL(for: id).path))
        XCTAssertEqual(store.tempDirectory, rootURL.appendingPathComponent("Temp", isDirectory: true))
        XCTAssertEqual(try Data(contentsOf: completedFileURL), data)
    }

    func testTransferCanUseOverriddenTempDirectory() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacMuleCoreTests-\(UUID().uuidString)", isDirectory: true)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacMuleTempTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
            try? FileManager.default.removeItem(at: tempURL)
        }

        let store = CoreTransferStore(rootDirectory: rootURL, tempDirectory: tempURL)
        let service = MacMuleCoreService(transferStore: store)
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|4|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = snapshot.transfers[0].id

        XCTAssertEqual(store.tempDirectory, tempURL)
        XCTAssertTrue(store.metadataURL(for: id).path.hasPrefix(tempURL.path))
        XCTAssertTrue(store.partFileURL(for: id).path.hasPrefix(tempURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.metadataURL(for: id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.partFileURL(for: id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("Temp", isDirectory: true).path))
    }

    func testPeerSourceBookmarksRoundTripThroughTransferRecord() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|4|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = snapshot.transfers[0].id
        let expected = [
            CorePeerSourceBookmark(
                endpoint: ED2KPeerEndpoint(host: "1.2.3.4", port: 4662),
                failureCount: 2,
                cooldownUntil: Date(timeIntervalSince1970: 1234)
            ),
            CorePeerSourceBookmark(
                endpoint: ED2KPeerEndpoint(host: "5.6.7.8", port: 4662),
                failureCount: 0
            )
        ]

        _ = try store.updatePeerSourceBookmarks(transferID: id, bookmarks: expected)

        let record = try store.loadRecord(for: id)
        XCTAssertEqual(record.peerSourceBookmarks, expected)
    }

    func testPeerInflightBookmarksRoundTripThroughTransferRecord() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|4|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = snapshot.transfers[0].id
        let reservedAt = Date()
        let expected = [
            CorePeerInflightBookmark(
                endpoint: ED2KPeerEndpoint(host: "1.2.3.4", port: 4662),
                startOffset: 0,
                endOffset: 262_144,
                reservedAt: reservedAt
            )
        ]

        _ = try store.updatePeerInflightBookmarks(transferID: id, bookmarks: expected)

        let record = try store.loadRecord(for: id)
        XCTAssertEqual(record.peerInflightBookmarks, expected)
    }

    func testPeerChunkRetryBookmarksRoundTripThroughTransferRecord() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|600000|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = snapshot.transfers[0].id
        let expected = [
            CorePeerChunkRetryBookmark(
                startOffset: 0,
                endOffset: 262_144,
                failureCount: 2,
                cooldownUntil: Date(timeIntervalSince1970: 1234),
                lastFailureAt: Date(timeIntervalSince1970: 1200)
            )
        ]

        _ = try store.updatePeerChunkRetryBookmarks(transferID: id, bookmarks: expected)

        let record = try store.loadRecord(for: id)
        XCTAssertEqual(record.peerChunkRetryBookmarks, expected)
    }

    func testResumeCheckpointRoundTrip() throws {
        let store = try makeTemporaryStore()
        let checkpoint = CoreResumeCheckpoint(
            activeTransferIDs: [UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!],
            activeSearchQuery: "ubuntu",
            serverConfiguration: CoreResumeServerConfiguration(
                endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
                clientID: 1,
                tcpPort: 4662,
                nickname: "MacMule",
                protocolVersion: 60,
                flags: 1
            ),
            updatedAt: Date(timeIntervalSince1970: 1234)
        )

        try store.saveResumeCheckpoint(checkpoint)

        XCTAssertEqual(try store.loadResumeCheckpoint(), checkpoint)
    }

    func testCompletedTransferWithHashMismatchFailsAndKeepsPartFile() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|4|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = snapshot.transfers[0].id

        let record = try store.writeBlock(transferID: id, offset: 0, data: Data([1, 2, 3, 4]))

        XCTAssertEqual(record.transfer.status, .failed)
        XCTAssertNil(record.completedFileName)
        XCTAssertEqual(record.verifiedHash, ED2KHash.hash(data: Data([1, 2, 3, 4])))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.partFileURL(for: id).path))
        XCTAssertNil(store.completedFileURL(for: record))
    }

    func testCompleteChunkVerifiesExpectedPartHashBeforeFullCompletion() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let chunkSize = CoreChunkMap.ed2kChunkSize
        let firstChunk = Data(repeating: 7, count: Int(chunkSize))
        let firstPartHash = ED2KHash.hash(data: firstChunk)
        let secondPartHash = ED2KHash.hash(data: Data([1]))
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|\(chunkSize + 1)|00000000000000000000000000000000|p=\(firstPartHash):\(secondPartHash)|/"
        )
        let id = snapshot.transfers[0].id

        let record = try store.writeBlock(transferID: id, offset: 0, data: firstChunk)

        XCTAssertEqual(record.transfer.status, .queued)
        XCTAssertEqual(record.transfer.completedBytes, chunkSize)
        XCTAssertEqual(record.verifiedPartHashes[0], firstPartHash)
        XCTAssertNil(record.verifiedPartHashes[1])
        XCTAssertNil(record.completedFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.partFileURL(for: id).path))
    }

    func testCompleteChunkWithMismatchedPartHashFailsBeforeFullCompletion() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let chunkSize = CoreChunkMap.ed2kChunkSize
        let firstChunk = Data(repeating: 7, count: Int(chunkSize))
        let secondPartHash = ED2KHash.hash(data: Data([1]))
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|\(chunkSize + 1)|00000000000000000000000000000000|p=00000000000000000000000000000000:\(secondPartHash)|/"
        )
        let id = snapshot.transfers[0].id

        let record = try store.writeBlock(transferID: id, offset: 0, data: firstChunk)

        XCTAssertEqual(record.transfer.status, .failed)
        XCTAssertEqual(record.transfer.completedBytes, chunkSize)
        XCTAssertNil(record.verifiedPartHashes[0])
        XCTAssertNil(record.completedFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.partFileURL(for: id).path))
    }

    func testWriteBlockRejectsOutOfBoundsRange() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|4|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = snapshot.transfers[0].id

        XCTAssertThrowsError(
            try store.writeBlock(transferID: id, offset: 3, data: Data([1, 2]))
        ) { error in
            XCTAssertEqual(
                error as? CoreTransferStoreError,
                .blockOutOfBounds(offset: 3, length: 2, fileSize: 4)
            )
        }
    }

    private func makeTemporaryStore() throws -> CoreTransferStore {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacMuleCoreTests-\(UUID().uuidString)", isDirectory: true)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        return CoreTransferStore(rootDirectory: rootURL)
    }
}
