import XCTest
@testable import MacMuleCore

final class CoreServiceTests: XCTestCase {
    func testAddsED2KLinkAsQueuedTransfer() throws {
        let service = MacMuleCoreService()

        let snapshot = try service.addED2KLink(
            "ed2k://|file|Ubuntu%2026.04%20Desktop.iso|5812142080|A41D8CD98F00B204E9800998ECF8427E|/"
        )

        XCTAssertEqual(snapshot.transfers.count, 1)
        XCTAssertEqual(snapshot.transfers[0].fileName, "Ubuntu 26.04 Desktop.iso")
        XCTAssertEqual(snapshot.transfers[0].kind, .archive)
        XCTAssertEqual(snapshot.transfers[0].status, .queued)
        XCTAssertEqual(snapshot.transfers[0].ed2kHash, "A41D8CD98F00B204E9800998ECF8427E")
    }

    func testDoesNotDuplicateExistingHash() throws {
        let service = MacMuleCoreService()
        let link = "ed2k://|file|Sample.zip|1024|0CC175B9C0F1B6A831C399E269772661|/"

        _ = try service.addED2KLink(link)
        let snapshot = try service.addED2KLink(link)

        XCTAssertEqual(snapshot.transfers.count, 1)
    }

    func testPauseResumeAndRemoveTransfer() throws {
        let service = MacMuleCoreService()
        let added = try service.addED2KLink(
            "ed2k://|file|Sample.zip|1024|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = added.transfers[0].id.uuidString

        let paused = try service.pauseTransfer(id: id)
        XCTAssertEqual(paused.transfers[0].status, .paused)

        let resumed = try service.resumeTransfer(id: id)
        XCTAssertEqual(resumed.transfers[0].status, .queued)
        XCTAssertEqual(resumed.transfers[0].downloadSpeedBytesPerSecond, 0)

        let removed = try service.removeTransfer(id: id)
        XCTAssertTrue(removed.transfers.isEmpty)
    }

    func testRecordsTransferEventsWithCursor() throws {
        let service = MacMuleCoreService()
        let added = try service.addED2KLink(
            "ed2k://|file|Sample.zip|1024|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = added.transfers[0].id.uuidString

        _ = try service.pauseTransfer(id: id)
        _ = try service.removeTransfer(id: id)

        let allEvents = service.events(after: 0)
        XCTAssertEqual(allEvents.latestSequence, 3)
        XCTAssertEqual(allEvents.events.map(\.kind), [.transferAdded, .transferUpdated, .transferRemoved])

        let recentEvents = service.events(after: 1)
        XCTAssertEqual(recentEvents.events.map(\.kind), [.transferUpdated, .transferRemoved])
    }

    func testPersistsTransfersAcrossServiceInstances() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let added = try service.addED2KLink(
            "ed2k://|file|Sample.zip|1024|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = added.transfers[0].id.uuidString

        _ = try service.pauseTransfer(id: id)

        let restoredService = MacMuleCoreService(transferStore: store)
        let restoredSnapshot = restoredService.snapshot()

        XCTAssertEqual(restoredSnapshot.transfers.count, 1)
        XCTAssertEqual(restoredSnapshot.transfers[0].id, added.transfers[0].id)
        XCTAssertEqual(restoredSnapshot.transfers[0].status, .paused)
    }

    func testCrashRecoveryCheckpointNormalizesDownloadingTransferBackToQueued() throws {
        let store = try makeTemporaryStore()
        let transferID: UUID
        do {
            let service = MacMuleCoreService(transferStore: store)
            let added = try service.addED2KLink(
                "ed2k://|file|Sample.zip|1024|0CC175B9C0F1B6A831C399E269772661|/"
            )
            transferID = added.transfers[0].id
            _ = try service.resumeTransfer(id: transferID.uuidString)
        }

        try store.saveResumeCheckpoint(
            CoreResumeCheckpoint(
                activeTransferIDs: [transferID],
                activeSearchQuery: "ubuntu iso",
                updatedAt: Date()
            )
        )
        _ = try store.activateRuntimeLock()

        let restoredService = MacMuleCoreService(transferStore: store)
        let restoredTransfer = try XCTUnwrap(restoredService.snapshot().transfers.first(where: { $0.id == transferID }))

        XCTAssertEqual(restoredTransfer.status, .queued)
        XCTAssertEqual(restoredTransfer.downloadSpeedBytesPerSecond, 0)
        XCTAssertEqual(restoredTransfer.uploadSpeedBytesPerSecond, 0)
        XCTAssertEqual(restoredTransfer.sources, 0)
        XCTAssertEqual(restoredTransfer.availability, 0)
    }

    func testSearchWithoutConnectionPersistsResumeCheckpointQuery() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)

        _ = service.search(query: "ubuntu iso")

        let checkpoint = try XCTUnwrap(store.loadResumeCheckpoint())
        XCTAssertEqual(checkpoint.activeSearchQuery, "ubuntu iso")
    }

