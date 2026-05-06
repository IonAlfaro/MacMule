import SwiftUI

struct SourceInspectorView: View {
    @EnvironmentObject private var store: MacMuleStore

    private var downloadName: String {
        store.selectedDownload?.fileName ?? "Sources"
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(
                title: downloadName,
                subtitle: "Download sources"
            )

            Divider()

            sourcesTable
        }
    }

    @ViewBuilder
    private var sourcesTable: some View {
        Table(SourceDetail.mock) {
            TableColumn("Status", value: \.stateText)
                .width(min: 80, ideal: 140)
            TableColumn("Client") { source in
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.clientName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(source.clientSoftware)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .width(min: 120, ideal: 200)
            TableColumn("Speed") { source in
                Text(ByteCountFormatter.macMuleString(source.downloadSpeedBytesPerSecond) + "/s")
                    .font(.caption.monospacedDigit())
            }
            .width(min: 80, ideal: 90)
            TableColumn("Parts") { source in
                Text("\(source.partsAvailable)/\(source.totalParts)")
                    .font(.caption.monospacedDigit())
            }
            .width(min: 60, ideal: 70)
            TableColumn("Queue") { source in
                Text("\(source.queueRank)")
                    .font(.caption.monospacedDigit())
            }
            .width(min: 40, ideal: 50)
            TableColumn("Score") { source in
                Text(String(format: "%.1f", source.score))
                    .font(.caption.monospacedDigit())
            }
            .width(min: 70, ideal: 80)
            TableColumn("Seen") { source in
                Text(source.lastSeen.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 90)
        }
    }
}

extension SourceDetail {
    static let mock: [SourceDetail] = [
        SourceDetail(
            id: "1",
            clientName: "eMule v0.60a [User1]",
            clientSoftware: "eMule v0.60a",
            ipAddress: "192.168.1.10",
            port: 4662,
            state: .downloading,
            queueRank: 0,
            downloadSpeedBytesPerSecond: 256_000,
            partsAvailable: 42,
            totalParts: 100,
            lastSeen: Date().addingTimeInterval(-12),
            a4afFiles: [],
            score: 9.8
        ),
        SourceDetail(
            id: "2",
            clientName: "aMule 2.3.3 [User2]",
            clientSoftware: "aMule 2.3.3",
            ipAddress: "10.0.0.5",
            port: 4672,
            state: .onQueue,
            queueRank: 15,
            downloadSpeedBytesPerSecond: 0,
            partsAvailable: 65,
            totalParts: 100,
            lastSeen: Date().addingTimeInterval(-30),
            a4afFiles: ["file1", "file2"],
            score: 7.2
        ),
        SourceDetail(
            id: "3",
            clientName: "eMule v0.50a [User3]",
            clientSoftware: "eMule v0.50a",
            ipAddress: "172.16.0.20",
            port: 4662,
            state: .connecting,
            queueRank: 0,
            downloadSpeedBytesPerSecond: 0,
            partsAvailable: 0,
            totalParts: 100,
            lastSeen: Date().addingTimeInterval(-3),
            a4afFiles: [],
            score: 3.1
        ),
        SourceDetail(
            id: "4",
            clientName: "MLDonkey 3.1.7 [User4]",
            clientSoftware: "MLDonkey 3.1.7",
            ipAddress: "192.168.0.50",
            port: 4662,
            state: .noNeededParts,
            queueRank: 0,
            downloadSpeedBytesPerSecond: 0,
            partsAvailable: 0,
            totalParts: 100,
            lastSeen: Date().addingTimeInterval(-300),
            a4afFiles: [],
            score: 1.5
        ),
        SourceDetail(
            id: "5",
            clientName: "eMule v0.60a [User5]",
            clientSoftware: "eMule v0.60a",
            ipAddress: "10.10.0.88",
            port: 4662,
            state: .error,
            queueRank: 0,
            downloadSpeedBytesPerSecond: 0,
            partsAvailable: 10,
            totalParts: 100,
            lastSeen: Date().addingTimeInterval(-120),
            a4afFiles: ["file3"],
            score: 5.6
        ),
    ]
}
