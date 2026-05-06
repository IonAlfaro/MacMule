import Foundation

public struct CoreDefaultED2KServer: Equatable, Sendable {
    public var name: String
    public var endpoint: ED2KServerEndpoint

    public init(name: String, endpoint: ED2KServerEndpoint) {
        self.name = name
        self.endpoint = endpoint
    }
}

public enum CoreDefaultED2KServers {
    public static let seedVersion = 3

    public static let bundled: [CoreDefaultED2KServer] = [
        CoreDefaultED2KServer(
            name: "eMule Sunrise",
            endpoint: ED2KServerEndpoint(host: "176.123.5.89", port: 4725)
        ),
        CoreDefaultED2KServer(
            name: "Mazinga Server",
            endpoint: ED2KServerEndpoint(host: "37.15.61.236", port: 4232)
        ),
        CoreDefaultED2KServer(
            name: "Sharing-Devils No.4",
            endpoint: ED2KServerEndpoint(host: "91.208.162.87", port: 4232)
        ),
        CoreDefaultED2KServer(
            name: "eMule Security",
            endpoint: ED2KServerEndpoint(host: "45.82.80.155", port: 5687)
        ),
        CoreDefaultED2KServer(
            name: "Sharing-Devils No.2",
            endpoint: ED2KServerEndpoint(host: "85.121.5.137", port: 4232)
        ),
        CoreDefaultED2KServer(
            name: "Sharing-Devils No.1",
            endpoint: ED2KServerEndpoint(host: "176.123.2.239", port: 4232)
        ),
        CoreDefaultED2KServer(
            name: "Astra-3",
            endpoint: ED2KServerEndpoint(host: "213.252.245.239", port: 43333)
        ),
    ]
}
