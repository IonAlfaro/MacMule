import Darwin
import Foundation

public enum CoreSocketServerError: Error, LocalizedError {
    case pathTooLong(String)
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case acceptFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .pathTooLong(let path):
            return "Unix socket path is too long: \(path)."
        case .socketCreationFailed(let errnoCode):
            return "Could not create Unix socket: errno \(errnoCode)."
        case .bindFailed(let errnoCode):
            return "Could not bind Unix socket: errno \(errnoCode)."
        case .listenFailed(let errnoCode):
            return "Could not listen on Unix socket: errno \(errnoCode)."
        case .acceptFailed(let errnoCode):
            return "Could not accept Unix socket connection: errno \(errnoCode)."
        }
    }
}

public final class CoreSocketServer {
    private let socketPath: String
    private let handler: CoreRPCHandler

    public init(socketPath: String, handler: CoreRPCHandler = CoreRPCHandler()) {
        self.socketPath = socketPath
        self.handler = handler
    }

    public func run() throws {
        let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            throw CoreSocketServerError.socketCreationFailed(errno)
        }
        defer {
            close(serverFD)
            unlink(socketPath)
        }

        try bindServerSocket(serverFD)

        guard listen(serverFD, SOMAXCONN) == 0 else {
            throw CoreSocketServerError.listenFailed(errno)
        }

        while true {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else {
                throw CoreSocketServerError.acceptFailed(errno)
            }

            handleConnection(clientFD)
            close(clientFD)
        }
    }

    private func bindServerSocket(_ serverFD: Int32) throws {
        unlink(socketPath)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString.map { UInt8(bitPattern: $0) }
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw CoreSocketServerError.pathTooLong(socketPath)
        }

        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.copyBytes(from: pathBytes)
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(serverFD, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            throw CoreSocketServerError.bindFailed(errno)
        }
    }

    private func handleConnection(_ clientFD: Int32) {
        var bufferedInput = Data()
        var readBuffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = read(clientFD, &readBuffer, readBuffer.count)
            if bytesRead <= 0 {
                return
            }

            bufferedInput.append(readBuffer, count: bytesRead)

            while let newlineIndex = bufferedInput.firstIndex(of: 0x0A) {
                let request = bufferedInput[..<newlineIndex]
                bufferedInput.removeSubrange(...newlineIndex)

                guard request.isEmpty == false else {
                    continue
                }

                var response = handler.handle(Data(request))
                response.append(0x0A)
                writeAll(response, to: clientFD)
            }
        }
    }

    private func writeAll(_ data: Data, to fileDescriptor: Int32) {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }

            var bytesWritten = 0
            while bytesWritten < data.count {
                let result = write(
                    fileDescriptor,
                    baseAddress.advanced(by: bytesWritten),
                    data.count - bytesWritten
                )

                guard result > 0 else {
                    return
                }

                bytesWritten += result
            }
        }
    }
}
