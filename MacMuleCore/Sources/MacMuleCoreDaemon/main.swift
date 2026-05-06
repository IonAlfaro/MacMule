import Darwin
import Foundation
import MacMuleCore

let arguments = CommandLine.arguments
let storageRoot = explicitStorageRoot(in: arguments) ?? defaultStorageRoot()
let transferStore = CoreTransferStore(
    rootDirectory: storageRoot,
    tempDirectory: explicitTempDirectory(in: arguments),
    incomingDirectory: explicitIncomingDirectory(in: arguments)
)
let service = MacMuleCoreService(
    transferStore: transferStore,
    networkLogHandler: { message in
        print(message)
        fflush(stdout)
    }
)
do {
    try service.bootstrapBundledServersIfNeeded()
} catch {
    print("eD2k bundled server bootstrap failed: \(error.localizedDescription)")
    fflush(stdout)
}
let handler = CoreRPCHandler(service: service)

if arguments.contains("--socket") {
    print("macmule-core-daemon storage: \(storageRoot.path)")
    fflush(stdout)
}

if let socketFlagIndex = arguments.firstIndex(of: "--socket") {
    guard arguments.indices.contains(socketFlagIndex + 1) else {
        fputs("Missing socket path after --socket\n", stderr)
        exit(64)
    }

    let socketPath = arguments[socketFlagIndex + 1]

    do {
        try CoreSocketServer(socketPath: socketPath, handler: handler).run()
    } catch {
        fputs("macmule-core-daemon socket error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

while let line = readLine() {
    let response = handler.handle(Data(line.utf8))
    if let output = String(data: response, encoding: .utf8) {
        print(output)
        fflush(stdout)
    }
}

private func explicitStorageRoot(in arguments: [String]) -> URL? {
    guard let storageFlagIndex = arguments.firstIndex(of: "--storage") else {
        return nil
    }

    guard arguments.indices.contains(storageFlagIndex + 1) else {
        fputs("Missing storage path after --storage\n", stderr)
        exit(64)
    }

    return URL(fileURLWithPath: arguments[storageFlagIndex + 1], isDirectory: true)
}

private func explicitIncomingDirectory(in arguments: [String]) -> URL? {
    guard let incomingFlagIndex = arguments.firstIndex(of: "--incoming-dir") else {
        return nil
    }

    guard arguments.indices.contains(incomingFlagIndex + 1) else {
        fputs("Missing incoming directory path after --incoming-dir\n", stderr)
        exit(64)
    }

    return URL(fileURLWithPath: arguments[incomingFlagIndex + 1], isDirectory: true)
}

private func explicitTempDirectory(in arguments: [String]) -> URL? {
    guard let tempFlagIndex = arguments.firstIndex(of: "--temp-dir") else {
        return nil
    }

    guard arguments.indices.contains(tempFlagIndex + 1) else {
        fputs("Missing temp directory path after --temp-dir\n", stderr)
        exit(64)
    }

    return URL(fileURLWithPath: arguments[tempFlagIndex + 1], isDirectory: true)
}

private func defaultStorageRoot() -> URL {
    let fileManager = FileManager.default
    let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    let baseURL = applicationSupport ?? fileManager.temporaryDirectory

    return baseURL
        .appendingPathComponent("MacMule", isDirectory: true)
        .appendingPathComponent("Core", isDirectory: true)
}