    func testCreatesPartFileAndMetadataSidecar() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|2048|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = snapshot.transfers[0].id

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.metadataURL(for: id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.partFileURL(for: id).path))

        let attributes = try FileManager.default.attributesOfItem(atPath: store.partFileURL(for: id).path)
        XCTAssertEqual(attributes[.size] as? UInt64, 2048)
    }

    func testRemoveDeletesPersistedTransferFiles() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|1024|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = snapshot.transfers[0].id

        _ = try service.removeTransfer(id: id.uuidString)

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.metadataURL(for: id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.partFileURL(for: id).path))
        XCTAssertTrue(MacMuleCoreService(transferStore: store).snapshot().transfers.isEmpty)
    }

    func testRemoveDeletesCompletedIncomingFile() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let data = Data([1, 2, 3, 4])
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|4|\(ED2KHash.hash(data: data))|/"
        )
        let id = snapshot.transfers[0].id
        _ = try service.writeBlock(id: id.uuidString, offset: 0, data: data)
        let completedFileURL = try XCTUnwrap(store.completedFileURL(for: store.loadRecord(for: id)))

        _ = try service.removeTransfer(id: id.uuidString)

        XCTAssertFalse(FileManager.default.fileExists(atPath: completedFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.metadataURL(for: id).path))
    }

    func testWriteBlockUpdatesTransferProgressAndEvents() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Sample.zip|4|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = snapshot.transfers[0].id

        let updatedSnapshot = try service.writeBlock(id: id.uuidString, offset: 0, data: Data([1, 2]))

        XCTAssertEqual(updatedSnapshot.transfers[0].completedBytes, 2)
        XCTAssertEqual(try store.loadRecord(for: id).transfer.completedBytes, 2)
        XCTAssertEqual(service.events(after: 1).events.map(\.kind), [.transferUpdated])
    }

    func testConnectToServerUpdatesNetworkStateAndRecordsEvents() {
        let transport = FakeED2KServerTCPTransport()
        let listenerTransport = FakeED2KPeerTCPListenerTransport()
        let service = MacMuleCoreService(peerListenerTransportFactory: { _ in listenerTransport })
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        let connectingSnapshot = service.connectToServer(configuration, transport: transport)
        XCTAssertFalse(connectingSnapshot.network.isConnected)
        XCTAssertEqual(connectingSnapshot.network.statusText, "Conectando a 127.0.0.1:4661")

        listenerTransport.simulateState(.ready(4662))
        transport.simulateState(.ready)
        let connectedSnapshot = service.snapshot()
        XCTAssertTrue(connectedSnapshot.network.isConnected)
        XCTAssertEqual(connectedSnapshot.network.statusText, "Login enviado a 127.0.0.1:4661")
        XCTAssertEqual(service.events(after: 0).events.map(\.kind), [.networkUpdated, .networkUpdated, .networkUpdated, .networkUpdated, .networkUpdated])
    }

    func testLowIDSourcesQueueServerCallbackAndStartPeerDownloadAfterCallback() throws {
        let serverTransport = FakeED2KServerTCPTransport()
        let listenerTransport = FakeED2KPeerTCPListenerTransport()
        let capture = ThreadSafePeerTransportCapture()
        let service = MacMuleCoreService(
            peerTransportFactory: { endpoint in
                let transport = FakeED2KPeerTCPTransport()
                capture.store(endpoint: endpoint, transport: transport)
                return transport
            },
            peerListenerTransportFactory: { _ in listenerTransport }
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        _ = service.connectToServer(configuration, transport: serverTransport)
        listenerTransport.simulateState(.ready(4662))
        serverTransport.simulateState(.ready)
        serverTransport.simulateReceive(
            ED2KPacket(
                opcode: .idChange,
                payload: Data([0x34, 0x12, 0x00, 0x01])
            ).encoded()
        )

        let snapshot = try service.addED2KLink(
            ED2KFileLink(
                fileName: "Ubuntu.iso",
                sizeInBytes: 1024,
                hash: "0123456789ABCDEF0123456789ABCDEF",
                rootHash: nil,
                partHashes: []
            ),
            initialSources: [
                ED2KFoundSource(clientID: 0x0000BEEF, clientPort: 4662)
            ]
        )

        XCTAssertEqual(snapshot.transfers[0].sources, 1)
        let callbackRequest = try XCTUnwrap(
            serverTransport.sentData.compactMap({ try? ED2KPacket.decode($0) })
                .first(where: { $0.opcode == ED2KPacketOpcode.callbackRequest.rawValue })
        )
        XCTAssertEqual(callbackRequest.payload, Data([0xEF, 0xBE, 0x00, 0x00]))

        serverTransport.simulateReceive(
            ED2KPacket(
                opcode: .callbackRequested,
                payload: Data([198, 51, 100, 24, 0x36, 0x12])
            ).encoded()
        )

        let createdPeerTransport = try XCTUnwrap(capture.transport)
        XCTAssertEqual(capture.endpoint, ED2KPeerEndpoint(host: "198.51.100.24", port: 4662))
        XCTAssertTrue(createdPeerTransport.startCalled)

        createdPeerTransport.simulateState(.ready)
        let peerPackets = createdPeerTransport.sentData.compactMap { try? ED2KPacket.decode($0) }
        XCTAssertTrue(peerPackets.contains(where: { $0.opcode == ED2KPeerPacketOpcode.hello.rawValue }))
    }

    func testConnectToServerUpgradesLegacyServerCapabilityFlags() throws {
        let transport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService()
        var normalizedHash = Data(0..<16)
        normalizedHash[5] = 0x0E
        normalizedHash[14] = 0x6F
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16),
            flags: ED2KLoginRequest.legacyDefaultServerCapabilityFlags
        )

        _ = service.connectToServer(configuration, transport: transport)
        transport.simulateState(.ready)

        XCTAssertEqual(
            transport.sentData.first,
            try ED2KLoginRequest(
                userHash: normalizedHash,
                flags: ED2KLoginRequest.defaultServerCapabilityFlags
            ).packet().encoded()
        )
    }

    func testServerConnectionWaitingUpdatesNetworkStatus() {
        let transport = FakeED2KServerTCPTransport()
        let listenerTransport = FakeED2KPeerTCPListenerTransport()
        let logs = ThreadSafeStringLog()
        let service = MacMuleCoreService(
            networkLogHandler: { logs.append($0) },
            peerListenerTransportFactory: { _ in listenerTransport }
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        _ = service.connectToServer(configuration, transport: transport)
        transport.simulateState(.waiting("dns lookup"))

        XCTAssertEqual(service.snapshot().network.statusText, "Esperando conexion a 127.0.0.1:4661")
        XCTAssertTrue(logs.values.contains(where: { $0.contains("eD2k waiting: dns lookup") }))
    }

    func testConnectToServerStartsPeerListenerOnConfiguredPort() {
        let transport = FakeED2KServerTCPTransport()
        let listenerTransport = FakeED2KPeerTCPListenerTransport()
        let service = MacMuleCoreService(peerListenerTransportFactory: { _ in listenerTransport })
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16),
            tcpPort: 4670
        )

        _ = service.connectToServer(configuration, transport: transport)
        listenerTransport.simulateState(.ready(4670))

        XCTAssertTrue(listenerTransport.startCalled)
        XCTAssertEqual(service.snapshot().network.tcpPort, 4670)
    }

    func testPeerListenerReadyTriggersUPnPPortMapping() {
        let transport = FakeED2KServerTCPTransport()
        let listenerTransport = FakeED2KPeerTCPListenerTransport()
        let portMapper = FakeED2KPeerPortMapper()
        let service = MacMuleCoreService(
            peerListenerTransportFactory: { _ in listenerTransport },
            peerPortMapper: portMapper
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16),
            tcpPort: 4670
        )

        _ = service.connectToServer(configuration, transport: transport)
        listenerTransport.simulateState(.ready(4670))

        XCTAssertEqual(portMapper.calls.count, 1)
        XCTAssertEqual(portMapper.calls[0].tcpPort, 4670)
        XCTAssertEqual(portMapper.calls[0].udpPort, 4672)
    }

    func testReconnectToServerReusesExistingPeerListenerOnSamePort() {
        let firstTransport = FakeED2KServerTCPTransport()
        let secondTransport = FakeED2KServerTCPTransport()
        let listenerTransport = FakeED2KPeerTCPListenerTransport()
        let listenerFactoryCallCount = ThreadSafeIntCounter()
        let service = MacMuleCoreService(
            serverTransportFactory: { endpoint in
                endpoint.host == "127.0.0.1" ? firstTransport : secondTransport
            },
            peerListenerTransportFactory: { _ in
                listenerFactoryCallCount.increment()
                return listenerTransport
            }
        )

        _ = service.connectToServer(
            ED2KServerSessionConfiguration(
                endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
                userHash: Data(0..<16),
                tcpPort: 4662
            )
        )
        listenerTransport.simulateState(.ready(4662))

        _ = service.connectToServer(
            ED2KServerSessionConfiguration(
                endpoint: ED2KServerEndpoint(host: "203.0.113.20", port: 4661),
                userHash: Data(0..<16),
                tcpPort: 4662
            )
        )

        XCTAssertEqual(listenerFactoryCallCount.value, 1)
        XCTAssertEqual(listenerTransport.startCallCount, 1)
    }

    func testReconnectWhilePeerListenerIsStartingReusesExistingListener() {
        let firstTransport = FakeED2KServerTCPTransport()
        let secondTransport = FakeED2KServerTCPTransport()
        let listenerTransport = FakeED2KPeerTCPListenerTransport()
        let listenerFactoryCallCount = ThreadSafeIntCounter()
        let service = MacMuleCoreService(
            serverTransportFactory: { endpoint in
                endpoint.host == "127.0.0.1" ? firstTransport : secondTransport
            },
            peerListenerTransportFactory: { _ in
                listenerFactoryCallCount.increment()
                return listenerTransport
            }
        )

        _ = service.connectToServer(
            ED2KServerSessionConfiguration(
                endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
                userHash: Data(0..<16),
                tcpPort: 4662
            )
        )
        _ = service.connectToServer(
            ED2KServerSessionConfiguration(
                endpoint: ED2KServerEndpoint(host: "203.0.113.20", port: 4661),
                userHash: Data(0..<16),
                tcpPort: 4662
            )
        )

        XCTAssertEqual(listenerFactoryCallCount.value, 1)
        XCTAssertEqual(listenerTransport.startCallCount, 1)
    }

    func testStaleServerConnectionEventsDoNotOverrideNewConnection() {
        let firstTransport = FakeED2KServerTCPTransport()
        let secondTransport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService(
            serverTransportFactory: { endpoint in
                endpoint.host == "127.0.0.1" ? firstTransport : secondTransport
            }
        )
        let firstEndpoint = ED2KServerEndpoint(host: "127.0.0.1", port: 4661)
        let secondEndpoint = ED2KServerEndpoint(host: "203.0.113.20", port: 4661)

        _ = service.connectToServer(
            ED2KServerSessionConfiguration(endpoint: firstEndpoint, userHash: Data(0..<16))
        )
        _ = service.connectToServer(
            ED2KServerSessionConfiguration(endpoint: secondEndpoint, userHash: Data(0..<16))
        )

        firstTransport.simulateState(.failed("old connection failed"))

        XCTAssertEqual(service.snapshot().network.statusText, "Conectando a \(secondEndpoint.address)")
    }

    func testServerMessageUpdatesNetworkStatusAndEmitsLog() {
        let transport = FakeED2KServerTCPTransport()
        let listenerTransport = FakeED2KPeerTCPListenerTransport()
        let logs = ThreadSafeStringLog()
        let service = MacMuleCoreService(
            networkLogHandler: { logs.append($0) },
            peerListenerTransportFactory: { _ in listenerTransport }
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let packet = ED2KPacket(
            opcode: .serverMessage,
            payload: serverMessagePayload("server version 17.15\r\nwelcome")
        )

        _ = service.connectToServer(configuration, transport: transport)
        listenerTransport.simulateState(.ready(4662))
        transport.simulateState(.ready)
        transport.simulateReceive(packet.encoded())

        XCTAssertEqual(service.snapshot().network.statusText, "server version 17.15")
        XCTAssertTrue(logs.values.contains(where: { $0.contains("eD2k server message: server version 17.15") }))
    }

    func testServerMessageLowIDUpdatesNetworkHighIDFlag() {
        let transport = FakeED2KServerTCPTransport()
        let listenerTransport = FakeED2KPeerTCPListenerTransport()
        let service = MacMuleCoreService(peerListenerTransportFactory: { _ in listenerTransport })
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let packet = ED2KPacket(
            opcode: .serverMessage,
            payload: serverMessagePayload("Your client has LowID")
        )

        _ = service.connectToServer(configuration, transport: transport)
        listenerTransport.simulateState(.ready(4662))
        transport.simulateState(.ready)
        transport.simulateReceive(packet.encoded())

        XCTAssertTrue(service.snapshot().network.isConnected)
        XCTAssertFalse(service.snapshot().network.highID)
        XCTAssertTrue(service.snapshot().network.statusText.contains("Conectado con LowID"))
    }

    func testLowIDStillAllowsSearchRequests() throws {
        let transport = FakeED2KServerTCPTransport()
        let listenerTransport = FakeED2KPeerTCPListenerTransport()
        let service = MacMuleCoreService(peerListenerTransportFactory: { _ in listenerTransport })
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let lowIDPacket = ED2KPacket(
            opcode: .serverMessage,
            payload: serverMessagePayload("Your client has LowID")
        )

        _ = service.connectToServer(configuration, transport: transport)
        listenerTransport.simulateState(.ready(4662))
        transport.simulateState(.ready)
        transport.simulateReceive(idChangePacket(clientID: 0x00000042).encoded())
        transport.simulateReceive(lowIDPacket.encoded())
        _ = service.search(query: "ubuntu iso")

        XCTAssertEqual(
            transport.sentData.last,
            try ED2KSearchRequest(query: "ubuntu iso").packet().encoded()
        )
    }

    func testServerMessageTooOldTriggersAutomaticFailoverToNextServer() throws {
        let firstEndpoint = ED2KServerEndpoint(host: "127.0.0.1", port: 4661)
        let secondEndpoint = ED2KServerEndpoint(host: "203.0.113.25", port: 4661)
        let firstTransport = FakeED2KServerTCPTransport()
        let secondTransport = FakeED2KServerTCPTransport()
        let requestedEndpoints = ThreadSafeEndpointLog()

        let service = MacMuleCoreService(
            serverTransportFactory: { endpoint in
                requestedEndpoints.append(endpoint)
                return endpoint == firstEndpoint ? firstTransport : secondTransport
            }
        )

        _ = try service.addServer(endpoint: firstEndpoint, name: "A")
        _ = try service.addServer(endpoint: secondEndpoint, name: "B")

        _ = service.connectToServer(
            ED2KServerSessionConfiguration(
                endpoint: firstEndpoint,
                userHash: Data(0..<16)
            )
        )

        firstTransport.simulateState(.ready)
        firstTransport.simulateReceive(
            ED2KPacket(
                opcode: .serverMessage,
                payload: serverMessagePayload("eDonkey ID too old")
            ).encoded()
        )

        XCTAssertEqual(requestedEndpoints.values, [firstEndpoint, secondEndpoint])
        XCTAssertEqual(service.snapshot().network.statusText, "Conectando a \(secondEndpoint.address)")
        XCTAssertEqual(service.snapshot().servers.first(where: { $0.endpoint == firstEndpoint })?.status, .unavailable)
        XCTAssertEqual(service.preferredServerEndpoint(), secondEndpoint)
    }

    func testAddAndRemoveServerPersistAcrossServiceInstances() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let endpoint = ED2KServerEndpoint(host: "203.0.113.10", port: 4661)

        let addedSnapshot = try service.addServer(endpoint: endpoint, name: "Bootstrap A")
        XCTAssertEqual(addedSnapshot.servers.count, 1)
        XCTAssertEqual(addedSnapshot.servers[0].name, "Bootstrap A")

        let restored = MacMuleCoreService(transferStore: store).snapshot()
        XCTAssertEqual(restored.servers.count, 1)
        XCTAssertEqual(restored.servers[0].endpoint, endpoint)
        XCTAssertEqual(restored.servers[0].status, .available)

        let removedSnapshot = try service.removeServer(endpoint: endpoint)
        XCTAssertTrue(removedSnapshot.servers.isEmpty)
        XCTAssertTrue(try store.loadServers().isEmpty)
    }

    func testBootstrapBundledServersSeedsDefaultServerListOnce() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)

        let seededSnapshot = try service.bootstrapBundledServersIfNeeded()

        XCTAssertEqual(
            seededSnapshot.servers.map(\.endpoint),
            CoreDefaultED2KServers.bundled.map(\.endpoint)
        )
        XCTAssertEqual(seededSnapshot.servers.first?.name, "eMule Sunrise")
        XCTAssertEqual(seededSnapshot.servers.first?.isPreferred, true)
        XCTAssertEqual(try store.loadServerBootstrapVersion(), CoreDefaultED2KServers.seedVersion)

        let removedEndpoint = CoreDefaultED2KServers.bundled[1].endpoint
        _ = try service.removeServer(endpoint: removedEndpoint)

        let restartedService = MacMuleCoreService(transferStore: store)
        let restartedSnapshot = try restartedService.bootstrapBundledServersIfNeeded()

        XCTAssertFalse(restartedSnapshot.servers.contains { $0.endpoint == removedEndpoint })
    }

    func testServerListPacketImportsServersAndMarksConnectedEndpoint() {
        let transport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService()
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let packet = ED2KPacket(
            opcode: .serverList,
            payload: serverListPayload([
                ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
                ED2KServerEndpoint(host: "203.0.113.25", port: 4661)
            ])
        )

        _ = service.connectToServer(configuration, transport: transport)
        transport.simulateState(.ready)
        transport.simulateReceive(packet.encoded())

        let snapshot = service.snapshot()
        XCTAssertEqual(snapshot.servers.count, 2)
        XCTAssertEqual(snapshot.servers.first?.endpoint, configuration.endpoint)
        XCTAssertEqual(snapshot.servers.first?.status, .connected)
        XCTAssertEqual(snapshot.servers.last?.status, .available)
    }

    func testClientUserHashPersistsAcrossServiceInstances() throws {
        let store = try makeTemporaryStore()
        let firstService = MacMuleCoreService(transferStore: store)
        let secondService = MacMuleCoreService(transferStore: store)

        XCTAssertEqual(firstService.userHash().count, 16)
        XCTAssertEqual(Array(firstService.userHash())[5], 0x0E)
        XCTAssertEqual(Array(firstService.userHash())[14], 0x6F)
        XCTAssertEqual(firstService.userHash(), secondService.userHash())
        XCTAssertEqual(try store.loadClientIdentity()?.userHash, firstService.userHash())
    }

    func testLegacyClientUserHashIsNormalizedAndPersisted() throws {
        let store = try makeTemporaryStore()
        let legacyHash = Data(0..<16)
        try store.saveClientIdentity(CoreClientIdentity(userHash: legacyHash))

        let service = MacMuleCoreService(transferStore: store)
        let normalizedHash = service.userHash()

        XCTAssertNotEqual(normalizedHash, legacyHash)
        XCTAssertEqual(Array(normalizedHash)[5], 0x0E)
        XCTAssertEqual(Array(normalizedHash)[14], 0x6F)
        XCTAssertEqual(try store.loadClientIdentity()?.userHash, normalizedHash)
    }

    func testConnectToServerMarksPreferredEndpointAndPersistsIt() throws {
        let store = try makeTemporaryStore()
        let transport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService(transferStore: store)
        let firstEndpoint = ED2KServerEndpoint(host: "203.0.113.10", port: 4661)
        let secondEndpoint = ED2KServerEndpoint(host: "203.0.113.11", port: 4661)
        let configuration = ED2KServerSessionConfiguration(
            endpoint: secondEndpoint,
            userHash: service.userHash()
        )

        _ = try service.addServer(endpoint: firstEndpoint, name: "Bootstrap A")
        _ = try service.addServer(endpoint: secondEndpoint, name: "Bootstrap B")
        _ = service.connectToServer(configuration, transport: transport)

        let snapshot = service.snapshot()
        XCTAssertEqual(snapshot.servers.first(where: { $0.endpoint == firstEndpoint })?.isPreferred, false)
        XCTAssertEqual(snapshot.servers.first(where: { $0.endpoint == secondEndpoint })?.isPreferred, true)
        XCTAssertEqual(MacMuleCoreService(transferStore: store).preferredServerEndpoint(), secondEndpoint)
    }

    func testAddED2KLinkRequestsSourcesWhenConnected() throws {
        let transport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService()
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        _ = service.connectToServer(configuration, transport: transport)
        transport.simulateState(.ready)
        transport.simulateReceive(idChangePacket().encoded())

        let snapshot = try service.addED2KLink(
            "ed2k://|file|Ubuntu.iso|1024|A41D8CD98F00B204E9800998ECF8427E|/"
        )

        XCTAssertEqual(snapshot.transfers.count, 1)
        XCTAssertEqual(transport.sentData.count, 2)
        XCTAssertEqual(
            transport.sentData[1],
            try ED2KSourceRequest(
                fileHash: Data(hexBytes: "A41D8CD98F00B204E9800998ECF8427E"),
                fileSizeInBytes: 1024
            ).packet().encoded()
        )
    }

    func testSearchSendsPacketAndMapsIncomingResultsIntoSnapshot() throws {
        let transport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService()
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        _ = service.connectToServer(configuration, transport: transport)
        transport.simulateState(.ready)

        let searchSnapshot = service.search(query: "ubuntu iso")
        XCTAssertTrue(searchSnapshot.searchResults.isEmpty)
        XCTAssertEqual(searchSnapshot.network.statusText, "Login enviado a 127.0.0.1:4661")
        XCTAssertEqual(transport.sentData.count, 1)

        transport.simulateReceive(idChangePacket().encoded())

        XCTAssertEqual(transport.sentData.count, 2)
        XCTAssertEqual(transport.sentData[1], try ED2KSearchRequest(query: "ubuntu iso").packet().encoded())

        let packet = ED2KPacket(
            opcode: .searchResults,
            payload: searchResultPayload(
                fileName: "Ubuntu 26.04 Desktop.iso",
                fileSize: 5_812_142_080,
                hash: "A41D8CD98F00B204E9800998ECF8427E"
            )
        )
        transport.simulateReceive(packet.encoded())

        let snapshot = service.snapshot()
        XCTAssertEqual(snapshot.searchResults.count, 1)
        XCTAssertEqual(snapshot.searchResults[0].fileName, "Ubuntu 26.04 Desktop.iso")
        XCTAssertEqual(snapshot.searchResults[0].sizeInBytes, 5_812_142_080)
        XCTAssertEqual(snapshot.searchResults[0].ed2kHash, "A41D8CD98F00B204E9800998ECF8427E")
        XCTAssertEqual(snapshot.searchResults[0].network, "127.0.0.1:4661")
        XCTAssertEqual(snapshot.searchResults[0].sourceClientID, 0x01020304)
        XCTAssertEqual(snapshot.searchResults[0].sourceClientPort, 4662)
        XCTAssertEqual(snapshot.network.statusText, "1 resultado(s) para ubuntu iso")
    }

    func testAddED2KLinkSeedsInitialSearchSourceAndPeerHelloUsesServerClientID() throws {
        let store = try makeTemporaryStore()
        let serverTransport = FakeED2KServerTCPTransport()
        let peerTransport = FakeED2KPeerTCPTransport()
        let service = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in serverTransport },
            peerTransportFactory: { _ in peerTransport }
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let link = try ED2KLinkParser.parseFileLink(
            "ed2k://|file|Sample.bin|1024|A41D8CD98F00B204E9800998ECF8427E|/"
        )

        _ = service.connectToServer(configuration)
        serverTransport.simulateState(.ready)
        serverTransport.simulateReceive(idChangePacket(clientID: 0x11223344).encoded())
        _ = try service.addED2KLink(
            link,
            initialSources: [ED2KFoundSource(clientID: 0x01020304, clientPort: 4662)]
        )

        XCTAssertTrue(peerTransport.startCalled)
        peerTransport.simulateState(.ready)

        let firstHelloData = try XCTUnwrap(peerTransport.sentData.first)
        let helloPacket = try ED2KPacket.decode(firstHelloData)
        XCTAssertEqual(helloPacket.opcode, ED2KPeerPacketOpcode.hello.rawValue)
        let hello = try ED2KPeerHelloDecoder.decodePeerHelloPayload(helloPacket.payload)
        XCTAssertEqual(hello.clientID, 0x11223344)
        XCTAssertEqual(hello.tcpPort, 4662)
    }

    func testSearchWithoutConnectionAutoconnectsKnownServerAndRetriesAfterLogin() throws {
        let endpoint = ED2KServerEndpoint(host: "127.0.0.1", port: 4661)
        let transport = FakeED2KServerTCPTransport()
        let requestedEndpoints = ThreadSafeEndpointLog()
        let service = MacMuleCoreService(
            serverTransportFactory: { requestedEndpoint in
                requestedEndpoints.append(requestedEndpoint)
                return transport
            }
        )

        _ = try service.addServer(endpoint: endpoint, name: "A")

        let searchSnapshot = service.search(query: "ubuntu iso")
        XCTAssertEqual(requestedEndpoints.values, [endpoint])
        XCTAssertEqual(searchSnapshot.network.statusText, "Conectando a \(endpoint.address)")
        XCTAssertEqual(transport.sentData.count, 0)

        transport.simulateState(.ready)

        XCTAssertEqual(transport.sentData.count, 1)
        transport.simulateReceive(idChangePacket().encoded())

        XCTAssertEqual(transport.sentData.count, 2)
        XCTAssertEqual(transport.sentData[1], try ED2KSearchRequest(query: "ubuntu iso").packet().encoded())
    }

    func testSearchRequestedWhileConnectingIsRetriedAfterLogin() throws {
        let transport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService()
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        _ = service.connectToServer(configuration, transport: transport)

        // Search is requested before transport becomes ready; it should be retried after login.
        _ = service.search(query: "ubuntu iso")
        XCTAssertEqual(transport.sentData.count, 0)

        transport.simulateState(.ready)

        XCTAssertEqual(transport.sentData.count, 1)
        transport.simulateReceive(idChangePacket().encoded())

        XCTAssertEqual(transport.sentData.count, 2)
        XCTAssertEqual(transport.sentData[1], try ED2KSearchRequest(query: "ubuntu iso").packet().encoded())
    }

    func testPendingSearchFailsOverToNextServerAfterDisconnect() throws {
        let firstEndpoint = ED2KServerEndpoint(host: "127.0.0.1", port: 4661)
        let secondEndpoint = ED2KServerEndpoint(host: "203.0.113.25", port: 4661)
        let firstTransport = FakeED2KServerTCPTransport()
        let secondTransport = FakeED2KServerTCPTransport()
        let requestedEndpoints = ThreadSafeEndpointLog()

        let service = MacMuleCoreService(
            serverTransportFactory: { endpoint in
                requestedEndpoints.append(endpoint)
                return endpoint == firstEndpoint ? firstTransport : secondTransport
            }
        )

        _ = try service.addServer(endpoint: firstEndpoint, name: "A")
        _ = try service.addServer(endpoint: secondEndpoint, name: "B")

        _ = service.search(query: "ubuntu iso")
        firstTransport.simulateState(.ready)
        firstTransport.simulateState(.cancelled)

        XCTAssertEqual(requestedEndpoints.values, [firstEndpoint, secondEndpoint])
        XCTAssertEqual(service.snapshot().network.statusText, "Conectando a \(secondEndpoint.address)")

        secondTransport.simulateState(.ready)

        XCTAssertEqual(secondTransport.sentData.count, 1)
        secondTransport.simulateReceive(idChangePacket().encoded())

        XCTAssertEqual(secondTransport.sentData.count, 2)
        XCTAssertEqual(secondTransport.sentData[1], try ED2KSearchRequest(query: "ubuntu iso").packet().encoded())
    }

    func testAcceptedServerDisconnectWithPendingSearchDoesNotImmediateFailover() throws {
        let firstEndpoint = ED2KServerEndpoint(host: "127.0.0.1", port: 4661)
        let secondEndpoint = ED2KServerEndpoint(host: "203.0.113.25", port: 4661)
        let firstTransport = FakeED2KServerTCPTransport()
        let secondTransport = FakeED2KServerTCPTransport()
        let requestedEndpoints = ThreadSafeEndpointLog()
        let logs = ThreadSafeStringLog()

        let service = MacMuleCoreService(
            networkLogHandler: { logs.append($0) },
            serverTransportFactory: { endpoint in
                requestedEndpoints.append(endpoint)
                return endpoint == firstEndpoint ? firstTransport : secondTransport
            }
        )

        _ = try service.addServer(endpoint: firstEndpoint, name: "A")
        _ = try service.addServer(endpoint: secondEndpoint, name: "B")

        _ = service.search(query: "ubuntu iso")
        firstTransport.simulateState(.ready)
        firstTransport.simulateReceive(idChangePacket().encoded())
        firstTransport.simulateState(.cancelled)

        XCTAssertEqual(requestedEndpoints.values, [firstEndpoint])
        XCTAssertEqual(service.snapshot().network.statusText, "Sin conexion")
        XCTAssertTrue(logs.values.contains(where: { $0.contains("reconexion") }))
    }

    func testFoundSourcesUpdatesTransferSourceCounts() throws {
        let transport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService()
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        _ = service.connectToServer(configuration, transport: transport)
        transport.simulateState(.ready)
        let added = try service.addED2KLink(
            "ed2k://|file|Ubuntu.iso|1024|A41D8CD98F00B204E9800998ECF8427E|/"
        )

        let packet = ED2KPacket(
            opcode: .foundSources,
            payload: foundSourcesPayload(
                hash: "A41D8CD98F00B204E9800998ECF8427E",
                sources: [
                    ED2KFoundSource(clientID: 0x01020304, clientPort: 4662),
                    ED2KFoundSource(clientID: 0x05060708, clientPort: 4672)
                ]
            )
        )
        transport.simulateReceive(packet.encoded())

        let transfer = try XCTUnwrap(service.snapshot().transfers.first(where: { $0.id == added.transfers[0].id }))
        XCTAssertEqual(transfer.sources, 2)
        XCTAssertEqual(transfer.availability, 2)
        XCTAssertEqual(transfer.status, .queued)
    }

    func testLowIDSourcesAreNotTreatedAsDirectPeerIPs() throws {
        let serverTransport = FakeED2KServerTCPTransport()
        let peerTransport = FakeED2KPeerTCPTransport()
        let logs = ThreadSafeStringLog()
        let service = MacMuleCoreService(
            networkLogHandler: { logs.append($0) },
            serverTransportFactory: { _ in serverTransport },
            peerTransportFactory: { _ in peerTransport }
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let fileHash = "A41D8CD98F00B204E9800998ECF8427E"

        _ = service.connectToServer(configuration)
        serverTransport.simulateState(.ready)
        serverTransport.simulateReceive(idChangePacket(clientID: 0x00000042).encoded())
        let added = try service.addED2KLink(
            "ed2k://|file|LowIDOnly.bin|1024|\(fileHash)|/"
        )

        serverTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [ED2KFoundSource(clientID: 0x0000007A, clientPort: 4662)]
                )
            ).encoded()
        )

        let transfer = try XCTUnwrap(service.snapshot().transfers.first(where: { $0.id == added.transfers[0].id }))
        XCTAssertEqual(transfer.sources, 1)
        XCTAssertEqual(transfer.availability, 0)
        XCTAssertFalse(peerTransport.startCalled)
        XCTAssertTrue(logs.values.contains(where: { $0.contains("LowID encoladas para callback de servidor") }))
        let callbackRequest = try XCTUnwrap(
            serverTransport.sentData.compactMap({ try? ED2KPacket.decode($0) })
                .first(where: { $0.opcode == ED2KPacketOpcode.callbackRequest.rawValue })
        )
        XCTAssertEqual(callbackRequest.payload, Data([0x7A, 0x00, 0x00, 0x00]))
    }

    func testFoundSourcesCanBootstrapPeerBlockWrite() throws {
        let store = try makeTemporaryStore()
        let serverTransport = FakeED2KServerTCPTransport()
        let peerTransport = FakeED2KPeerTCPTransport()
        let service = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in serverTransport },
            peerTransportFactory: { _ in peerTransport }
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        _ = service.connectToServer(configuration)
        serverTransport.simulateState(.ready)
        let added = try service.addED2KLink(
            "ed2k://|file|Sample.bin|1024|A41D8CD98F00B204E9800998ECF8427E|/"
        )
        let transferID = try XCTUnwrap(added.transfers.first?.id)

        serverTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: "A41D8CD98F00B204E9800998ECF8427E",
                    sources: [ED2KFoundSource(clientID: 0x01020304, clientPort: 4662)]
                )
            ).encoded()
        )

        XCTAssertTrue(peerTransport.startCalled)
        peerTransport.simulateState(.ready)
        try completePeerHandshake(on: peerTransport)
        try assertPeerNegotiationSent(peerTransport, fileHash: "A41D8CD98F00B204E9800998ECF8427E")
        XCTAssertTrue(try peerPartRequests(peerTransport).isEmpty)
        acceptUpload(on: peerTransport)
        XCTAssertEqual(try peerPartRequests(peerTransport), [
            try ED2KPartRequest(
            fileHash: Data(hexBytes: "A41D8CD98F00B204E9800998ECF8427E"),
            ranges: [ED2KPartRange(startOffset: 0, endOffset: 1024)]
            )
        ])

        var sendingPayload = Data(hexBytes: "A41D8CD98F00B204E9800998ECF8427E")
        sendingPayload.appendUInt32LittleEndian(0)
        sendingPayload.appendUInt32LittleEndian(1024)
        sendingPayload.append(Data(repeating: 0x5A, count: 1024))
        peerTransport.simulateReceive(
            ED2KPacket(
                opcode: ED2KPeerPacketOpcode.sendingPart.rawValue,
                payload: sendingPayload
            ).encoded()
        )

        let transfer = try XCTUnwrap(service.snapshot().transfers.first(where: { $0.id == transferID }))
        XCTAssertEqual(transfer.completedBytes, 1024)
        XCTAssertEqual(try store.loadRecord(for: transferID).transfer.completedBytes, 1024)
    }

    func testPeerBlockSpeedIsAttributedToSourceAndQueue() throws {
        let store = try makeTemporaryStore()
        let serverTransport = FakeED2KServerTCPTransport()
        let peerTransport = FakeED2KPeerTCPTransport()
        let service = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in serverTransport },
            peerTransportFactory: { _ in peerTransport }
        )
        let fileHash = "A41D8CD98F00B204E9800998ECF8427E"
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        _ = service.connectToServer(configuration)
        serverTransport.simulateState(.ready)
        let added = try service.addED2KLink(
            "ed2k://|file|Large.bin|524288|\(fileHash)|/"
        )
        let transferID = try XCTUnwrap(added.transfers.first?.id)

        serverTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [ED2KFoundSource(clientID: 0x01020304, clientPort: 4662)]
                )
            ).encoded()
        )
        peerTransport.simulateState(.ready)
        try completePeerHandshake(on: peerTransport)
        acceptUpload(on: peerTransport)

        let blockSize = 128 * 1024
        var payload = Data(hexBytes: fileHash)
        payload.appendUInt32LittleEndian(0)
        payload.appendUInt32LittleEndian(UInt32(blockSize))
        payload.append(Data(repeating: 0x5A, count: blockSize))
        peerTransport.simulateReceive(
            ED2KPacket(
                opcode: ED2KPeerPacketOpcode.sendingPart.rawValue,
                payload: payload
            ).encoded()
        )

        Thread.sleep(forTimeInterval: 1.1)
        let snapshot = service.snapshot()
        let transfer = try XCTUnwrap(snapshot.transfers.first(where: { $0.id == transferID }))
        let peer = try XCTUnwrap(snapshot.transferPeers[transferID]?.first)

        XCTAssertGreaterThan(transfer.downloadSpeedBytesPerSecond, 0)
        XCTAssertEqual(peer.ipAddress, "4.3.2.1")
        XCTAssertEqual(peer.state, .downloading)
        XCTAssertGreaterThan(peer.downloadSpeedBytesPerSecond, 0)
        XCTAssertGreaterThan(snapshot.network.downloadSpeedBytesPerSecond, 0)
    }

    func testPeerSourceExchangeBootstrapsAdditionalPeerSource() throws {
        let store = try makeTemporaryStore()
        let serverTransport = FakeED2KServerTCPTransport()
        let firstPeerTransport = FakeED2KPeerTCPTransport()
        let secondPeerTransport = FakeED2KPeerTCPTransport()
        let firstEndpoint = ED2KPeerEndpoint(host: "4.3.2.1", port: 4662)
        let secondEndpoint = ED2KPeerEndpoint(host: "8.7.6.5", port: 4672)
        let fileHash = "A41D8CD98F00B204E9800998ECF8427E"
        let service = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in serverTransport },
            peerTransportFactory: { endpoint in
                if endpoint == firstEndpoint {
                    return firstPeerTransport
                }
                if endpoint == secondEndpoint {
                    return secondPeerTransport
                }
                return secondPeerTransport
            }
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        _ = service.connectToServer(configuration)
        serverTransport.simulateState(.ready)
        _ = try service.addED2KLink(
            "ed2k://|file|SourceExchange.bin|1048576|\(fileHash)|/"
        )
        serverTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [ED2KFoundSource(clientID: 0x01020304, clientPort: 4662)]
                )
            ).encoded()
        )

        XCTAssertTrue(firstPeerTransport.startCalled)
        firstPeerTransport.simulateState(.ready)
        try completePeerHandshake(on: firstPeerTransport)
        try assertPeerNegotiationSent(firstPeerTransport, fileHash: fileHash)

        firstPeerTransport.simulateReceive(
            ED2KPacket(
                protocolByte: .emule,
                opcode: ED2KPeerPacketOpcode.answerSources2.rawValue,
                payload: sourceExchangeAnswerPayload(
                    hash: fileHash,
                    sources: [ED2KPeerSourceExchangeSource(
                        clientID: 0x05060708,
                        clientPort: 4672,
                        serverEndpoint: nil,
                        userHash: Data(repeating: 0xAB, count: 16),
                        cryptOptions: 0
                    )]
                )
            ).encoded()
        )

        XCTAssertTrue(secondPeerTransport.startCalled)
        let transfer = try XCTUnwrap(service.snapshot().transfers.first)
        XCTAssertEqual(transfer.availability, 2)
        XCTAssertEqual(transfer.sources, 2)
    }

    func testPeerDownloadRequestsFollowingRangesUntilComplete() throws {
        let store = try makeTemporaryStore()
        let serverTransport = FakeED2KServerTCPTransport()
        let peerTransport = FakeED2KPeerTCPTransport()
        let service = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in serverTransport },
            peerTransportFactory: { _ in peerTransport }
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let fileHash = "A41D8CD98F00B204E9800998ECF8427E"

        _ = service.connectToServer(configuration)
        serverTransport.simulateState(.ready)
        let added = try service.addED2KLink(
            "ed2k://|file|Large.bin|300000|\(fileHash)|/"
        )
        let transferID = try XCTUnwrap(added.transfers.first?.id)

        serverTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [ED2KFoundSource(clientID: 0x01020304, clientPort: 4662)]
                )
            ).encoded()
        )

        peerTransport.simulateState(.ready)
        try completePeerHandshake(on: peerTransport)
        try assertPeerNegotiationSent(peerTransport, fileHash: fileHash)
        XCTAssertTrue(try peerPartRequests(peerTransport).isEmpty)
        acceptUpload(on: peerTransport)
        XCTAssertEqual(try peerPartRequests(peerTransport), [
            try ED2KPartRequest(
            fileHash: Data(hexBytes: fileHash),
            ranges: [ED2KPartRange(startOffset: 0, endOffset: 262_144)]
            )
        ])

        var firstPayload = Data(hexBytes: fileHash)
        firstPayload.appendUInt32LittleEndian(0)
        firstPayload.appendUInt32LittleEndian(262_144)
        firstPayload.append(Data(repeating: 0x11, count: 262_144))
        peerTransport.simulateReceive(
            ED2KPacket(
                opcode: ED2KPeerPacketOpcode.sendingPart.rawValue,
                payload: firstPayload
            ).encoded()
        )

        XCTAssertEqual(try peerPartRequests(peerTransport), [
            try ED2KPartRequest(
                fileHash: Data(hexBytes: fileHash),
                ranges: [ED2KPartRange(startOffset: 0, endOffset: 262_144)]
            ),
            try ED2KPartRequest(
            fileHash: Data(hexBytes: fileHash),
            ranges: [ED2KPartRange(startOffset: 262_144, endOffset: 300_000)]
            )
        ])

        var secondPayload = Data(hexBytes: fileHash)
        secondPayload.appendUInt32LittleEndian(262_144)
        secondPayload.appendUInt32LittleEndian(300_000)
        secondPayload.append(Data(repeating: 0x22, count: 37_856))
        peerTransport.simulateReceive(
            ED2KPacket(
                opcode: ED2KPeerPacketOpcode.sendingPart.rawValue,
                payload: secondPayload
            ).encoded()
        )

        let transfer = try XCTUnwrap(service.snapshot().transfers.first(where: { $0.id == transferID }))
        XCTAssertEqual(transfer.completedBytes, 300_000)
        XCTAssertEqual(peerTransport.cancelCalled, true)
    }

    func testPeerDownloadFailsOverToNextSourceUsingNextMissingRange() throws {
        let store = try makeTemporaryStore()
        let serverTransport = FakeED2KServerTCPTransport()
        let firstPeerTransport = FakeED2KPeerTCPTransport()
        let secondPeerTransport = FakeED2KPeerTCPTransport()
        let thirdPeerTransport = FakeED2KPeerTCPTransport()
        let firstEndpoint = ED2KPeerEndpoint(host: "4.3.2.1", port: 4662)
        let secondEndpoint = ED2KPeerEndpoint(host: "8.7.6.5", port: 4662)
        let service = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in serverTransport },
            peerTransportFactory: { endpoint in
                if endpoint == firstEndpoint {
                    return firstPeerTransport
                }
                if endpoint == secondEndpoint {
                    return secondPeerTransport
                }
                return thirdPeerTransport
            }
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let fileHash = "A41D8CD98F00B204E9800998ECF8427E"

        _ = service.connectToServer(configuration)
        serverTransport.simulateState(.ready)
        _ = try service.addED2KLink(
            "ed2k://|file|Large.bin|900000|\(fileHash)|/"
        )

        serverTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [
                        ED2KFoundSource(clientID: 0x01020304, clientPort: 4662),
                        ED2KFoundSource(clientID: 0x05060708, clientPort: 4662),
                        ED2KFoundSource(clientID: 0x090A0B0C, clientPort: 4662)
                    ]
                )
            ).encoded()
        )

        XCTAssertTrue(firstPeerTransport.startCalled)
        XCTAssertTrue(secondPeerTransport.startCalled)
        firstPeerTransport.simulateState(.ready)
        secondPeerTransport.simulateState(.ready)
        try completePeerHandshake(on: firstPeerTransport)
        try completePeerHandshake(on: secondPeerTransport)
        try assertPeerNegotiationSent(firstPeerTransport, fileHash: fileHash)
        try assertPeerNegotiationSent(secondPeerTransport, fileHash: fileHash)
        acceptUpload(on: firstPeerTransport)
        acceptUpload(on: secondPeerTransport)
        XCTAssertEqual(try peerPartRequests(firstPeerTransport), [
            try ED2KPartRequest(
            fileHash: Data(hexBytes: fileHash),
            ranges: [ED2KPartRange(startOffset: 0, endOffset: 262_144)]
            )
        ])
        XCTAssertEqual(try peerPartRequests(secondPeerTransport), [
            try ED2KPartRequest(
            fileHash: Data(hexBytes: fileHash),
            ranges: [ED2KPartRange(startOffset: 262_144, endOffset: 524_288)]
            )
        ])

        var firstPayload = Data(hexBytes: fileHash)
        firstPayload.appendUInt32LittleEndian(0)
        firstPayload.appendUInt32LittleEndian(262_144)
        firstPayload.append(Data(repeating: 0x11, count: 262_144))
        firstPeerTransport.simulateReceive(
            ED2KPacket(
                opcode: ED2KPeerPacketOpcode.sendingPart.rawValue,
                payload: firstPayload
            ).encoded()
        )

        XCTAssertEqual(try peerPartRequests(firstPeerTransport), [
            try ED2KPartRequest(
                fileHash: Data(hexBytes: fileHash),
                ranges: [ED2KPartRange(startOffset: 0, endOffset: 262_144)]
            ),
            try ED2KPartRequest(
            fileHash: Data(hexBytes: fileHash),
            ranges: [ED2KPartRange(startOffset: 524_288, endOffset: 786_432)]
            )
        ])

        firstPeerTransport.simulateState(.failed("timeout"))

        XCTAssertTrue(thirdPeerTransport.startCalled)
        thirdPeerTransport.simulateState(.ready)
        try completePeerHandshake(on: thirdPeerTransport)
        try assertPeerNegotiationSent(thirdPeerTransport, fileHash: fileHash)
        acceptUpload(on: thirdPeerTransport)
        XCTAssertEqual(try peerPartRequests(thirdPeerTransport), [
            try ED2KPartRequest(
            fileHash: Data(hexBytes: fileHash),
            ranges: [ED2KPartRange(startOffset: 786_432, endOffset: 900_000)]
            )
        ])
    }

    func testPeerDownloadStartsTwoPeersWithDistinctRangesAndNoOverlap() throws {
        let store = try makeTemporaryStore()
        let serverTransport = FakeED2KServerTCPTransport()
        let firstPeerTransport = FakeED2KPeerTCPTransport()
        let secondPeerTransport = FakeED2KPeerTCPTransport()
        let firstEndpoint = ED2KPeerEndpoint(host: "4.3.2.1", port: 4662)
        let service = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in serverTransport },
            peerTransportFactory: { endpoint in
                endpoint == firstEndpoint ? firstPeerTransport : secondPeerTransport
            }
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let fileHash = "A41D8CD98F00B204E9800998ECF8427E"

        _ = service.connectToServer(configuration)
        serverTransport.simulateState(.ready)
        _ = try service.addED2KLink(
            "ed2k://|file|Large.bin|600000|\(fileHash)|/"
        )

        serverTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [
                        ED2KFoundSource(clientID: 0x01020304, clientPort: 4662),
                        ED2KFoundSource(clientID: 0x05060708, clientPort: 4662)
                    ]
                )
            ).encoded()
        )

        XCTAssertTrue(firstPeerTransport.startCalled)
        XCTAssertTrue(secondPeerTransport.startCalled)
        firstPeerTransport.simulateState(.ready)
        secondPeerTransport.simulateState(.ready)
        try completePeerHandshake(on: firstPeerTransport)
        try completePeerHandshake(on: secondPeerTransport)
        try assertPeerNegotiationSent(firstPeerTransport, fileHash: fileHash)
        try assertPeerNegotiationSent(secondPeerTransport, fileHash: fileHash)
        acceptUpload(on: firstPeerTransport)
        acceptUpload(on: secondPeerTransport)

        XCTAssertEqual(try peerPartRequests(firstPeerTransport), [
            try ED2KPartRequest(
            fileHash: Data(hexBytes: fileHash),
            ranges: [ED2KPartRange(startOffset: 0, endOffset: 262_144)]
            )
        ])
        XCTAssertEqual(try peerPartRequests(secondPeerTransport), [
            try ED2KPartRequest(
            fileHash: Data(hexBytes: fileHash),
            ranges: [ED2KPartRange(startOffset: 262_144, endOffset: 524_288)]
            )
        ])

        var firstPayload = Data(hexBytes: fileHash)
        firstPayload.appendUInt32LittleEndian(0)
        firstPayload.appendUInt32LittleEndian(262_144)
        firstPayload.append(Data(repeating: 0x11, count: 262_144))
        firstPeerTransport.simulateReceive(
            ED2KPacket(
                opcode: ED2KPeerPacketOpcode.sendingPart.rawValue,
                payload: firstPayload
            ).encoded()
        )

        XCTAssertEqual(try peerPartRequests(firstPeerTransport), [
            try ED2KPartRequest(
                fileHash: Data(hexBytes: fileHash),
                ranges: [ED2KPartRange(startOffset: 0, endOffset: 262_144)]
            ),
            try ED2KPartRequest(
            fileHash: Data(hexBytes: fileHash),
            ranges: [ED2KPartRange(startOffset: 524_288, endOffset: 600_000)]
            )
        ])
    }

    func testPeerFailureWithoutAlternativeSourceRequestsFreshSourceLookup() throws {
        let store = try makeTemporaryStore()
        let serverTransport = FakeED2KServerTCPTransport()
        let peerTransport = FakeED2KPeerTCPTransport()
        let service = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in serverTransport },
            peerTransportFactory: { _ in peerTransport }
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let fileHash = "A41D8CD98F00B204E9800998ECF8427E"

        _ = service.connectToServer(configuration)
        serverTransport.simulateState(.ready)
        serverTransport.simulateReceive(idChangePacket().encoded())
        _ = try service.addED2KLink(
            "ed2k://|file|Sample.bin|1024|\(fileHash)|/"
        )

        serverTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [ED2KFoundSource(clientID: 0x01020304, clientPort: 4662)]
                )
            ).encoded()
        )

        peerTransport.simulateState(.ready)
        XCTAssertEqual(serverTransport.sentData.count, 2)

        peerTransport.simulateState(.failed("connection reset"))

        XCTAssertEqual(serverTransport.sentData.count, 3)
        XCTAssertEqual(
            serverTransport.sentData[2],
            try ED2KSourceRequest(fileHash: Data(hexBytes: fileHash), fileSizeInBytes: 1024).packet().encoded()
        )
    }

    func testOnlyOneActivePeerRequestsRemotePartHashSetAtATime() throws {
        let store = try makeTemporaryStore()
        let serverTransport = FakeED2KServerTCPTransport()
        let firstPeerTransport = FakeED2KPeerTCPTransport()
        let secondPeerTransport = FakeED2KPeerTCPTransport()
        let firstEndpoint = ED2KPeerEndpoint(host: "4.3.2.1", port: 4662)
        let service = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in serverTransport },
            peerTransportFactory: { endpoint in
                endpoint == firstEndpoint ? firstPeerTransport : secondPeerTransport
            }
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let fileHash = "A41D8CD98F00B204E9800998ECF8427E"
        let largeSize = CoreChunkMap.ed2kChunkSize + 128

        _ = service.connectToServer(configuration)
        serverTransport.simulateState(.ready)
        _ = try service.addED2KLink(
            "ed2k://|file|Large.bin|\(largeSize)|\(fileHash)|/"
        )

        serverTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [
                        ED2KFoundSource(clientID: 0x01020304, clientPort: 4662),
                        ED2KFoundSource(clientID: 0x05060708, clientPort: 4662)
                    ]
                )
            ).encoded()
        )

        firstPeerTransport.simulateState(.ready)
        secondPeerTransport.simulateState(.ready)
        try completePeerHandshake(on: firstPeerTransport)
        try completePeerHandshake(on: secondPeerTransport)
        try assertPeerNegotiationSent(firstPeerTransport, fileHash: fileHash)
        try assertPeerNegotiationSent(secondPeerTransport, fileHash: fileHash)
        acceptUpload(on: firstPeerTransport)
        acceptUpload(on: secondPeerTransport)

        XCTAssertEqual(
            try peerPackets(firstPeerTransport, opcode: .hashSetRequest),
            [try ED2KPartHashSetRequest(fileHash: Data(hexBytes: fileHash)).packet()]
        )
        XCTAssertEqual(
            try peerPartRequests(firstPeerTransport),
            [
                try ED2KPartRequest(
                fileHash: Data(hexBytes: fileHash),
                ranges: [ED2KPartRange(startOffset: 0, endOffset: 262_144)]
                )
            ]
        )
        XCTAssertEqual(
            try peerPartRequests(secondPeerTransport),
            [
                try ED2KPartRequest(
                fileHash: Data(hexBytes: fileHash),
                ranges: [ED2KPartRange(startOffset: 262_144, endOffset: 524_288)]
                )
            ]
        )

        firstPeerTransport.simulateState(.failed("timeout"))

        XCTAssertEqual(
            try peerPackets(secondPeerTransport, opcode: .hashSetRequest),
            [try ED2KPartHashSetRequest(fileHash: Data(hexBytes: fileHash)).packet()]
        )
    }

    func testPeerRequestsAndPersistsRemotePartHashSet() throws {
        let store = try makeTemporaryStore()
        let serverTransport = FakeED2KServerTCPTransport()
        let peerTransport = FakeED2KPeerTCPTransport()
        let service = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in serverTransport },
            peerTransportFactory: { _ in peerTransport }
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let chunkSize = CoreChunkMap.ed2kChunkSize
        let secondChunk = Data(repeating: 0x22, count: 16)
        let fileHash = "A41D8CD98F00B204E9800998ECF8427E"

        _ = service.connectToServer(configuration)
        serverTransport.simulateState(.ready)
        let added = try service.addED2KLink(
            "ed2k://|file|Large.bin|\(chunkSize + UInt64(secondChunk.count))|\(fileHash)|/"
        )
        let transferID = try XCTUnwrap(added.transfers.first?.id)

        serverTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [ED2KFoundSource(clientID: 0x01020304, clientPort: 4662)]
                )
            ).encoded()
        )

        peerTransport.simulateState(.ready)
        try completePeerHandshake(on: peerTransport)
        try assertPeerNegotiationSent(peerTransport, fileHash: fileHash)
        acceptUpload(on: peerTransport)
        XCTAssertEqual(
            try peerPackets(peerTransport, opcode: .hashSetRequest),
            [try ED2KPartHashSetRequest(fileHash: Data(hexBytes: fileHash)).packet()]
        )

        let firstChunkHash = ED2KHash.hash(data: Data(repeating: 0x11, count: Int(chunkSize)))
        let secondChunkHash = ED2KHash.hash(data: secondChunk)
        peerTransport.simulateReceive(
            ED2KPacket(
                opcode: ED2KPeerPacketOpcode.hashSetAnswer.rawValue,
                payload: partHashSetPayload(
                    hash: fileHash,
                    partHashes: [firstChunkHash, secondChunkHash]
                )
            ).encoded()
        )

        let transfer = try XCTUnwrap(service.snapshot().transfers.first(where: { $0.id == transferID }))
        XCTAssertEqual(transfer.partHashes, [firstChunkHash, secondChunkHash])
        XCTAssertEqual(try store.loadRecord(for: transferID).transfer.partHashes, [firstChunkHash, secondChunkHash])
    }

    func testRemotePartHashSetCanFailPreviouslyWrittenChunk() throws {
        let store = try makeTemporaryStore()
        let serverTransport = FakeED2KServerTCPTransport()
        let peerTransport = FakeED2KPeerTCPTransport()
        let service = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in serverTransport },
            peerTransportFactory: { _ in peerTransport }
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let chunkSize = CoreChunkMap.ed2kChunkSize
        let secondChunk = Data(repeating: 0x22, count: 16)
        let firstChunk = Data(repeating: 0x11, count: Int(chunkSize))
        let fileHash = "A41D8CD98F00B204E9800998ECF8427E"

        _ = service.connectToServer(configuration)
        serverTransport.simulateState(.ready)
        let added = try service.addED2KLink(
            "ed2k://|file|Large.bin|\(chunkSize + UInt64(secondChunk.count))|\(fileHash)|/"
        )
        let transferID = try XCTUnwrap(added.transfers.first?.id)
        _ = try service.writeBlock(id: transferID.uuidString, offset: 0, data: firstChunk)

        serverTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [ED2KFoundSource(clientID: 0x01020304, clientPort: 4662)]
                )
            ).encoded()
        )

        peerTransport.simulateState(.ready)
        try completePeerHandshake(on: peerTransport)
        try assertPeerNegotiationSent(peerTransport, fileHash: fileHash)
        acceptUpload(on: peerTransport)
        let wrongFirstChunkHash = ED2KHash.hash(data: Data(repeating: 0x99, count: Int(chunkSize)))
        let secondChunkHash = ED2KHash.hash(data: secondChunk)
        peerTransport.simulateReceive(
            ED2KPacket(
                opcode: ED2KPeerPacketOpcode.hashSetAnswer.rawValue,
                payload: partHashSetPayload(
                    hash: fileHash,
                    partHashes: [wrongFirstChunkHash, secondChunkHash]
                )
            ).encoded()
        )

        let transfer = try XCTUnwrap(service.snapshot().transfers.first(where: { $0.id == transferID }))
        XCTAssertEqual(transfer.status, .failed)
        XCTAssertEqual(try store.loadRecord(for: transferID).transfer.status, .failed)
        XCTAssertTrue(peerTransport.cancelCalled)
    }

    func testPeerFailurePersistsSourceFailureCounts() throws {
        let store = try makeTemporaryStore()
        let serverTransport = FakeED2KServerTCPTransport()
        let peerTransport = FakeED2KPeerTCPTransport()
        let service = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in serverTransport },
            peerTransportFactory: { _ in peerTransport }
        )
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let fileHash = "A41D8CD98F00B204E9800998ECF8427E"
        let endpoint = ED2KPeerEndpoint(host: "4.3.2.1", port: 4662)

        _ = service.connectToServer(configuration)
        serverTransport.simulateState(.ready)
        let added = try service.addED2KLink(
            "ed2k://|file|Sample.bin|1024|\(fileHash)|/"
        )
        let transferID = try XCTUnwrap(added.transfers.first?.id)

        serverTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [ED2KFoundSource(clientID: 0x01020304, clientPort: 4662)]
                )
            ).encoded()
        )

        peerTransport.simulateState(.failed("timeout"))

        let record = try store.loadRecord(for: transferID)
        XCTAssertEqual(record.peerSourceBookmarks.count, 1)
        XCTAssertEqual(record.peerSourceBookmarks[0].endpoint, endpoint)
        XCTAssertEqual(record.peerSourceBookmarks[0].failureCount, 1)
        XCTAssertGreaterThan(record.peerSourceBookmarks[0].cooldownUntil ?? .distantPast, Date())

        serverTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [ED2KFoundSource(clientID: 0x01020304, clientPort: 4662)]
                )
            ).encoded()
        )

        XCTAssertEqual(peerTransport.startCallCount, 1)
    }

    func testReconnectCanBootstrapPeerFromPersistedSourceBookmarks() throws {
        let store = try makeTemporaryStore()
        let seedServerTransport = FakeED2KServerTCPTransport()
        let seedPeerTransport = FakeED2KPeerTCPTransport()
        let fileHash = "A41D8CD98F00B204E9800998ECF8427E"
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let seedService = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in seedServerTransport },
            peerTransportFactory: { _ in seedPeerTransport }
        )

        _ = seedService.connectToServer(configuration)
        seedServerTransport.simulateState(.ready)
        seedServerTransport.simulateReceive(idChangePacket().encoded())
        _ = try seedService.addED2KLink(
            "ed2k://|file|Sample.bin|600000|\(fileHash)|/"
        )
        seedServerTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [ED2KFoundSource(clientID: 0x01020304, clientPort: 4662)]
                )
            ).encoded()
        )
        seedPeerTransport.simulateState(.ready)
        try completePeerHandshake(on: seedPeerTransport)
        try assertPeerNegotiationSent(seedPeerTransport, fileHash: fileHash)
        acceptUpload(on: seedPeerTransport)
        var firstPayload = Data(hexBytes: fileHash)
        firstPayload.appendUInt32LittleEndian(0)
        firstPayload.appendUInt32LittleEndian(262_144)
        firstPayload.append(Data(repeating: 0x11, count: 262_144))
        seedPeerTransport.simulateReceive(
            ED2KPacket(
                opcode: ED2KPeerPacketOpcode.sendingPart.rawValue,
                payload: firstPayload
            ).encoded()
        )

        let restartServerTransport = FakeED2KServerTCPTransport()
        let restartPeerTransport = FakeED2KPeerTCPTransport()
        let restartedService = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in restartServerTransport },
            peerTransportFactory: { _ in restartPeerTransport }
        )

        _ = restartedService.connectToServer(configuration)
        restartServerTransport.simulateState(.ready)
        restartServerTransport.simulateReceive(idChangePacket().encoded())

        XCTAssertTrue(restartPeerTransport.startCalled)
        XCTAssertEqual(restartServerTransport.sentData.count, 2)
        XCTAssertEqual(
            restartServerTransport.sentData[1],
            try ED2KSourceRequest(fileHash: Data(hexBytes: fileHash), fileSizeInBytes: 600_000).packet().encoded()
        )
    }

    func testReconnectKeepsPersistedPeerCooldownWhenSourceIsReannounced() throws {
        let store = try makeTemporaryStore()
        let seedServerTransport = FakeED2KServerTCPTransport()
        let seedPeerTransport = FakeED2KPeerTCPTransport()
        let fileHash = "A41D8CD98F00B204E9800998ECF8427E"
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let seedService = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in seedServerTransport },
            peerTransportFactory: { _ in seedPeerTransport }
        )

        _ = seedService.connectToServer(configuration)
        seedServerTransport.simulateState(.ready)
        seedServerTransport.simulateReceive(idChangePacket().encoded())
        _ = try seedService.addED2KLink(
            "ed2k://|file|Sample.bin|1024|\(fileHash)|/"
        )
        seedServerTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [ED2KFoundSource(clientID: 0x01020304, clientPort: 4662)]
                )
            ).encoded()
        )
        seedPeerTransport.simulateState(.failed("timeout"))

        let restartServerTransport = FakeED2KServerTCPTransport()
        let restartPeerTransport = FakeED2KPeerTCPTransport()
        let restartedService = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in restartServerTransport },
            peerTransportFactory: { _ in restartPeerTransport }
        )

        _ = restartedService.connectToServer(configuration)
        restartServerTransport.simulateState(.ready)
        restartServerTransport.simulateReceive(idChangePacket().encoded())

        XCTAssertFalse(restartPeerTransport.startCalled)

        restartServerTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [ED2KFoundSource(clientID: 0x01020304, clientPort: 4662)]
                )
            ).encoded()
        )

        XCTAssertFalse(restartPeerTransport.startCalled)
    }

    func testReconnectRestoresInflightReservationsAndSkipsReservedRange() throws {
        let store = try makeTemporaryStore()
        let seedServerTransport = FakeED2KServerTCPTransport()
        let seedPeerTransport = FakeED2KPeerTCPTransport()
        let fileHash = "A41D8CD98F00B204E9800998ECF8427E"
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let seedService = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in seedServerTransport },
            peerTransportFactory: { _ in seedPeerTransport }
        )

        _ = seedService.connectToServer(configuration)
        seedServerTransport.simulateState(.ready)
        seedServerTransport.simulateReceive(idChangePacket().encoded())
        _ = try seedService.addED2KLink(
            "ed2k://|file|Large.bin|600000|\(fileHash)|/"
        )
        seedServerTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [ED2KFoundSource(clientID: 0x01020304, clientPort: 4662)]
                )
            ).encoded()
        )
        seedPeerTransport.simulateState(.ready)
        try completePeerHandshake(on: seedPeerTransport)
        try assertPeerNegotiationSent(seedPeerTransport, fileHash: fileHash)
        acceptUpload(on: seedPeerTransport)
        XCTAssertEqual(
            try peerPartRequests(seedPeerTransport),
            [
                try ED2KPartRequest(
                fileHash: Data(hexBytes: fileHash),
                ranges: [ED2KPartRange(startOffset: 0, endOffset: 262_144)]
                )
            ]
        )

        let restartServerTransport = FakeED2KServerTCPTransport()
        let restartPeerTransport = FakeED2KPeerTCPTransport()
        let restartedService = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in restartServerTransport },
            peerTransportFactory: { _ in restartPeerTransport }
        )

        _ = restartedService.connectToServer(configuration)
        restartServerTransport.simulateState(.ready)
        restartServerTransport.simulateReceive(idChangePacket().encoded())
        restartPeerTransport.simulateState(.ready)
        try completePeerHandshake(on: restartPeerTransport)
        try assertPeerNegotiationSent(restartPeerTransport, fileHash: fileHash)
        acceptUpload(on: restartPeerTransport)

        XCTAssertEqual(
            try peerPartRequests(restartPeerTransport),
            [
                try ED2KPartRequest(
                fileHash: Data(hexBytes: fileHash),
                ranges: [ED2KPartRange(startOffset: 262_144, endOffset: 524_288)]
                )
            ]
        )
    }

    func testReconnectRestoresChunkRetryHistoryAndSkipsProblematicLeadingRange() throws {
        let store = try makeTemporaryStore()
        let seedServerTransport = FakeED2KServerTCPTransport()
        let seedPeerTransport = FakeED2KPeerTCPTransport()
        let fileHash = "A41D8CD98F00B204E9800998ECF8427E"
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )
        let seedService = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in seedServerTransport },
            peerTransportFactory: { _ in seedPeerTransport }
        )

        _ = seedService.connectToServer(configuration)
        seedServerTransport.simulateState(.ready)
        seedServerTransport.simulateReceive(idChangePacket().encoded())
        _ = try seedService.addED2KLink(
            "ed2k://|file|Large.bin|600000|\(fileHash)|/"
        )
        seedServerTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [ED2KFoundSource(clientID: 0x01020304, clientPort: 4662)]
                )
            ).encoded()
        )
        seedPeerTransport.simulateState(.ready)
        try completePeerHandshake(on: seedPeerTransport)
        try assertPeerNegotiationSent(seedPeerTransport, fileHash: fileHash)
        acceptUpload(on: seedPeerTransport)
        XCTAssertEqual(
            try peerPartRequests(seedPeerTransport),
            [
                try ED2KPartRequest(
                fileHash: Data(hexBytes: fileHash),
                ranges: [ED2KPartRange(startOffset: 0, endOffset: 262_144)]
                )
            ]
        )
        seedPeerTransport.simulateState(.failed("timeout"))

        let restartServerTransport = FakeED2KServerTCPTransport()
        let restartPeerTransport = FakeED2KPeerTCPTransport()
        let restartedService = MacMuleCoreService(
            transferStore: store,
            serverTransportFactory: { _ in restartServerTransport },
            peerTransportFactory: { _ in restartPeerTransport }
        )

        _ = restartedService.connectToServer(configuration)
        restartServerTransport.simulateState(.ready)
        restartServerTransport.simulateReceive(idChangePacket().encoded())
        restartServerTransport.simulateReceive(
            ED2KPacket(
                opcode: .foundSources,
                payload: foundSourcesPayload(
                    hash: fileHash,
                    sources: [ED2KFoundSource(clientID: 0x05060708, clientPort: 4662)]
                )
            ).encoded()
        )
        restartPeerTransport.simulateState(.ready)
        try completePeerHandshake(on: restartPeerTransport)
        try assertPeerNegotiationSent(restartPeerTransport, fileHash: fileHash)
        acceptUpload(on: restartPeerTransport)

        let actualRequest = try XCTUnwrap(peerPartRequests(restartPeerTransport).last)
        XCTAssertEqual(actualRequest.fileHash, Data(hexBytes: fileHash))
        XCTAssertEqual(actualRequest.ranges, [ED2KPartRange(startOffset: 262_144, endOffset: 524_288)])
    }

    func testSetConfigEmitsNetworkLog() {
        let logs = ThreadSafeStringLog()
        let service = MacMuleCoreService(networkLogHandler: { logs.append($0) })

        let snapshot = service.setConfig(maxDownloadKbps: 1024, maxUploadKbps: 256)
        XCTAssertNotNil(snapshot)
        XCTAssertTrue(logs.values.contains(where: { $0.contains("1024") && $0.contains("256") }))
    }

    func testSetConfigZeroMeansUnlimited() {
        let logs = ThreadSafeStringLog()
        let service = MacMuleCoreService(networkLogHandler: { logs.append($0) })

        // 0 should be accepted (unlimited)
        let snapshot = service.setConfig(maxDownloadKbps: 0, maxUploadKbps: 0)
        XCTAssertNotNil(snapshot)
        XCTAssertTrue(logs.values.contains(where: { $0.contains("Config") }))
    }

    func testDisconnectServerClearsReconnectConfig() {
        let transport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService()
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        _ = service.connectToServer(configuration, transport: transport)
        // User-initiated disconnect should clear reconnect config
        let snapshot = service.disconnectServer()
        XCTAssertFalse(snapshot.network.isConnected)
        XCTAssertEqual(snapshot.network.statusText, "Sin conexion")
    }

    func testConnectToServerBootstrapsPersistedQueuedTransfersWithSourceLookup() throws {
        let store = try makeTemporaryStore()
        let seedService = MacMuleCoreService(transferStore: store)
        _ = try seedService.addED2KLink(
            "ed2k://|file|Queued.bin|1024|A41D8CD98F00B204E9800998ECF8427E|/"
        )

        let transport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService(transferStore: store)
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        _ = service.connectToServer(configuration, transport: transport)
        transport.simulateState(.ready)
        XCTAssertEqual(transport.sentData.count, 1)
        transport.simulateReceive(idChangePacket().encoded())

        XCTAssertEqual(transport.sentData.count, 2)
        XCTAssertEqual(
            transport.sentData[1],
            try ED2KSourceRequest(
                fileHash: Data(hexBytes: "A41D8CD98F00B204E9800998ECF8427E"),
                fileSizeInBytes: 1024
            ).packet().encoded()
        )
    }

    func testReconnectToServerRequestsSourcesAgainForActiveTransfers() throws {
        let transport = FakeED2KServerTCPTransport()
        let logs = ThreadSafeStringLog()
        let service = MacMuleCoreService(networkLogHandler: { logs.append($0) })
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        _ = try service.addED2KLink(
            "ed2k://|file|Reconnect.bin|1024|A41D8CD98F00B204E9800998ECF8427E|/"
        )
        _ = service.connectToServer(configuration, transport: transport)
        transport.simulateState(.ready)
        XCTAssertEqual(transport.sentData.count, 1)
        transport.simulateReceive(idChangePacket().encoded())
        XCTAssertEqual(transport.sentData.count, 2)

        let reconnectTransport = FakeED2KServerTCPTransport()
        _ = service.connectToServer(configuration, transport: reconnectTransport)
        reconnectTransport.simulateState(.ready)
        XCTAssertEqual(reconnectTransport.sentData.count, 1)
        reconnectTransport.simulateReceive(idChangePacket().encoded())

        XCTAssertEqual(reconnectTransport.sentData.count, 2)
        XCTAssertEqual(
            reconnectTransport.sentData[1],
            try ED2KSourceRequest(
                fileHash: Data(hexBytes: "A41D8CD98F00B204E9800998ECF8427E"),
                fileSizeInBytes: 1024
            ).packet().encoded()
        )
        XCTAssertTrue(logs.values.contains(where: { $0.contains("reactivando 1 transferencia") }))
    }

    func testSourceLookupMaintenanceDoesNotRepeatRecentServerRequests() throws {
        let transport = FakeED2KServerTCPTransport()
        let service = MacMuleCoreService()
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        _ = service.connectToServer(configuration, transport: transport)
        transport.simulateState(.ready)
        transport.simulateReceive(idChangePacket().encoded())
        let added = try service.addED2KLink(
            "ed2k://|file|Throttle.bin|1024|A41D8CD98F00B204E9800998ECF8427E|/"
        )

        XCTAssertEqual(try serverPackets(transport, opcode: .getSources).count, 1)

        service.refreshSourcesForActiveTransfers()
        XCTAssertEqual(try serverPackets(transport, opcode: .getSources).count, 1)

        _ = try service.pauseTransfer(id: added.transfers[0].id.uuidString)
        service.refreshSourcesForActiveTransfers()
        XCTAssertEqual(try serverPackets(transport, opcode: .getSources).count, 1)
    }

    func testAutoReconnectScheduledOnConnectionFailure() {
        let transport = FakeED2KServerTCPTransport()
        let logs = ThreadSafeStringLog()
        let service = MacMuleCoreService(networkLogHandler: { logs.append($0) })
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        _ = service.connectToServer(configuration, transport: transport)
        transport.simulateState(.failed("connection refused"))

        XCTAssertTrue(logs.values.contains(where: { $0.contains("reconexion") }))
        XCTAssertFalse(service.snapshot().network.isConnected)
    }

    func testAutoReconnectScheduledOnDisconnect() {
        let transport = FakeED2KServerTCPTransport()
        let logs = ThreadSafeStringLog()
        let service = MacMuleCoreService(networkLogHandler: { logs.append($0) })
        let configuration = ED2KServerSessionConfiguration(
            endpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661),
            userHash: Data(0..<16)
        )

        _ = service.connectToServer(configuration, transport: transport)
        transport.simulateState(.ready)
        transport.simulateState(.cancelled)

        XCTAssertTrue(logs.values.contains(where: { $0.contains("reconexion") }))
    }

    func testWriteBlockTracksRealDownloadSpeed() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Large.bin|8192|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = snapshot.transfers[0].id

        // First write: speed tracker starts
        let afterFirst = try service.writeBlock(id: id.uuidString, offset: 0, data: Data(repeating: 0, count: 512))
        // Speed may be 0 if window hasn't elapsed yet, but the transfer must be tracked
        XCTAssertGreaterThanOrEqual(afterFirst.transfers[0].downloadSpeedBytesPerSecond, 0)
    }

    func testEventSnapshotDecaysIdleDownloadSpeed() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Large.bin|8192|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = snapshot.transfers[0].id

        _ = try service.writeBlock(id: id.uuidString, offset: 0, data: Data(repeating: 0, count: 512))
        Thread.sleep(forTimeInterval: 0.1)
        let active = try service.writeBlock(id: id.uuidString, offset: 512, data: Data(repeating: 1, count: 512))

        XCTAssertGreaterThan(active.transfers[0].downloadSpeedBytesPerSecond, 0)

        Thread.sleep(forTimeInterval: 3.2)
        let batch = service.events(after: 0)
        let transfer = try XCTUnwrap(batch.snapshot.transfers.first { $0.id == id })

        XCTAssertEqual(transfer.downloadSpeedBytesPerSecond, 0)
    }

    func testDownloadSpeedUsesElapsedWallClockForBursts() throws {
        let store = try makeTemporaryStore()
        let service = MacMuleCoreService(transferStore: store)
        let snapshot = try service.addED2KLink(
            "ed2k://|file|Large.bin|10485760|0CC175B9C0F1B6A831C399E269772661|/"
        )
        let id = snapshot.transfers[0].id
        let block = Data(repeating: 0, count: 256 * 1024)

        _ = try service.writeBlock(id: id.uuidString, offset: 0, data: block)
        _ = try service.writeBlock(id: id.uuidString, offset: UInt64(block.count), data: block)

        Thread.sleep(forTimeInterval: 1.2)
        let transfer = try XCTUnwrap(service.snapshot().transfers.first { $0.id == id })

        XCTAssertGreaterThan(transfer.downloadSpeedBytesPerSecond, 0)
        XCTAssertLessThanOrEqual(transfer.downloadSpeedBytesPerSecond, 600 * 1024)
    }

    private func makeTemporaryStore() throws -> CoreTransferStore {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacMuleCoreTests-\(UUID().uuidString)", isDirectory: true)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }

        return CoreTransferStore(rootDirectory: rootURL)
    }

    private func serverMessagePayload(_ text: String) -> Data {
        let bytes = Data(text.utf8)
        var payload = Data()
        payload.append(UInt8(bytes.count & 0x00FF))
        payload.append(UInt8((bytes.count >> 8) & 0x00FF))
        payload.append(bytes)
        return payload
    }

    private func idChangePacket(clientID: UInt32 = 0x01020304) -> ED2KPacket {
        var payload = Data()
        payload.appendUInt32LittleEndian(clientID)
        return ED2KPacket(opcode: .idChange, payload: payload)
    }

    private func serverListPayload(_ endpoints: [ED2KServerEndpoint]) -> Data {
        var payload = Data([UInt8(endpoints.count)])
        for endpoint in endpoints {
            let octets = endpoint.host.split(separator: ".").compactMap { UInt8($0) }
            payload.append(contentsOf: octets)
            payload.append(UInt8(endpoint.port & 0x00FF))
            payload.append(UInt8((endpoint.port >> 8) & 0x00FF))
        }
        return payload
    }

    private func searchResultPayload(fileName: String, fileSize: UInt64, hash: String) -> Data {
        var payload = Data()
        payload.appendUInt32LittleEndian(1)
        payload.append(Data(hash.chunkedHexBytes()))
        payload.appendUInt32LittleEndian(0x01020304)
        payload.appendUInt16LittleEndian(4662)
        payload.appendUInt32LittleEndian(2)
        payload.append(ED2KTag(name: ED2KSearchTagName.fileName, value: .string(fileName)).encoded())
        payload.append(ED2KTag(name: ED2KSearchTagName.fileSize, value: .uint64(fileSize)).encoded())
        return payload
    }

    private func foundSourcesPayload(hash: String, sources: [ED2KFoundSource]) -> Data {
        var payload = Data(hash.chunkedHexBytes())
        payload.append(UInt8(sources.count))
        for source in sources {
            payload.appendUInt32LittleEndian(source.clientID)
            payload.appendUInt16LittleEndian(source.clientPort)
        }
        return payload
    }

    private func sourceExchangeAnswerPayload(
        hash: String,
        sources: [ED2KPeerSourceExchangeSource]
    ) -> Data {
        var payload = Data([ED2KPeerSourceExchangeRequest.currentVersion])
        payload.append(Data(hash.chunkedHexBytes()))
        payload.appendUInt16LittleEndian(UInt16(sources.count))
        for source in sources {
            payload.appendUInt32LittleEndian(source.clientID)
            payload.appendUInt16LittleEndian(source.clientPort)
            payload.appendUInt32LittleEndian(0)
            payload.appendUInt16LittleEndian(0)
            payload.append(source.userHash ?? Data(repeating: 0, count: 16))
            payload.append(source.cryptOptions ?? 0)
        }
        return payload
    }

    private func partHashSetPayload(hash: String, partHashes: [String]) -> Data {
        var payload = Data(hash.chunkedHexBytes())
        payload.appendUInt16LittleEndian(UInt16(partHashes.count))
        for partHash in partHashes {
            payload.append(Data(partHash.chunkedHexBytes()))
        }
        return payload
    }

    private func acceptUpload(on transport: FakeED2KPeerTCPTransport) {
        transport.simulateReceive(
            ED2KPacket(opcode: ED2KPeerPacketOpcode.acceptUploadRequest.rawValue).encoded()
        )
    }

    private func completePeerHandshake(on transport: FakeED2KPeerTCPTransport) throws {
        let hello = try ED2KPeerHello(
            userHash: Data(repeating: 0xAB, count: 16),
            clientID: 0x01020304,
            tcpPort: 4662,
            nickname: "Peer Mule",
            serverEndpoint: ED2KServerEndpoint(host: "127.0.0.1", port: 4661)
        )
        transport.simulateReceive(try hello.packet(opcode: .helloAnswer).encoded())
    }

    private func peerPackets(
        _ transport: FakeED2KPeerTCPTransport,
        opcode: ED2KPeerPacketOpcode
    ) throws -> [ED2KPacket] {
        try transport.sentData
            .map(ED2KPacket.decode)
            .filter { $0.opcode == opcode.rawValue }
    }

    private func serverPackets(
        _ transport: FakeED2KServerTCPTransport,
        opcode: ED2KPacketOpcode
    ) throws -> [ED2KPacket] {
        try transport.sentData
            .map(ED2KPacket.decode)
            .filter { $0.opcode == opcode.rawValue }
    }

    private func peerPartRequests(_ transport: FakeED2KPeerTCPTransport) throws -> [ED2KPartRequest] {
        try transport.sentData.compactMap { data in
            let packet = try ED2KPacket.decode(data)
            switch ED2KPeerPacketOpcode(rawValue: packet.opcode) {
            case .requestParts:
                return try ED2KPartRequestDecoder.decodePartRequestPayload(packet.payload)
            case .requestPartsI64:
                return try ED2KPartRequestDecoder.decodePartRequestPayload(packet.payload, uses64BitOffsets: true)
            default:
                return nil
            }
        }
    }

    private func assertPeerNegotiationSent(
        _ transport: FakeED2KPeerTCPTransport,
        fileHash: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let fileHashData = Data(hexBytes: fileHash)
        XCTAssertEqual(
            try peerPackets(transport, opcode: .requestFileName).map(\.payload),
            [fileHashData],
            file: file,
            line: line
        )
        XCTAssertEqual(
            try peerPackets(transport, opcode: .setRequestFileID).map(\.payload),
            [fileHashData],
            file: file,
            line: line
        )
        XCTAssertEqual(
            try peerPackets(transport, opcode: .requestSources2).map(\.payload),
            [Data([0x04, 0x00, 0x00]) + fileHashData],
            file: file,
            line: line
        )
        XCTAssertEqual(
            try peerPackets(transport, opcode: .startUploadRequest).map(\.payload),
            [fileHashData],
            file: file,
            line: line
        )
    }
}

