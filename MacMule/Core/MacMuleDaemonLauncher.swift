import Darwin
import Foundation
import MacMuleCore

@MainActor
final class MacMuleDaemonSession {
    let socketPath: String
    let storageDirectory: URL?
    let incomingDirectory: URL?
    let tempDirectory: URL?
    let ownsProcess: Bool

    private let process: Process?
    private let outputPipe: Pipe?
    private let errorPipe: Pipe?
    private(set) var logs: [MacMuleCoreLogEntry] = []

    var isRunning: Bool {
        process?.isRunning ?? true
    }

    init(
        socketPath: String,
        storageDirectory: URL?,
        incomingDirectory: URL?,
        tempDirectory: URL?,
        process: Process,
        outputPipe: Pipe,
        errorPipe: Pipe
    ) {
        self.socketPath = socketPath
        self.storageDirectory = storageDirectory
        self.incomingDirectory = incomingDirectory
        self.tempDirectory = tempDirectory
        self.process = process
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        ownsProcess = true

        appendLog(.info, "Daemon iniciado en \(socketPath).")
        observe(pipe: outputPipe, level: .info)
        observe(pipe: errorPipe, level: .error)

        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            guard let self else { return }

            Task { @MainActor [self] in
                self.appendLog(.warning, "Daemon finalizado con codigo \(status).")
            }
        }
    }

    init(
        attachedTo socketPath: String,
        storageDirectory: URL?,
        incomingDirectory: URL?,
        tempDirectory: URL?
    ) {
        self.socketPath = socketPath
        self.storageDirectory = storageDirectory
        self.incomingDirectory = incomingDirectory
        self.tempDirectory = tempDirectory
        process = nil
        outputPipe = nil
        errorPipe = nil
        ownsProcess = false
        appendLog(.info, "Daemon reutilizado en \(socketPath).")
    }

    deinit {
        guard ownsProcess,
              let process,
              let outputPipe,
              let errorPipe else {
            return
        }
        Self.teardown(process: process, outputPipe: outputPipe, errorPipe: errorPipe, socketPath: socketPath)
    }

    func stop() {
        guard ownsProcess,
              let process,
              let outputPipe,
              let errorPipe else {
            return
        }
        Self.teardown(process: process, outputPipe: outputPipe, errorPipe: errorPipe, socketPath: socketPath)
    }

    nonisolated private static func teardown(process: Process, outputPipe: Pipe, errorPipe: Pipe, socketPath: String) {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil

        if process.isRunning {
            process.terminate()
        }

        try? FileManager.default.removeItem(atPath: socketPath)
    }

    private func observe(pipe: Pipe, level: MacMuleCoreLogLevel) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard data.isEmpty == false else { return }

            let message = String(data: data, encoding: .utf8) ?? "\(data.count) bytes"
            guard let self else { return }

            Task { @MainActor [self, message, level] in
                self.appendOutput(message, level: level)
            }
        }
    }

    private func appendOutput(_ output: String, level: MacMuleCoreLogLevel) {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        for line in lines where line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            appendLog(level, line)
        }
    }

    private func appendLog(_ level: MacMuleCoreLogLevel, _ message: String) {
        logs.append(
            MacMuleCoreLogEntry(
                timestamp: Date(),
                level: level,
                message: message
            )
        )

        if logs.count > 200 {
            logs.removeFirst(logs.count - 200)
        }
    }
}

@MainActor
enum MacMuleCoreClientFactory {
    /// Synchronous: only returns a real client if MACMULE_CORE_SOCKET is set.
    /// Otherwise returns a lightweight empty placeholder so init() never blocks.
    /// The real daemon is launched asynchronously in MacMuleStore.start().
    static func makeDefaultClient() -> any MacMuleCoreClient {
        let environment = ProcessInfo.processInfo.environment

        if let socketPath = environment["MACMULE_CORE_SOCKET"], socketPath.isEmpty == false {
            return DaemonMacMuleCoreClient(
                socketPath: socketPath,
                baseRuntimeStatus: MacMuleCoreRuntimeStatus(
                    title: "Socket externo",
                    detail: socketPath,
                    systemImage: "point.3.connected.trianglepath.dotted",
                    isWarning: false
                )
            )
        }

        return EmptyMacMuleCoreClient()
    }

