import SwiftUI

struct DownloadsTabView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var selectedDownload: TransferItem.ID?
    @State private var statusFilter: TransferStatusFilter = .all
    @State private var detailTab: DownloadDetailTab = .sources
    
    enum TransferStatusFilter: String, CaseIterable {
        case all = "All"
        case downloading = "Downloading"
        case paused = "Paused"
        case completed = "Completed"
    }
    
    enum DownloadDetailTab: String, CaseIterable {
        case sources = "Sources"
        case parts = "Parts"
        case info = "Info"
    }
    
    private var filteredDownloads: [TransferItem] {
        switch statusFilter {
        case .all: store.downloads
        case .downloading: store.downloads.filter { $0.status == .downloading }
        case .paused: store.downloads.filter { $0.status == .paused }
        case .completed: store.downloads.filter { $0.status == .completed }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 12) {
                Picker("Status", selection: $statusFilter) {
                    ForEach(TransferStatusFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                
                Spacer()
                
                Text("Total: \(filteredDownloads.count) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.3))
            
            // Main split view
            VSplitView {
                // Top: Download list
                Table(filteredDownloads, selection: $selectedDownload) {
                    TableColumn("Name") { download in
                        HStack(spacing: 6) {
                            FileIcon(kind: download.kind, size: .small)
                            Text(download.fileName)
                        }
                    }
                    .width(300)
                    
                    TableColumn("Size") { download in
                        Text(download.sizeText)
                            .font(.caption.monospacedDigit())
                    }
                    .width(80)
                    
                    TableColumn("Downloaded") { download in
                        VStack(alignment: .leading, spacing: 2) {
                            ProgressView(value: download.progress)
                                .scaleEffect(y: 0.6)
                            Text("\(download.completedText) / \(download.sizeText)")
                                .font(.caption2.monospacedDigit())
                        }
                    }
                    .width(150)
                    
                    TableColumn("Speed") { download in
                        Text(download.downloadSpeedText)
                            .font(.caption.monospacedDigit())
                    }
                    .width(80)
                    
                    TableColumn("Sources") { download in
                        Text("\(download.sources)")
                            .font(.caption.monospacedDigit())
                    }
                    .width(60)
                    
                    TableColumn("Status") { download in
                        StatusBadge(status: download.status)
                    }
                    .width(100)
                }
                .tableStyle(.bordered(alternatesRowBackgrounds: true))
                
                // Bottom: Detail panel
                if let download = selectedDownload.flatMap({ id in store.downloads.first(where: { $0.id == id }) }) {
                    VStack(spacing: 0) {
                        // Detail tabs
                        Picker("Detail", selection: $detailTab) {
                            ForEach(DownloadDetailTab.allCases, id: \.self) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(8)
                        
                        Divider()
                        
                        // Tab content
                        ScrollView {
                            switch detailTab {
                            case .sources:
                                DownloadSourcesView(download: download)
                            case .parts:
                                DownloadPartsView(download: download)
                            case .info:
                                DownloadInfoView(download: download)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .background(.quaternary.opacity(0.15))
                } else {
                    VStack {
                        Spacer()
                        Text("Select a download to view details")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .background(.quaternary.opacity(0.15))
                }
            }
        }
        .onDeleteCommand {
            if let selected = selectedDownload {
                store.removeDownload(downloadID: selected)
            }
        }
    }
}

// MARK: - Detail Views

struct DownloadSourcesView: View {
    @EnvironmentObject private var store: MacMuleStore
    let download: TransferItem

    var sources: [SourceDetail] {
        store.transferPeers[download.id] ?? [
            SourceDetail(
                id: "pending",
                clientName: "Searching sources...",
                clientSoftware: "",
                ipAddress: "",
                port: 0,
                state: .connecting,
                queueRank: 0,
                downloadSpeedBytesPerSecond: 0,
                partsAvailable: 0,
                totalParts: 54,
                lastSeen: Date(),
                a4afFiles: [],
                score: 0
            )
        ]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active sources: \(sources.count)")
                .font(.headline)
            
            Table(sources) {
                TableColumn("Status") { source in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(sourceStateColor(source.state))
                            .frame(width: 6, height: 6)
                        Text(source.stateText)
                            .font(.caption)
                    }
                }
                .width(120)
                
                TableColumn("Client") { source in
                    Text(source.clientName)
                        .font(.caption)
                }
                .width(140)
                
                TableColumn("Software") { source in
                    Text(source.clientSoftware)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(100)
                
                TableColumn("Speed") { source in
                    Text(ByteCountFormatter.macMuleString(source.downloadSpeedBytesPerSecond) + "/s")
                        .font(.caption.monospacedDigit())
                }
                .width(80)
                
                TableColumn("Parts") { source in
                    Text("\(source.partsAvailable)/\(source.totalParts)")
                        .font(.caption.monospacedDigit())
                }
                .width(60)
                
                TableColumn("Queue") { source in
                    Text(source.queueRank > 0 ? "\(source.queueRank)" : "—")
                        .font(.caption.monospacedDigit())
                }
                .width(50)
                
                TableColumn("Score") { source in
                    Text(String(format: "%.1f", source.score))
                        .font(.caption.monospacedDigit())
                }
                .width(60)
            }
            .tableStyle(.bordered)
        }
        .padding()
    }
    
    private func sourceStateColor(_ state: SourceState) -> Color {
        switch state {
        case .downloading: .green
        case .connecting, .onQueue: .blue
        case .noNeededParts: .orange
        case .tooManyConnections, .banned, .error: .red
        }
    }
}

struct DownloadPartsView: View {
    let download: TransferItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Part map")
                .font(.headline)
            
            ChunkMap(chunks: download.chunks)
                .frame(height: 60)
            
            HStack(spacing: 16) {
                LegendItem(color: .gray, label: "Pending")
                LegendItem(color: .green, label: "Complete")
                LegendItem(color: .blue, label: "Active")
                LegendItem(color: .red, label: "Corrupt")
            }
            .font(.caption)
            
            Text("Progress: \(String(format: "%.1f", download.progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct DownloadInfoView: View {
    let download: TransferItem
    
    var body: some View {
        Form {
            Section("File information") {
                LabeledContent("Name", value: download.fileName)
                LabeledContent("Size", value: download.sizeText)
                LabeledContent("Completed", value: download.completedText)
                LabeledContent("Progress", value: String(format: "%.1f%%", download.progress * 100))
            }
            
            Section("Hash") {
                LabeledContent("ED2K", value: download.ed2kHash)
            }
            
            Section("Sources") {
                LabeledContent("Active", value: "\(download.sources)")
                LabeledContent("Availability", value: "\(download.availability)")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Rectangle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
        }
    }
}

#Preview {
    DownloadsTabView()
        .environmentObject(MacMuleStore())
}
