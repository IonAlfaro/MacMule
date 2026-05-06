import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject private var store: MacMuleStore

    var body: some View {
        HStack(spacing: MacMuleTheme.spacingLG) {
            connectionIndicator
            Divider().frame(height: 14)
            speedIndicator
            Divider().frame(height: 14)
            kadIndicator
            Spacer()
            diskIndicator
        }
        .padding(.horizontal, MacMuleTheme.spacingMD)
        .padding(.vertical, 5)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .top)
        .frame(height: 32)
    }

    private var connectionIndicator: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(connectionColor)
                .frame(width: 6, height: 6)
            Text(connectionText)
                .font(.caption)
        }
        .frame(minWidth: 110, alignment: .leading)
    }

    private var speedIndicator: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                Image(systemName: "arrow.down")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text(downloadSpeedText)
                    .font(.caption.monospacedDigit())
            }
            HStack(spacing: 3) {
                Image(systemName: "arrow.up")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text(uploadSpeedText)
                    .font(.caption.monospacedDigit())
            }
        }
        .frame(minWidth: 160, alignment: .leading)
    }

    private var kadIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.hexagongrid")
                .font(.caption)
                .foregroundStyle(kadColor)
            Text(kadStatusText)
                .font(.caption.monospacedDigit())
        }
        .frame(minWidth: 90, alignment: .leading)
    }

    private var diskIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "internaldrive")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(diskSpaceText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 90, alignment: .trailing)
    }

    private var connectionColor: Color {
        if !store.network.isConnected { return .secondary.opacity(0.4) }
        return store.network.highID ? .green : .orange
    }

    private var connectionText: String {
        if !store.network.isConnected { return "Disconnected" }
        return store.network.highID ? "High ID" : "Low ID"
    }

    private var downloadSpeedText: String {
        ByteCountFormatter.macMuleString(store.totalDownloadSpeed) + "/s"
    }

    private var uploadSpeedText: String {
        ByteCountFormatter.macMuleString(store.totalUploadSpeed) + "/s"
    }

    private var kadColor: Color {
        if !store.kad.isRunning { return .secondary }
        if !store.kad.isConnected { return .orange }
        return store.kad.isFirewalled ? .orange : .green
    }

    private var kadStatusText: String {
        if !store.kad.isRunning { return "Kad: Off" }
        return "Kad: \(store.kad.nodeCount)"
    }

    private var diskSpaceText: String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let available = values.volumeAvailableCapacityForImportantUsage {
                return ByteCountFormatter.macMuleString(Int64(available))
            }
        } catch {}
        return "—"
    }
}