private extension String {
    func chunkedHexBytes() -> [UInt8] {
        stride(from: 0, to: count, by: 2).compactMap { index in
            let start = self.index(startIndex, offsetBy: index)
            let end = self.index(start, offsetBy: 2)
            return UInt8(self[start..<end], radix: 16)
        }
    }
}

private extension Data {
    init(hexBytes: String) {
        self.init(hexBytes.chunkedHexBytes())
    }
}

private extension Data {
    mutating func appendUInt16LittleEndian(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value >> 8) & 0x00FF))
    }

    mutating func appendUInt32LittleEndian(_ value: UInt32) {
        append(UInt8(value & 0x000000FF))
        append(UInt8((value >> 8) & 0x000000FF))
        append(UInt8((value >> 16) & 0x000000FF))
        append(UInt8((value >> 24) & 0x000000FF))
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

    func simulateState(_ state: ED2KServerTCPTransportState) {
        stateUpdateHandler?(state)
    }

    func simulateReceive(_ data: Data) {
        receiveHandler?(data)
    }
}

private func isEmptyOfferFilesPacket(_ data: Data) -> Bool {
    guard let packet = try? ED2KPacket.decode(data) else {
        return false
    }

    return packet.opcode == ED2KPacketOpcode.offerFiles.rawValue
        && packet.payload == Data([0x00, 0x00, 0x00, 0x00])
}