    /// Async: launches the bundled daemon and returns a real client, or nil on failure.
    static func makeRealClientAsync(
        storageDirectory: URL? = nil,
        incomingDirectory: URL? = nil,
        tempDirectory: URL? = nil
    ) async -> (any MacMuleCoreClient)? {
        let environment = ProcessInfo.processInfo.environment

        if let socketPath = environment["MACMULE_CORE_SOCKET"], socketPath.isEmpty == false {
            return DaemonMacMuleCoreClient(
                socketPath: socketPath,
                storageDirectory: storageDirectory,
                incomingDirectory: incomingDirectory,
                tempDirectory: tempDirectory,
                baseRuntimeStatus: MacMuleCoreRuntimeStatus(
                    title: "Socket externo",
                    detail: socketPath,
                    systemImage: "point.3.connected.trianglepath.dotted",
                    isWarning: false
                )
            )
        }

        guard let session = await MacMuleDaemonLauncher.launchBundledDaemonAsync(
            forceFresh: true,
            storageDirectory: storageDirectory,
            incomingDirectory: incomingDirectory,
            tempDirectory: tempDirectory
        ) else {
            return nil
        }

        return DaemonMacMuleCoreClient(
            socketPath: session.socketPath,
            daemonSession: session,
            storageDirectory: storageDirectory,
            incomingDirectory: incomingDirectory,
            tempDirectory: tempDirectory,
            baseRuntimeStatus: MacMuleCoreRuntimeStatus(
                title: "Daemon local",
                detail: "macmule-core-daemon",
                systemImage: "terminal",
                isWarning: false
            )
        )
    }
}

@MainActor
enum MacMuleDaemonLauncher {
    /// Async version — uses Task.sleep so it never blocks the main thread.
    static func launchBundledDaemonAsync(
        forceFresh: Bool = false,
        storageDirectory: URL? = nil,
        incomingDirectory: URL? = nil,
        tempDirectory: URL? = nil
    ) async -> MacMuleDaemonSession? {
        if forceFresh {
            terminateExistingLocalDaemons(storageDirectory: storageDirectory)
        } else if let attachedSession = attachToExistingDaemon(
            storageDirectory: storageDirectory,
            incomingDirectory: incomingDirectory,
            tempDirectory: tempDirectory
        ) {
            return attachedSession
        }

        let executableCandidates = daemonExecutableCandidates()

        for (index, executableURL) in executableCandidates.enumerated() {
            if let session = await launchDaemonAsync(
                executableURL: executableURL,
                storageDirectory: storageDirectory,
                incomingDirectory: incomingDirectory,
                tempDirectory: tempDirectory,
                attempt: index
            ) {
                return session
            }
        }

        return nil
    }

    /// Legacy sync version kept for internal use only.
    static func launchBundledDaemon(
        forceFresh: Bool = false,
        storageDirectory: URL? = nil,
        incomingDirectory: URL? = nil,
        tempDirectory: URL? = nil
    ) -> MacMuleDaemonSession? {
        if forceFresh {
            terminateExistingLocalDaemons(storageDirectory: storageDirectory)
        } else if let attachedSession = attachToExistingDaemon(
            storageDirectory: storageDirectory,
            incomingDirectory: incomingDirectory,
            tempDirectory: tempDirectory
        ) {
            return attachedSession
        }

        let executableCandidates = daemonExecutableCandidates()

        for (index, executableURL) in executableCandidates.enumerated() {
            if let session = launchDaemonSync(
                executableURL: executableURL,
                storageDirectory: storageDirectory,
                incomingDirectory: incomingDirectory,
                tempDirectory: tempDirectory,
                attempt: index
            ) {
                return session
            }
        }

        return nil
    }

    private static func locateDaemonExecutable() -> URL? {
        daemonExecutableCandidates().first
    }

    private static func daemonExecutableCandidates() -> [URL] {
        var orderedCandidates: [URL?] = [explicitDaemonPath()]

#if DEBUG
        orderedCandidates.append(contentsOf: developmentDaemonCandidates())
#endif

        orderedCandidates.append(bundleMainExecutableSiblingPath())
        orderedCandidates.append(Bundle.main.url(forAuxiliaryExecutable: "macmule-core-daemon"))
        orderedCandidates.append(Bundle.main.url(forResource: "macmule-core-daemon", withExtension: nil))

#if !DEBUG
        orderedCandidates.append(contentsOf: developmentDaemonCandidates())
#endif

        var seenPaths = Set<String>()
        return orderedCandidates.compactMap(\.self).filter { url in
            guard FileManager.default.isExecutableFile(atPath: url.path) else { return false }
            return seenPaths.insert(url.path).inserted
        }
    }

    private static func bundleMainExecutableSiblingPath() -> URL? {
        guard let mainExecutableURL = Bundle.main.executableURL else {
            return nil
        }
        return mainExecutableURL
            .deletingLastPathComponent()
            .appendingPathComponent("macmule-core-daemon")
    }

