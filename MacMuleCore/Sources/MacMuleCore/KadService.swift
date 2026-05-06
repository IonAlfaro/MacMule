import Foundation

public final class KadService: @unchecked Sendable {
    public private(set) var isRunning: Bool = false
    public private(set) var isConnected: Bool = false
    public private(set) var isFirewalled: Bool = true
    public private(set) var firewallState: KadFirewallState = .unknown

    public let routingTable: KadRoutingTable
    public var selfNodeID: KadUInt128 { routingTable.currentSelfNodeID }

    private let logHandler: (@Sendable (String) -> Void)?
    private var maintenanceTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.macmule.kad.timer")
    public var clientSearcher: KadClientSearcher?
    public var lookups: KadLookupCoordinator?

    public init(
        selfNodeID: KadUInt128 = KadUInt128.random(),
        logHandler: (@Sendable (String) -> Void)? = nil
    ) {
        self.routingTable = KadRoutingTable(selfNodeID: selfNodeID)
        self.logHandler = logHandler
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        log("Kad service started with NodeID: \(selfNodeID.hexString.prefix(16))...")
        startMaintenanceTimer()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        isConnected = false
        stopMaintenanceTimer()
        log("Kad service stopped")
    }

    public func markConnected(_ connected: Bool) {
        isConnected = connected
    }

    public func markFirewalled(_ firewalled: Bool) {
        isFirewalled = firewalled
        firewallState = firewalled ? .firewalled : .open
    }

    public func addContact(_ contact: KadContact) {
        let result = routingTable.addContact(contact)
        switch result {
        case .inserted:
            log("Kad: added contact \(contact.nodeID.hexString.prefix(12))...")
        case .updated:
            break
        case .replacedExpired:
            log("Kad: replaced expired contact in bucket")
        case .rejectedBucketFull:
            break
        }
    }

    public func bootstrap(from endpoints: [KadEndpoint]) async {
        let searcher = clientSearcher
        guard let searcher else {
            log("Kad: bootstrap skipped — no clientSearcher")
            return
        }

        log("Kad: bootstrapping from \(endpoints.count) endpoints...")

        let pings = endpoints.prefix(Int(KadConstants.alpha)).map { endpoint in
            Task.detached { [weak self] in
                guard let self = self else { return }
                let transaction = searcher.sendPing(to: KadContact(
                    nodeID: KadUInt128.random(),
                    ipAddress: endpoint.ipAddress,
                    udpPort: endpoint.port,
                    tcpPort: endpoint.port
                ))
                let tid = transaction
                log("Kad: sent PING to \(endpoint.ipAddress):\(endpoint.port) (tid: \(tid.hexString.prefix(8)))")
                // The response will be handled by KadPacketHandler.handleResponse
            }
        }

        // Wait for PINGs to be sent
        for task in pings {
            _ = await task.value
        }

        // Wait a short time for PONGs to arrive
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        isConnected = routingTable.totalContacts > 0
        log("Kad: bootstrap complete — \(routingTable.totalContacts) contacts in routing table")
    }

    public func processMaintenance() {
        guard isRunning else { return }

        let expired = routingTable.expireStale()
        if !expired.isEmpty {
            log("Kad: expired \(expired.count) stale contacts")
        }
    }

    public var nodeCount: Int {
        routingTable.totalContacts
    }

    private func startMaintenanceTimer() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 5, repeating: KadConstants.bucketRefreshInterval)
        timer.setEventHandler { [weak self] in
            self?.processMaintenance()
        }
        timer.resume()
        maintenanceTimer = timer
    }

    private func stopMaintenanceTimer() {
        maintenanceTimer?.cancel()
        maintenanceTimer = nil
    }

    private func log(_ message: String) {
        logHandler?(message)
    }
}