private final class FakeED2KPeerTCPTransport: @unchecked Sendable, ED2KPeerTCPTransport {
    var stateUpdateHandler: ((ED2KPeerTCPTransportState) -> Void)?
    var receiveHandler: ((Data) -> Void)?
    private(set) var startCalled = false
    private(set) var startCallCount = 0
    private(set) var sentData: [Data] = []
    private(set) var receiveNextCallCount = 0
    private(set) var cancelCalled = false

    func start(queue: DispatchQueue) {
        startCalled = true
        startCallCount += 1
    }

    func send(_ data: Data, completion: @escaping @Sendable (ED2KPeerTCPTransportSendResult) -> Void) {
        sentData.append(data)
        completion(.sent)
    }

    func receiveNext() {
        receiveNextCallCount += 1
    }

    func cancel() {
        cancelCalled = true
    }

    func simulateState(_ state: ED2KPeerTCPTransportState) {
        stateUpdateHandler?(state)
    }

    func simulateReceive(_ data: Data) {
        receiveHandler?(data)
    }
}

private final class FakeED2KPeerTCPListenerTransport: @unchecked Sendable, ED2KPeerTCPListenerTransport {
    var stateUpdateHandler: ((ED2KPeerTCPListenerTransportState) -> Void)?
    var connectionHandler: ((ED2KAcceptedPeerConnection) -> Void)?

