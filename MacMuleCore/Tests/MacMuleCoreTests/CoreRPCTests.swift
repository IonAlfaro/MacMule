import Foundation
import XCTest
@testable import MacMuleCore

final class CoreRPCTests: XCTestCase {
    func testAddED2KLinkRequestReturnsSnapshot() throws {
        let handler = CoreRPCHandler()
        let request = JSONRPCRequest(
            id: 1,
            method: "add_ed2k_link",
            params: [
                "link": "ed2k://|file|Sample.zip|1024|0CC175B9C0F1B6A831C399E269772661|/"
            ]
        )

        let response = handler.handle(request)

        XCTAssertNil(response.error)
        XCTAssertEqual(response.id, 1)
        XCTAssertEqual(response.result?.snapshot?.transfers.count, 1)
        XCTAssertEqual(response.result?.snapshot?.transfers[0].fileName, "Sample.zip")
    }

    func testMissingParamReturnsInvalidParamsError() {
        let handler = CoreRPCHandler()
        let response = handler.handle(JSONRPCRequest(id: 2, method: "add_ed2k_link"))

        XCTAssertEqual(response.error?.code, -32602)
        XCTAssertEqual(response.id, 2)
    }

    func testUnknownMethodReturnsMethodNotFound() {
        let handler = CoreRPCHandler()
        let response = handler.handle(JSONRPCRequest(id: 3, method: "dance"))

        XCTAssertEqual(response.error?.code, -32601)
    }

    func testInvalidJSONReturnsParseErrorData() throws {
        let handler = CoreRPCHandler()
        let data = handler.handle(Data("{".utf8))
        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)

