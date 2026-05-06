import SwiftUI

struct KadTabView: View {
    @EnvironmentObject private var store: MacMuleStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "Kad", subtitle: "Kademlia network", systemImage: "circle.hexagongrid")

            HSplitView {
                VStack(spacing: MacMuleTheme.spacingLG) {
                    KadStatusBanner()
                    KadBootstrapSection()
                    KadIndexStatsSection()
                    Spacer()
                }
                .frame(minWidth: 300)
                .padding(MacMuleTheme.spacingLG)

                VStack(spacing: MacMuleTheme.spacingLG) {
                    KadRoutingSection()
                    KadNodeListSection()
                }
                .padding(MacMuleTheme.spacingLG)
            }
        }
        .macMulePageBackground()
    }
}

// MARK: - Status Banner

private struct KadStatusBanner: View {
    @EnvironmentObject private var store: MacMuleStore

    var body: some View {
        HStack(spacing: MacMuleTheme.spacingMD) {
            Image(systemName: kadStatusIcon)
                .font(.title)
                .foregroundStyle(kadStatusColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.kad.isRunning ? "Kad active" : "Kad inactive")
                    .font(.headline)

                if store.kad.isRunning {
                    Text(store.kad.isConnected
                        ? "Connected to the Kademlia network with \(store.kad.nodeCount) nodes."
                        : "Connecting to the Kademlia network...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if store.kad.isFirewalled {
                        Label("Firewalled — limited connectivity", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("Start Kad to search for sources and content without depending on eD2k servers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(store.kad.isRunning ? "Stop" : "Start") {
                store.kad.isRunning ? store.kadStop() : store.kadStart()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(store.kad.isRunning ? .red : .green)
        }
        .padding(MacMuleTheme.spacingLG)
        .macMuleElevated()
        .overlay {
            RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
                .strokeBorder(kadStatusColor.opacity(0.2), lineWidth: 1)
        }
    }

    private var kadStatusIcon: String {
        "circle.hexagongrid"
    }

    private var kadStatusColor: Color {
        if !store.kad.isRunning { return .secondary }
        if !store.kad.isConnected { return .orange }
        return store.kad.isFirewalled ? .orange : .green
    }
}

// MARK: - Bootstrap Section

private struct KadBootstrapSection: View {
    @EnvironmentObject private var store: MacMuleStore

    var body: some View {
        VStack(alignment: .leading, spacing: MacMuleTheme.spacingSM) {
            Label("Manual bootstrap", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)

            HStack(spacing: 6) {
                TextField("Node IP", text: $store.kadBootstrapHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                TextField("Port", text: $store.kadBootstrapPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Connect") { store.kadBootstrap() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(store.kadBootstrapHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Manually connect to a known Kad node to start the routing table.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(MacMuleTheme.spacingLG)
        .macMuleElevated()
    }
}

// MARK: - Routing Section

private struct KadRoutingSection: View {
    @EnvironmentObject private var store: MacMuleStore

    var body: some View {
        VStack(alignment: .leading, spacing: MacMuleTheme.spacingSM) {
            Label("Routing table", systemImage: "circle.grid.3x3")
                .font(.headline)

            if store.kadBucketStats.isEmpty {
                Text("The routing table will fill as you connect to more nodes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, MacMuleTheme.spacingMD)
            } else {
                KadRoutingGraph(stats: store.kadBucketStats)
            }

            HStack(spacing: MacMuleTheme.spacingXL) {
                MetricBadge(label: "Nodes", value: "\(store.kad.nodeCount)", icon: "circle.fill", color: .blue)
                MetricBadge(label: "Buckets", value: "\(store.kadBucketStats.count)", icon: "square.grid.3x3", color: .green)
                MetricBadge(label: "Searches", value: "\(store.kad.activeSearchCount)", icon: "magnifyingglass", color: .purple)
            }
        }
        .padding(MacMuleTheme.spacingLG)
        .macMuleElevated()
    }
}

private struct KadRoutingGraph: View {
    let stats: [KadBucketStat]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(stats) { bucket in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bucketColor(bucket.fullness))
                            .frame(width: 14, height: max(4, CGFloat(bucket.count) * 3))
                        Text("\(bucket.depth)")
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 48)
            .padding(.vertical, 3)
        }
    }

    private func bucketColor(_ fullness: Double) -> Color {
        switch fullness {
        case 0..<0.25: Color.secondary.opacity(0.35)
        case 0.25..<0.5: .blue.opacity(0.45)
        case 0.5..<0.75: .blue.opacity(0.65)
        default: .blue
        }
    }
}

private struct MetricBadge: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Node List Section

private struct KadNodeListSection: View {
    @EnvironmentObject private var store: MacMuleStore

    var body: some View {
        VStack(alignment: .leading, spacing: MacMuleTheme.spacingSM) {
            Label("Known nodes", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)

            if store.kadNodes.isEmpty {
                Text("There are no nodes in the routing table yet. Connect to a bootstrap node or wait for Kad to connect automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, MacMuleTheme.spacingMD)
            } else {
                VStack(spacing: 0) {
                    KadNodeRowHeader()
                    Divider()
                    ForEach(store.kadNodes.prefix(20)) { node in
                        KadNodeRow(node: node)
                        if node.id != store.kadNodes.prefix(20).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(MacMuleTheme.spacingLG)
        .macMuleElevated()
    }
}

private struct KadNodeRowHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Node ID")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(width: 140, alignment: .leading)
            Text("IP")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(width: 140, alignment: .leading)
            Text("Port")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)
            Text("Distance")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .leading)
            Text("Seen")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 5)
    }
}

private struct KadNodeRow: View {
    let node: KadNode

    var body: some View {
        HStack(spacing: 6) {
            Text(node.nodeIDPrefix)
                .font(.caption.monospaced())
                .frame(width: 140, alignment: .leading)
                .lineLimit(1)
            Text(node.ipAddress)
                .font(.caption)
                .frame(width: 140, alignment: .leading)
                .lineLimit(1)
            Text("\(node.udpPort)")
                .font(.caption.monospacedDigit())
                .frame(width: 70, alignment: .leading)
            Text(node.distance)
                .font(.caption.monospaced())
                .frame(width: 80, alignment: .leading)
            Text(node.lastSeenText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Index Stats Section

private struct KadIndexStatsSection: View {
    @EnvironmentObject private var store: MacMuleStore

    var body: some View {
        VStack(alignment: .leading, spacing: MacMuleTheme.spacingSM) {
            Label("Local storage", systemImage: "internaldrive")
                .font(.headline)

            HStack(spacing: MacMuleTheme.spacingXL) {
                MetricBadge(label: "Keywords", value: "\(store.kad.totalKeywords)", icon: "text.word.spacing", color: .indigo)
                MetricBadge(label: "Sources", value: "\(store.kad.totalSources)", icon: "person.2", color: .teal)
            }

            Text("Data indexed locally by the Kad network. Useful for serverless searches.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(MacMuleTheme.spacingLG)
        .macMuleElevated()
    }
}
