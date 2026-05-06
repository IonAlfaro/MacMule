import XCTest
@testable import MacMuleCore

final class NATPMPPortMapperTests: XCTestCase {
    func testMappingRequestEncodesPortsAndLifetimeInBigEndian() {
        let request = NATPMPPortMapper.makeMappingRequest(
            protocolOpcode: 1,
            internalPort: 4662,
            requestedExternalPort: 4662,
            lifetime: 3600
        )

        XCTAssertEqual(
            Array(request),
            [0x00, 0x01, 0x00, 0x00, 0x12, 0x36, 0x12, 0x36, 0x00, 0x00, 0x0E, 0x10]
        )
    }

    func testMappingResponseParserReadsSuccessfulReply() throws {
        let response = Data([
            0x00, 0x81,
            0x00, 0x00,
            0x00, 0x00, 0x00, 0x2A,
            0x12, 0x36,
            0x23, 0x45,
            0x00, 0x00, 0x0E, 0x10
        ])

        let parsed = try NATPMPPortMapper.parseMappingResponse(response, expectedOpcode: 1)

        XCTAssertEqual(parsed.protocolOpcode, 1)
        XCTAssertEqual(parsed.resultCode, .success)
        XCTAssertEqual(parsed.epoch, 42)
        XCTAssertEqual(parsed.internalPort, 4662)
        XCTAssertEqual(parsed.externalPort, 9029)
        XCTAssertEqual(parsed.lifetime, 3600)
    }

    func testSequentialPeerPortMapperFallsBackToSecondMapper() {
        let first = FakePeerPortMapper(
            result: UPnPPortMappingResult(
                tcpMapped: false,
                udpMapped: false,
                detail: "UPnP sin IGD."
            )
        )
        let second = FakePeerPortMapper(
            result: UPnPPortMappingResult(
                tcpMapped: true,
                udpMapped: true,
                detail: "NAT-PMP publico ambos puertos."
            )
        )
        let mapper = SequentialPeerPortMapper(
            mappers: [
                ("UPnP", first),
                ("NAT-PMP", second)
            ]
        )
        let expectation = expectation(description: "mapping")
        let captured = LockedResultBox()

        mapper.ensureMappings(tcpPort: 4662, udpPort: 4672) { result in
            captured.value = result
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(first.calls.count, 1)
        XCTAssertEqual(second.calls.count, 1)
        XCTAssertEqual(captured.value?.tcpMapped, true)
        XCTAssertEqual(captured.value?.udpMapped, true)
        XCTAssertEqual(
            captured.value?.detail,
            "UPnP: UPnP sin IGD. NAT-PMP: NAT-PMP publico ambos puertos."
        )
    }
}

private final class FakePeerPortMapper: ED2KPeerPortMapper {
    let result: UPnPPortMappingResult
    private(set) var calls: [(tcpPort: UInt16, udpPort: UInt16)] = []

    init(result: UPnPPortMappingResult) {
        self.result = result
    }

    func ensureMappings(
        tcpPort: UInt16,
        udpPort: UInt16,
        completion: @escaping @Sendable (UPnPPortMappingResult) -> Void
    ) {
        calls.append((tcpPort: tcpPort, udpPort: udpPort))
        completion(result)
    }
}

private final class LockedResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: UPnPPortMappingResult?

    var value: UPnPPortMappingResult? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