        XCTAssertEqual(response.error?.code, -32700)
        XCTAssertNil(response.id)
    }

    func testPauseThroughJSONData() throws {
        let handler = CoreRPCHandler()
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let addRequest = JSONRPCRequest(
            id: 4,
            method: "add_ed2k_link",
            params: [
                "link": "ed2k://|file|Sample.zip|1024|0CC175B9C0F1B6A831C399E269772661|/"
            ]
        )
        let addResponse = try decoder.decode(JSONRPCResponse.self, from: handler.handle(try encoder.encode(addRequest)))
        let id = try XCTUnwrap(addResponse.result?.snapshot?.transfers[0].id.uuidString)

        let pauseRequest = JSONRPCRequest(id: 5, method: "pause", params: ["id": id])
        let pauseResponse = try decoder.decode(JSONRPCResponse.self, from: handler.handle(try encoder.encode(pauseRequest)))

        XCTAssertEqual(pauseResponse.result?.snapshot?.transfers[0].status, .paused)
    }

    func testEventsSinceReturnsIncrementalChanges() throws {
        let handler = CoreRPCHandler()

        _ = handler.handle(
            JSONRPCRequest(
                id: 6,
                method: "add_ed2k_link",
                params: [
                    "link": "ed2k://|file|Sample.zip|1024|0CC175B9C0F1B6A831C399E269772661|/"
                ]
            )
        )

        let response = handler.handle(JSONRPCRequest(id: 7, method: "events_since"))
        let batch = try XCTUnwrap(response.result?.eventBatch)

        XCTAssertNil(response.error)
        XCTAssertEqual(batch.afterSequence, 0)
        XCTAssertEqual(batch.latestSequence, 1)
        XCTAssertEqual(batch.events.map(\.kind), [.transferAdded])
        XCTAssertEqual(batch.snapshot.transfers.count, 1)
    }

    func testEventsSinceCursorSkipsOlderChanges() throws {
        let handler = CoreRPCHandler()

        _ = handler.handle(
            JSONRPCRequest(
                id: 8,
                method: "add_ed2k_link",
                params: [
                    "link": "ed2k://|file|Sample.zip|1024|0CC175B9C0F1B6A831C399E269772661|/"
                ]
            )
        )

        let response = handler.handle(
            JSONRPCRequest(
                id: 9,
                method: "events_since",
                params: ["after": "1"]
            )
        )
        let batch = try XCTUnwrap(response.result?.eventBatch)

        XCTAssertEqual(batch.latestSequence, 1)
        XCTAssertTrue(batch.events.isEmpty)
        XCTAssertEqual(batch.snapshot.transfers.count, 1)
    }

    func testEventsSinceThroughJSONDataDecodesEventBatchResult() throws {
        let handler = CoreRPCHandler()
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let addRequest = JSONRPCRequest(
            id: 901,
            method: "add_ed2k_link",
            params: [
                "link": "ed2k://|file|Sample.zip|1024|0CC175B9C0F1B6A831C399E269772661|/"
            ]
        )
        _ = try decoder.decode(JSONRPCResponse.self, from: handler.handle(try encoder.encode(addRequest)))

        let eventsRequest = JSONRPCRequest(id: 902, method: "events_since")
        let eventsResponse = try decoder.decode(JSONRPCResponse.self, from: handler.handle(try encoder.encode(eventsRequest)))

        let batch = try XCTUnwrap(eventsResponse.result?.eventBatch)
        XCTAssertNil(eventsResponse.result?.snapshot)
        XCTAssertEqual(batch.events.map(\.kind), [.transferAdded])
    }

    func testWriteBlockRequestUpdatesTransferProgress() throws {
        let store = try makeTemporaryStore()
        let handler = CoreRPCHandler(service: MacMuleCoreService(transferStore: store))
        let addResponse = handler.handle(
            JSONRPCRequest(
                id: 10,
                method: "add_ed2k_link",
                params: [
                    "link": "ed2k://|file|Sample.zip|4|0CC175B9C0F1B6A831C399E269772661|/"
                ]
            )
        )
        let id = try XCTUnwrap(addResponse.result?.snapshot?.transfers[0].id.uuidString)

        let response = handler.handle(
            JSONRPCRequest(
                id: 11,
                method: "write_block",
                params: [
                    "id": id,
                    "offset": "0",
                    "data_base64": Data([1, 2]).base64EncodedString()
                ]
            )
        )

        XCTAssertNil(response.error)
        XCTAssertEqual(response.result?.snapshot?.transfers[0].completedBytes, 2)
        XCTAssertEqual(try store.loadRecord(for: try XCTUnwrap(UUID(uuidString: id))).transfer.completedBytes, 2)
    }

    func testWriteBlockRequestCanCompleteTransfer() throws {
        let store = try makeTemporaryStore()
        let handler = CoreRPCHandler(service: MacMuleCoreService(transferStore: store))
        let data = Data([1, 2, 3, 4])
        let addResponse = handler.handle(
            JSONRPCRequest(
                id: 12,
                method: "add_ed2k_link",
                params: [
                    "link": "ed2k://|file|Sample.zip|4|\(ED2KHash.hash(data: data))|/"
                ]
            )
        )
        let id = try XCTUnwrap(addResponse.result?.snapshot?.transfers[0].id.uuidString)

        let response = handler.handle(
            JSONRPCRequest(
                id: 13,
                method: "write_block",
                params: [
                    "id": id,
                    "offset": "0",
                    "data_base64": data.base64EncodedString()
                ]
            )
        )
        let transfer = try XCTUnwrap(response.result?.snapshot?.transfers[0])
        let record = try store.loadRecord(for: transfer.id)

        XCTAssertEqual(transfer.status, .completed)
        XCTAssertNotNil(store.completedFileURL(for: record))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.partFileURL(for: transfer.id).path))
    }

    func testWriteBlockRejectsInvalidBase64() {
        let handler = CoreRPCHandler()
        let response = handler.handle(
            JSONRPCRequest(
                id: 14,
                method: "write_block",
                params: [
                    "id": UUID().uuidString,
                    "offset": "0",
                    "data_base64": "not base64"
                ]
            )
        )

        XCTAssertEqual(response.error?.code, -32602)
        XCTAssertEqual(response.id, 14)
    }

    func testConnectServerRequestReturnsConnectingSnapshot() throws {
        let transport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService(
            serverTransportFactory: { _ in transport }
        )
        let handler = CoreRPCHandler(service: service)

        let response = handler.handle(
            JSONRPCRequest(
                id: 15,
                method: "connect_server",
                params: [
                    "host": "127.0.0.1",
                    "port": "4661"
                ]
            )
        )

        XCTAssertNil(response.error)
        XCTAssertEqual(response.result?.snapshot?.network.statusText, "Conectando a 127.0.0.1:4661")
        XCTAssertFalse(response.result?.snapshot?.network.isConnected ?? true)
    }

    func testDisconnectServerRequestResetsNetworkState() {
        let transport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService(
            serverTransportFactory: { _ in transport }
        )
        let handler = CoreRPCHandler(service: service)

        _ = handler.handle(
            JSONRPCRequest(
                id: 16,
                method: "connect_server",
                params: [
                    "host": "127.0.0.1",
                    "port": "4661"
                ]
            )
        )

        let response = handler.handle(
            JSONRPCRequest(
                id: 17,
                method: "disconnect_server"
            )
        )

        XCTAssertNil(response.error)
        XCTAssertEqual(response.result?.snapshot?.network.statusText, "Sin conexion")
        XCTAssertFalse(response.result?.snapshot?.network.isConnected ?? true)
    }

    func testConnectServerRejectsInvalidPort() {
        let handler = CoreRPCHandler()
        let response = handler.handle(
            JSONRPCRequest(
                id: 18,
                method: "connect_server",
                params: [
                    "host": "127.0.0.1",
                    "port": "70000"
                ]
            )
        )

        XCTAssertEqual(response.error?.code, -32602)
        XCTAssertEqual(response.id, 18)
    }

    func testAddAndRemoveServerRequestsRoundTripSnapshot() {
        let handler = CoreRPCHandler()

        let addResponse = handler.handle(
            JSONRPCRequest(
                id: 19,
                method: "add_server",
                params: [
                    "host": "203.0.113.5",
                    "port": "4661",
                    "name": "Index A"
                ]
            )
        )

        XCTAssertNil(addResponse.error)
        XCTAssertEqual(addResponse.result?.snapshot?.servers.count, 1)
        XCTAssertEqual(addResponse.result?.snapshot?.servers[0].name, "Index A")

        let removeResponse = handler.handle(
            JSONRPCRequest(
                id: 20,
                method: "remove_server",
                params: [
                    "host": "203.0.113.5",
                    "port": "4661"
                ]
            )
        )

        XCTAssertNil(removeResponse.error)
        XCTAssertTrue(removeResponse.result?.snapshot?.servers.isEmpty ?? false)
    }

    func testImportServersRequestParsesMultipleAddresses() {
        let handler = CoreRPCHandler()
        let response = handler.handle(
            JSONRPCRequest(
                id: 21,
                method: "import_servers",
                params: [
                    "addresses": "203.0.113.5:4661\n203.0.113.6:4662"
                ]
            )
        )

        XCTAssertNil(response.error)
        XCTAssertEqual(response.result?.snapshot?.servers.map(\.endpoint.address), [
            "203.0.113.5:4661",
            "203.0.113.6:4662"
        ])
    }

    func testSearchRequestSendsPacketThroughActiveConnection() throws {
        let transport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService(
            serverTransportFactory: { _ in transport }
        )
        let handler = CoreRPCHandler(service: service)

        _ = handler.handle(
            JSONRPCRequest(
                id: 22,
                method: "connect_server",
                params: [
                    "host": "127.0.0.1",
                    "port": "4661"
                ]
            )
        )
        transport.stateUpdateHandler?(.ready)

        let response = handler.handle(
            JSONRPCRequest(
                id: 23,
                method: "search",
                params: ["query": "ubuntu iso"]
            )
        )

        XCTAssertNil(response.error)
        XCTAssertTrue(response.result?.snapshot?.searchResults.isEmpty ?? false)
        XCTAssertEqual(transport.sentData.count, 1)

        transport.receiveHandler?(
            ED2KPacket(
                opcode: .idChange,
                payload: Data([0x04, 0x03, 0x02, 0x01])
            ).encoded()
        )

        XCTAssertEqual(transport.sentData.count, 2)
        XCTAssertEqual(transport.sentData[1], try ED2KSearchRequest(query: "ubuntu iso").packet().encoded())
    }

    func testConnectServerWithoutHostUsesPreferredPersistedEndpoint() throws {
        let transport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService(
            serverTransportFactory: { _ in transport }
        )
        let handler = CoreRPCHandler(service: service)

        _ = handler.handle(
            JSONRPCRequest(
                id: 24,
                method: "add_server",
                params: [
                    "host": "203.0.113.55",
                    "port": "4661",
                    "name": "Bootstrap"
                ]
            )
        )

        let response = handler.handle(
            JSONRPCRequest(
                id: 25,
                method: "connect_server"
            )
        )

        XCTAssertNil(response.error)
        XCTAssertEqual(response.result?.snapshot?.network.statusText, "Conectando a 203.0.113.55:4661")
    }

    func testConnectServerUsesPersistedUserHashByDefault() throws {
        let store = try makeTemporaryStore()
        let transport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in transport }
        )
        let handler = CoreRPCHandler(service: service)

        _ = handler.handle(
            JSONRPCRequest(
                id: 26,
                method: "connect_server",
                params: [
                    "host": "127.0.0.1",
                    "port": "4661"
                ]
            )
        )
        transport.stateUpdateHandler?(.ready)

        let loginPacket = try XCTUnwrap(transport.sentData.first).dropFirst(6)
        XCTAssertEqual(Data(loginPacket.prefix(16)), service.userHash())
        XCTAssertEqual(try store.loadClientIdentity()?.userHash, service.userHash())
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

private final class FakeED2KServerTCPTransport: @unchecked Sendable, ED2KServerTCPTransport {
    var stateUpdateHandler: ((ED2KServerTCPTransportState) -> Void)?
    var receiveHandler: ((Data) -> Void)?
    var logHandler: (@Sendable (String) -> Void)?
    private(set) var sentData: [Data] = []

    func start(queue: DispatchQueue) {}

    func send(_ data: Data, completion: @escaping @Sendable (ED2KServerTCPTransportSendResult) -> Void) {
        if isEmptyOfferFilesPacket(data) == false {
            sentData.append(data)
        }
        completion(.sent)
    }

    func receiveNext() {}

    func cancel() {}
}

private func isEmptyOfferFilesPacket(_ data: Data) -> Bool {
    guard let packet = try? ED2KPacket.decode(data) else {
        return false
    }

    return packet.opcode == ED2KPacketOpcode.offerFiles.rawValue
        && packet.payload == Data([0x00, 0x00, 0x00, 0x00])
}