    private static func launchDaemonSync(
        executableURL: URL,
        storageDirectory: URL?,
        incomingDirectory: URL?,
        tempDirectory: URL?,
        attempt: Int
    ) -> MacMuleDaemonSession? {
        let socketURL = socketURL(storageDirectory: storageDirectory, attempt: attempt)

        if canConnect(to: socketURL.path) == false {
            try? FileManager.default.removeItem(at: socketURL)
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = daemonArguments(
            socketPath: socketURL.path,
            storageDirectory: storageDirectory,
            incomingDirectory: incomingDirectory,
            tempDirectory: tempDirectory
        )
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        guard waitForSocket(at: socketURL.path, timeout: 2.0) else {
            if process.isRunning { process.terminate() }
            try? FileManager.default.removeItem(at: socketURL)
            return nil
        }

        return MacMuleDaemonSession(
            socketPath: socketURL.path,
            storageDirectory: storageDirectory,
            incomingDirectory: incomingDirectory,
            tempDirectory: tempDirectory,
            process: process,
            outputPipe: outputPipe,
            errorPipe: errorPipe
        )
    }

    private static func launchDaemonAsync(
        executableURL: URL,
        storageDirectory: URL?,
        incomingDirectory: URL?,
        tempDirectory: URL?,
        attempt: Int
    ) async -> MacMuleDaemonSession? {
        let socketURL = socketURL(storageDirectory: storageDirectory, attempt: attempt)

        if canConnect(to: socketURL.path) == false {
            try? FileManager.default.removeItem(at: socketURL)
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = daemonArguments(
            socketPath: socketURL.path,
            storageDirectory: storageDirectory,
            incomingDirectory: incomingDirectory,
            tempDirectory: tempDirectory
        )
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let socketPath = socketURL.path
        let deadline = Date().addingTimeInterval(2.0)
        var ready = false
        while Date() < deadline {
            if canConnect(to: socketPath) {
                ready = true
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms — cooperative, non-blocking
        }

        guard ready else {
            if process.isRunning { process.terminate() }
            try? FileManager.default.removeItem(at: socketURL)
            return nil
        }

        return MacMuleDaemonSession(
            socketPath: socketPath,
            storageDirectory: storageDirectory,
            incomingDirectory: incomingDirectory,
            tempDirectory: tempDirectory,
            process: process,
            outputPipe: outputPipe,
            errorPipe: errorPipe
        )
    }

    private static func daemonArguments(
        socketPath: String,
        storageDirectory: URL?,
        incomingDirectory: URL?,
        tempDirectory: URL?
    ) -> [String] {
        var arguments = ["--socket", socketPath]
        if let storageDirectory {
            arguments.append(contentsOf: ["--storage", storageDirectory.path])
        }
        if let incomingDirectory {
            arguments.append(contentsOf: ["--incoming-dir", incomingDirectory.path])
        }
        if let tempDirectory {
            arguments.append(contentsOf: ["--temp-dir", tempDirectory.path])
        }
        return arguments
    }

    private static func explicitDaemonPath() -> URL? {
        guard let path = ProcessInfo.processInfo.environment["MACMULE_CORE_DAEMON_PATH"], path.isEmpty == false else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    private static func developmentDaemonCandidates() -> [URL] {
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let repositoryRoot = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return [
            repositoryRoot.appendingPathComponent("MacMuleCore/.build/debug/macmule-core-daemon"),
            repositoryRoot.appendingPathComponent("MacMuleCore/.build/arm64-apple-macosx/debug/macmule-core-daemon"),
            repositoryRoot.appendingPathComponent("MacMuleCore/.build/x86_64-apple-macosx/debug/macmule-core-daemon")
        ]
    }

    private static func attachToExistingDaemon(
        storageDirectory: URL?,
        incomingDirectory: URL?,
        tempDirectory: URL?
    ) -> MacMuleDaemonSession? {
        for socketURL in existingDaemonSocketCandidates(storageDirectory: storageDirectory) {
            if probeDaemon(at: socketURL.path) {
                return MacMuleDaemonSession(
                    attachedTo: socketURL.path,
                    storageDirectory: storageDirectory,
                    incomingDirectory: incomingDirectory,
                    tempDirectory: tempDirectory
                )
            }

            try? FileManager.default.removeItem(at: socketURL)
        }

        return nil
    }

    private static func existingDaemonSocketCandidates(storageDirectory: URL?) -> [URL] {
        if let storageDirectory {
            return [socketURL(storageDirectory: storageDirectory, attempt: 0)]
        }

        var candidates: [URL] = []
        let temporaryDirectory = FileManager.default.temporaryDirectory
        if let enumerator = FileManager.default.enumerator(at: temporaryDirectory, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                guard url.lastPathComponent.hasPrefix("macmule-core-"),
                      url.pathExtension == "sock" else {
                    continue
                }
                candidates.append(url)
            }
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.path).inserted }
    }

    private static func probeDaemon(at socketPath: String) -> Bool {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            return false
        }
        defer {
            close(fileDescriptor)
        }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fileDescriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString.map { UInt8(bitPattern: $0) }
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            return false
        }

        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.copyBytes(from: pathBytes)
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(fileDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            return false
        }

        let request = #"{"id":1,"method":"snapshot"}"#
        let requestData = Data((request + "\n").utf8)
        let writeResult = requestData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return -1 }
            return Darwin.write(fileDescriptor, baseAddress, requestData.count)
        }

        guard writeResult == requestData.count else {
            return false
        }

        var response = Data()
        var byte: UInt8 = 0

        while true {
            let bytesRead = Darwin.read(fileDescriptor, &byte, 1)
            guard bytesRead > 0 else {
                return false
            }

            if byte == 0x0A {
                break
            }
            response.append(byte)
        }

        return response.isEmpty == false
    }

    private static func terminateExistingLocalDaemons(storageDirectory: URL?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-x", "-u", String(getuid()), "macmule-core-daemon"]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Best effort cleanup only.
        }

        Thread.sleep(forTimeInterval: 0.2)

        if let storageDirectory {
            try? FileManager.default.removeItem(
                at: socketURL(storageDirectory: storageDirectory, attempt: 0)
            )
        }
    }

    private static func socketURL(storageDirectory: URL?, attempt: Int) -> URL {
        if let storageDirectory {
            try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            return storageDirectory.appendingPathComponent(
                attempt == 0 ? "macmule-core.sock" : "macmule-core-\(attempt).sock"
            )
        }

        return FileManager.default.temporaryDirectory
            .appendingPathComponent("macmule-core-\(ProcessInfo.processInfo.processIdentifier)-\(attempt).sock")
    }

    private static func waitForSocket(at socketPath: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if canConnect(to: socketPath) {
                return true
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        return false
    }

    private static func canConnect(to socketPath: String) -> Bool {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            return false
        }
        defer {
            close(fileDescriptor)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString.map { UInt8(bitPattern: $0) }
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            return false
        }

        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.copyBytes(from: pathBytes)
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(fileDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        return result == 0
    }
}