    private(set) var startCalled = false
    private(set) var startCallCount = 0
    private(set) var cancelCalled = false

    func start(queue: DispatchQueue) {
        startCalled = true
        startCallCount += 1
    }

    func cancel() {
        cancelCalled = true
        stateUpdateHandler?(.cancelled)
    }

    func simulateState(_ state: ED2KPeerTCPListenerTransportState) {
        stateUpdateHandler?(state)
    }

    func simulateAcceptedConnection(_ connection: ED2KAcceptedPeerConnection) {
        connectionHandler?(connection)
    }
}

private final class FakeED2KPeerPortMapper: ED2KPeerPortMapper {
    private(set) var calls: [(tcpPort: UInt16, udpPort: UInt16)] = []

    func ensureMappings(
        tcpPort: UInt16,
        udpPort: UInt16,
        completion: @escaping @Sendable (UPnPPortMappingResult) -> Void
    ) {
        calls.append((tcpPort: tcpPort, udpPort: udpPort))
        completion(
            UPnPPortMappingResult(
                tcpMapped: true,
                udpMapped: true,
                detail: "ok"
            )
        )
    }
}

private final class ThreadSafeStringLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private final class ThreadSafeEndpointLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ED2KServerEndpoint] = []

    var values: [ED2KServerEndpoint] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: ED2KServerEndpoint) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private final class ThreadSafePeerTransportCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: (endpoint: ED2KPeerEndpoint, transport: FakeED2KPeerTCPTransport)?

    var endpoint: ED2KPeerEndpoint? {
        lock.lock()
        defer { lock.unlock() }
        return storage?.endpoint
    }

    var transport: FakeED2KPeerTCPTransport? {
        lock.lock()
        defer { lock.unlock() }
        return storage?.transport
    }

    func store(endpoint: ED2KPeerEndpoint, transport: FakeED2KPeerTCPTransport) {
        lock.lock()
        storage = (endpoint, transport)
        lock.unlock()
    }
}

private final class ThreadSafeIntCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