/// Minimal placeholder used while the real daemon is launching.
/// Has NO demo/mock data — just empty state.
@MainActor
fileprivate final class EmptyMacMuleCoreClient: MacMuleCoreClient {
    var runtimeStatus: MacMuleCoreRuntimeStatus {
        MacMuleCoreRuntimeStatus(title: "Starting", detail: "Connecting to the engine...", systemImage: "bolt.horizontal.circle", isWarning: false)
    }
    var runtimeLogs: [MacMuleCoreLogEntry] { [] }
    var canRestartCore: Bool { false }

    func currentSnapshot() async -> MacMuleSnapshot { .empty }
    func events(after: UInt64) async -> MacMuleEventBatch { .empty(after: after) }
    func search(query: String) async -> MacMuleSnapshot { .empty }
    func addDownload(from result: SearchResult) async -> MacMuleSnapshot { .empty }
    func addED2KLink(_ link: ED2KFileLink) async -> MacMuleSnapshot { .empty }
    func setDownloadPaused(id: TransferItem.ID, paused: Bool) async -> MacMuleSnapshot { .empty }
    func removeDownload(id: TransferItem.ID) async -> MacMuleSnapshot { .empty }
    func setConnection(enabled: Bool) async -> MacMuleSnapshot { .empty }
    func connectToServer(host: String, port: UInt16) async -> MacMuleSnapshot { .empty }
    func addServer(host: String, port: UInt16) async -> MacMuleSnapshot { .empty }
    func removeServer(host: String, port: UInt16) async -> MacMuleSnapshot { .empty }
    func importServers(servers: [(host: String, port: UInt16)]) async -> MacMuleSnapshot { .empty }
    func setConfig(maxDownloadKilobytes: Int, maxUploadKilobytes: Int) async -> MacMuleSnapshot { .empty }
    func restartCore() async -> MacMuleSnapshot { .empty }
    func kadStart() async -> MacMuleSnapshot { .empty }
    func kadStop() async -> MacMuleSnapshot { .empty }
    func kadBootstrap(host: String, port: UInt16) async -> MacMuleSnapshot { .empty }
    func kadSearchKeyword(query: String) async -> MacMuleSnapshot { .empty }
    func kadSearchSources(hash: String) async -> MacMuleSnapshot { .empty }
    func schedulerEnable(enabled: Bool) async -> MacMuleSnapshot { .empty }
    func schedulerAddEntry(title: String, days: Set<Int>, startHour: Int, startMinute: Int, endHour: Int, endMinute: Int, actions: [String]) async -> MacMuleSnapshot { .empty }
    func schedulerRemoveEntry(id: UUID) async -> MacMuleSnapshot { .empty }
    func addCategory(title: String, color: String) async -> MacMuleSnapshot { .empty }
    func removeCategory(id: UUID) async -> MacMuleSnapshot { .empty }
}
