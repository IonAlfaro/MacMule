import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Search

struct SearchView: View {
    @EnvironmentObject private var store: MacMuleStore

    private var canSearch: Bool {
        store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var filteredResults: [SearchResult] {
        var results = store.searchResults

        if let kind = store.searchFileKind {
            results = results.filter { $0.kind == kind }
        }

        let extensionFilter = store.searchExtensionFilter
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        if extensionFilter.isEmpty == false {
            results = results.filter {
                ($0.fileName as NSString).pathExtension.lowercased() == extensionFilter
            }
        }

        if let minMB = Double(store.searchMinSizeKB.trimmingCharacters(in: .whitespacesAndNewlines)), minMB > 0 {
            results = results.filter { Double($0.sizeInBytes) >= minMB * 1_048_576 }
        }

        if let maxMB = Double(store.searchMaxSizeKB.trimmingCharacters(in: .whitespacesAndNewlines)), maxMB > 0 {
            results = results.filter { Double($0.sizeInBytes) <= maxMB * 1_048_576 }
        }

        return results
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "Search", subtitle: subtitleText, systemImage: "magnifyingglass")

            SearchOverviewBand()
                .padding(.horizontal, MacMuleTheme.spacingXL)
                .padding(.bottom, MacMuleTheme.spacingMD)

            searchField
                .padding(.horizontal, MacMuleTheme.spacingXL)
                .padding(.bottom, MacMuleTheme.spacingSM)

            searchFilters
                .padding(.horizontal, MacMuleTheme.spacingXL)
                .padding(.bottom, MacMuleTheme.spacingSM)

            networkHint
                .padding(.horizontal, MacMuleTheme.spacingXL)
                .padding(.bottom, MacMuleTheme.spacingSM)

            if store.searchResults.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        FilterPill(
                            label: "Todo",
                            count: store.searchResults.count,
                            isSelected: store.searchFileKind == nil
                        ) { store.searchFileKind = nil }
                        ForEach(FileKind.allCases, id: \.self) { kind in
                            let count = store.searchResults.filter { $0.kind == kind }.count
                            FilterPill(
                                label: kind.title,
                                systemImage: kind.systemImage,
                                count: count,
                                isSelected: store.searchFileKind == kind
                            ) { store.searchFileKind = store.searchFileKind == kind ? nil : kind }
                            .disabled(count == 0)
                        }
                    }
                    .padding(.horizontal, MacMuleTheme.spacingXL)
                }
                .padding(.bottom, 6)
            }

            Divider()

            if store.searchResults.isEmpty {
                if store.isSearching {
                    EmptySectionView(
                        icon: "magnifyingglass",
                        title: "Buscando…",
                        subtitle: "Consultando servidores eD2k. Esto puede tardar unos segundos."
                    )
                } else {
                    EmptySectionView(
                        icon: "magnifyingglass",
                        title: "Search files",
                        subtitle: "Type a query and press ↵ to search the eD2k network."
                    )
                }
            } else if filteredResults.isEmpty {
                EmptySectionView(
                    icon: store.searchFileKind?.systemImage ?? "line.3.horizontal.decrease.circle",
                    title: "No results",
                    subtitle: "No results match the current filters.",
                    action: { clearSearchFilters() },
                    actionLabel: "Show all"
                )
            } else {
                List(filteredResults) { result in
                    SearchResultRow(result: result) {
                        store.addDownload(from: result)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .macMulePageBackground()
        .animation(.easeInOut(duration: 0.18), value: filteredResults.count)
    }

    private var searchField: some View {
        HStack(spacing: MacMuleTheme.spacingSM) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.accentColor)
                .font(.callout.weight(.semibold))
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))

            TextField("Search the eD2k network…", text: $store.searchQuery)
                .textFieldStyle(.plain)
                .font(.body)
                .onSubmit {
                    guard canSearch else { return }
                    store.runSearch()
                }

            if store.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.85)
                    .transition(.opacity.combined(with: .scale(0.8)))
            }

            if store.searchQuery.isEmpty == false {
                Button {
                    store.searchQuery = ""
                    store.runSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(0.8)))
            }

            Button("Search") {
                store.runSearch()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(store.isSearching || canSearch == false)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, MacMuleTheme.spacingMD)
        .padding(.vertical, 10)
        .macMuleElevated()
        .overlay {
            RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
                .strokeBorder(Color.accentColor.opacity(canSearch ? 0.3 : 0), lineWidth: 1)
        }
    }

    private var searchFilters: some View {
        ViewThatFits(in: .horizontal) {
            searchFilterRow
            VStack(alignment: .leading, spacing: MacMuleTheme.spacingSM) {
                searchFilterRow
            }
        }
    }

    private var searchFilterRow: some View {
        HStack(spacing: MacMuleTheme.spacingSM) {
            Picker("Type", selection: $store.searchFileKind) {
                Text("All").tag(nil as FileKind?)
                ForEach(FileKind.allCases, id: \.self) { kind in
                    Label(kind.title, systemImage: kind.systemImage).tag(kind as FileKind?)
                }
            }
            .frame(width: 150)

            HStack(spacing: 6) {
                TextField("Min MB", text: $store.searchMinSizeKB)
                    .textFieldStyle(.plain)
                    .frame(width: 58)
                Divider().frame(height: 16)
                TextField("Max MB", text: $store.searchMaxSizeKB)
                    .textFieldStyle(.plain)
                    .frame(width: 58)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .macMuleSurface(cornerRadius: 6)

            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Extension", text: $store.searchExtensionFilter)
                    .textFieldStyle(.plain)
                    .frame(width: 90)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .macMuleSurface(cornerRadius: 6)

            Spacer(minLength: 0)

            Button { clearSearchFilters() } label: {
                Label("Clear filters", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(filtersAreEmpty)
        }
        .font(.caption)
    }

    private var filtersAreEmpty: Bool {
        store.searchFileKind == nil &&
            store.searchMinSizeKB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            store.searchMaxSizeKB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            store.searchExtensionFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func clearSearchFilters() {
        store.searchFileKind = nil
        store.searchMinSizeKB = ""
        store.searchMaxSizeKB = ""
        store.searchExtensionFilter = ""
    }

    private var networkHint: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(store.network.isConnected ? .green : .secondary.opacity(0.35))
                .frame(width: 5, height: 5)
            Text(store.network.isConnected ? store.network.statusText : "Offline — will connect when searching")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("↵ to search")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
    }

    private var subtitleText: String {
        if store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }
        let total = store.searchResults.count
        return total > 0 ? "\(total) result\(total == 1 ? "" : "s")" : ""
    }
}

private struct SearchOverviewBand: View {
    @EnvironmentObject private var store: MacMuleStore

    var body: some View {
        HStack(spacing: MacMuleTheme.spacingLG) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Browse network")
                    .font(.headline)
                Text(store.network.isConnected ? "Connected: \(store.network.statusText)" : "Will connect automatically when searching")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Picker("Method", selection: $store.searchMethod) {
                ForEach(SearchMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            Button {
                store.toggleConnection()
            } label: {
                Label(store.network.isConnected ? "Disconnect" : "Connect",
                      systemImage: store.network.isConnected ? "bolt.slash" : "bolt")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(store.network.isConnected ? .red : .accentColor)
        }
        .padding(MacMuleTheme.spacingMD)
        .macMuleElevated()
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject private var store: MacMuleStore

    private var activeDownloads: [TransferItem] {
        store.downloads
            .filter { $0.status == .downloading || $0.status == .queued || $0.status == .verifying }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MacMuleTheme.spacingLG) {
                HeaderBar(title: "Home", subtitle: "Search, network and transfer control center", systemImage: "square.grid.2x2")
                    .padding(.horizontal, -MacMuleTheme.spacingXL)
                    .padding(.top, -MacMuleTheme.spacingLG)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: MacMuleTheme.spacingLG) {
                        DashboardCommandPanel()
                            .frame(minWidth: 420)
                        DashboardNetworkPanel()
                            .frame(width: 300)
                    }

                    VStack(alignment: .leading, spacing: MacMuleTheme.spacingLG) {
                        DashboardCommandPanel()
                        DashboardNetworkPanel()
                    }
                }

                MetricsStrip(metrics: [
                    StatMetric(title: "Download", value: ByteCountFormatter.macMuleString(store.totalDownloadSpeed) + "/s", systemImage: "arrow.down"),
                    StatMetric(title: "Upload", value: ByteCountFormatter.macMuleString(store.totalUploadSpeed) + "/s", systemImage: "arrow.up"),
                    StatMetric(title: "Sources", value: "\(store.totalSources)", systemImage: "person.2"),
                    StatMetric(title: "Session", value: store.sessionDurationText, systemImage: "clock")
                ])

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: MacMuleTheme.spacingLG) {
                        DashboardTransfersPanel(downloads: activeDownloads)
                        DashboardActivityPanel()
                    }

                    VStack(alignment: .leading, spacing: MacMuleTheme.spacingLG) {
                        DashboardTransfersPanel(downloads: activeDownloads)
                        DashboardActivityPanel()
                            .frame(maxWidth: .infinity)
                    }
                }

                ThroughputChart(
                    downloadHistory: store.downloadSpeedHistory,
                    uploadHistory: store.uploadSpeedHistory,
                    downloadSpeed: store.totalDownloadSpeed,
                    uploadSpeed: store.totalUploadSpeed
                )
            }
            .padding(MacMuleTheme.spacingXL)
        }
        .macMulePageBackground()
    }
}

private struct DashboardCommandPanel: View {
    @EnvironmentObject private var store: MacMuleStore

    private var canSearch: Bool {
        store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacMuleTheme.spacingLG) {
            HStack(alignment: .top, spacing: MacMuleTheme.spacingMD) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.network.isConnected ? "Network ready to transfer" : "Prepare your next download")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text(store.network.statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            VStack(spacing: MacMuleTheme.spacingSM) {
                HStack(spacing: MacMuleTheme.spacingSM) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.blue)
                        .frame(width: 24, height: 24)
                        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    TextField("Search files on eD2k or Kad…", text: $store.searchQuery)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            guard canSearch else { return }
                            store.selectedSection = .search
                            store.runSearch()
                        }
                    Button {
                        store.selectedSection = .search
                        if canSearch { store.runSearch() }
                    } label: {
                        Image(systemName: "arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(canSearch == false || store.isSearching)
                    .help("Search")
                }
                .padding(10)
                .macMuleSurface()

                HStack(spacing: MacMuleTheme.spacingSM) {
                    Image(systemName: "link")
                        .foregroundStyle(.teal)
                        .frame(width: 24, height: 24)
                        .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                    TextField("Paste ed2k:// link…", text: $store.ed2kLinkText)
                        .textFieldStyle(.plain)
                        .onSubmit { store.addED2KLink() }
                    Button { store.pasteED2KLink() } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .help("Paste")
                    Button { store.addED2KLink() } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.ed2kLinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isAddingED2KLink)
                    .help("Add download")
                }
                .padding(10)
                .macMuleSurface()
            }

            HStack(spacing: MacMuleTheme.spacingSM) {
                DashboardQuickAction(
                    title: store.network.isConnected ? "Disconnect" : "Connect",
                    systemImage: store.network.isConnected ? "bolt.slash" : "bolt",
                    color: store.network.isConnected ? .red : .green
                ) {
                    store.toggleConnection()
                }
                DashboardQuickAction(title: "Servers", systemImage: "server.rack", color: .indigo) {
                    store.selectedSection = .network
                }
                DashboardQuickAction(title: "Kad", systemImage: "circle.hexagongrid", color: .teal) {
                    store.selectedSection = .kad
                }
            }

            if let error = store.ed2kLinkError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(MacMuleTheme.spacingLG)
        .macMuleElevated()
        .overlay {
            RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
                .strokeBorder(Color.accentColor.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct DashboardQuickAction: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(color)
    }
}

private struct DashboardNetworkPanel: View {
    @EnvironmentObject private var store: MacMuleStore

    private var statusColor: Color {
        guard store.network.isConnected else { return .secondary }
        return store.network.highID ? .green : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacMuleTheme.spacingMD) {
            HStack {
                Text("Network")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(store.network.isConnected ? (store.network.highID ? "High ID" : "Low ID") : "Disconnected")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusColor)
                Text(store.network.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            VStack(spacing: 6) {
                DashboardInfoRow(title: "TCP", value: ":\(store.network.tcpPort)", color: .blue)
                DashboardInfoRow(title: "UDP", value: ":\(store.network.udpPort)", color: .teal)
                DashboardInfoRow(title: "Servers", value: "\(store.servers.count)", color: .indigo)
                DashboardInfoRow(title: "Kad", value: "\(store.kad.nodeCount) nodes", color: .green)
            }

            Spacer(minLength: 0)

            VStack(spacing: MacMuleTheme.spacingSM) {
                Button { store.connectToBestServer() } label: {
                    Label("Best server", systemImage: "bolt.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { store.selectedSection = .network } label: {
                    Label("View servers", systemImage: "server.rack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(MacMuleTheme.spacingLG)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .macMuleElevated()
        .overlay {
            RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
                .strokeBorder(statusColor.opacity(0.2), lineWidth: 1)
        }
    }
}

private struct DashboardTransfersPanel: View {
    @EnvironmentObject private var store: MacMuleStore
    let downloads: [TransferItem]

    var body: some View {
        VStack(alignment: .leading, spacing: MacMuleTheme.spacingMD) {
            HStack {
                Text("Active transfers")
                    .font(.headline)
                Spacer()
                Button { store.selectedSection = .downloads } label: {
                    Image(systemName: "arrow.forward")
                }
                .buttonStyle(.borderless)
                .help("Open downloads")
            }
            if downloads.isEmpty {
                DashboardEmptyMini(icon: "arrow.down.circle", title: "No activity", subtitle: "Add a link or search files to get started.")
            } else {
                VStack(spacing: 6) {
                    ForEach(downloads) { item in
                        DashboardTransferRow(item: item)
                    }
                }
            }
        }
        .padding(MacMuleTheme.spacingLG)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .macMuleElevated()
    }
}

private struct DashboardActivityPanel: View {
    @EnvironmentObject private var store: MacMuleStore

    private var recentLogs: [MacMuleCoreLogEntry] {
        Array(store.coreRuntimeLogs.suffix(5).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacMuleTheme.spacingMD) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                Button { store.selectedSection = .logs } label: {
                    Image(systemName: "text.alignleft")
                }
                .buttonStyle(.borderless)
                .help("Open logs")
            }
            if recentLogs.isEmpty {
                DashboardEmptyMini(icon: "text.alignleft", title: "No events", subtitle: "The core has not emitted activity yet.")
            } else {
                VStack(spacing: 5) {
                    ForEach(recentLogs) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 64, alignment: .leading)
                            Text(entry.level.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(entry.level.tint)
                                .frame(width: 40, alignment: .leading)
                            Text(entry.message)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
        .padding(MacMuleTheme.spacingLG)
        .frame(minWidth: 280, idealWidth: 340, maxWidth: .infinity, alignment: .topLeading)
        .macMuleElevated()
    }
}

private struct DashboardTransferRow: View {
    let item: TransferItem

    var body: some View {
        HStack(spacing: MacMuleTheme.spacingSM) {
            FileIcon(kind: item.kind, size: .small)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.fileName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(item.progress * 100))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: item.progress)
                    .controlSize(.small)
                    .tint(item.status.tint)
            }
        }
        .padding(8)
        .macMuleSurface(cornerRadius: 6)
    }
}

private struct DashboardInfoRow: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
        }
    }
}

private struct DashboardEmptyMini: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

// MARK: - Downloads

struct DownloadsView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var statusFilter: TransferStatus? = nil
    @State private var isDropTargeted = false

    private var filtered: [TransferItem] {
        let base = statusFilter == nil
            ? store.downloads
            : store.downloads.filter { $0.status == statusFilter }
        return base.sorted(by: store.downloadSortOrder.comparator)
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(
                title: "Downloads",
                subtitle: "\(store.downloads.count) transfer\(store.downloads.count == 1 ? "" : "s")",
                systemImage: "arrow.down.circle"
            )

            ed2kLinkBar
                .padding(.horizontal, MacMuleTheme.spacingXL)
                .padding(.bottom, MacMuleTheme.spacingMD)

            MetricsStrip(metrics: [
                StatMetric(title: "Download", value: ByteCountFormatter.macMuleString(store.totalDownloadSpeed) + "/s", systemImage: "arrow.down"),
                StatMetric(title: "Sources", value: "\(store.totalSources)", systemImage: "person.2"),
                StatMetric(title: "Active", value: "\(store.activeDownloadCount)", systemImage: "bolt"),
                StatMetric(title: "Completed", value: "\(store.completedDownloadCount)", systemImage: "checkmark")
            ])
            .padding(.horizontal, MacMuleTheme.spacingXL)
            .padding(.bottom, MacMuleTheme.spacingSM)

            if store.downloads.isEmpty == false {
                DownloadsActionBar(statusFilter: $statusFilter)
                    .padding(.horizontal, MacMuleTheme.spacingXL)
                    .padding(.bottom, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        FilterPill(label: "All", count: store.downloads.count, isSelected: statusFilter == nil) {
                            statusFilter = nil
                        }
                        ForEach(TransferStatus.allCases, id: \.self) { status in
                            let count = store.downloads.filter { $0.status == status }.count
                            FilterPill(
                                label: status.title,
                                systemImage: status.systemImage,
                                count: count,
                                isSelected: statusFilter == status
                            ) { statusFilter = statusFilter == status ? nil : status }
                            .disabled(count == 0)
                        }
                    }
                    .padding(.horizontal, MacMuleTheme.spacingXL)
                }
                .padding(.bottom, 6)
            }

            Divider()

            if store.downloads.isEmpty {
                EmptySectionView(
                    icon: "arrow.down.circle",
                    title: "No downloads",
                    subtitle: "Paste an ed2k:// link above, drag one here, or search for it from the Search section."
                )
            } else if filtered.isEmpty {
                EmptySectionView(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "No downloads with that status",
                    subtitle: "Change the filter or try another status.",
                    action: { statusFilter = nil },
                    actionLabel: "Show all"
                )
            } else {
                HSplitView {
                    List(selection: $store.selectedDownloadID) {
                        ForEach(filtered) { item in
                            DownloadRow(
                                item: item,
                                onTogglePause: { store.togglePause(downloadID: item.id) },
                                onDelete: { store.removeDownload(downloadID: item.id) }
                            )
                            .tag(item.id as TransferItem.ID?)
                            .contextMenu { downloadContextMenu(for: item) }
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(minWidth: 420)

                    DownloadDetailView(item: store.selectedDownload)
                        .frame(minWidth: 300)
                }
            }
        }
        .macMulePageBackground()
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: MacMuleTheme.radiusXL)
                    .strokeBorder(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(MacMuleTheme.spacingMD)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.url, .text], isTargeted: $isDropTargeted) { handleDrop($0) }
    }

    private var ed2kLinkBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: MacMuleTheme.spacingSM) {
                Image(systemName: "link")
                    .foregroundStyle(Color.accentColor)
                    .font(.callout.weight(.semibold))
                    .frame(width: 26, height: 26)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))

                TextField("Paste an ed2k:// link…", text: $store.ed2kLinkText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit { store.addED2KLink() }

                if store.isAddingED2KLink {
                    ProgressView().controlSize(.small).scaleEffect(0.85)
                }

                Button { store.addED2KLink() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .disabled(store.isAddingED2KLink || store.ed2kLinkText.isEmpty)
                .help("Add eD2k link")

                Divider()
                    .frame(height: 18)

                Button { store.pasteED2KLink() } label: {
                    Image(systemName: "doc.on.clipboard")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Paste link")

                Button { store.selectedSection = .search } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Search file")
            }
            .padding(.horizontal, MacMuleTheme.spacingMD)
            .padding(.vertical, 10)
            .macMuleElevated()
            .overlay(
                RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor : MacMuleTheme.border,
                        lineWidth: isDropTargeted ? 2 : 1
                    )
            )
            .onDrop(of: [.url, .text], isTargeted: $isDropTargeted) { handleDrop($0) }

            if let error = store.ed2kLinkError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func downloadContextMenu(for item: TransferItem) -> some View {
        if item.status != .completed && item.status != .failed {
            Button { store.togglePause(downloadID: item.id) } label: {
                Label(item.status == .paused ? "Resume" : "Pause",
                      systemImage: item.status == .paused ? "play.fill" : "pause.fill")
            }
        }
        Divider()
        Button(role: .destructive) { store.removeDownload(downloadID: item.id) } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier("public.url") {
            provider.loadItem(forTypeIdentifier: "public.url") { item, _ in
                let raw: String?
                if let url = item as? URL { raw = url.absoluteString }
                else if let data = item as? Data { raw = String(data: data, encoding: .utf8) }
                else { raw = nil }
                if let link = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                   link.lowercased().hasPrefix("ed2k://") {
                    Task { @MainActor in
                        self.store.ed2kLinkText = link
                        self.store.addED2KLink()
                    }
                }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
            provider.loadItem(forTypeIdentifier: "public.plain-text") { item, _ in
                if let text = item as? String,
                   text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("ed2k://") {
                    Task { @MainActor in
                        self.store.ed2kLinkText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.store.addED2KLink()
                    }
                }
            }
            return true
        }
        return false
    }
}

private struct DownloadsActionBar: View {
    @EnvironmentObject private var store: MacMuleStore
    @Binding var statusFilter: TransferStatus?

    private var hasPausable: Bool {
        store.downloads.contains { $0.status != .paused && $0.status != .completed && $0.status != .failed }
    }
    private var hasPaused: Bool {
        store.downloads.contains { $0.status == .paused }
    }
    private var hasCompleted: Bool {
        store.downloads.contains { $0.status == .completed }
    }
    private var hasFailed: Bool {
        store.downloads.contains { $0.status == .failed }
    }

    var body: some View {
        HStack(spacing: 6) {
            Button { store.resumeAllDownloads() } label: {
                Label("Resume", systemImage: "play.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(hasPaused == false)

            Button { store.pauseAllDownloads() } label: {
                Label("Pause", systemImage: "pause.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(hasPausable == false)

            Button(role: .destructive) { store.removeCompletedDownloads() } label: {
                Label("Remove completed", systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(hasCompleted == false)

            Button(role: .destructive) { store.removeFailedDownloads() } label: {
                Label("Clear errors", systemImage: "exclamationmark.triangle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(hasFailed == false)

            Spacer()

            Menu {
                ForEach(DownloadSortOrder.allCases) { order in
                    Button { store.downloadSortOrder = order } label: {
                        Label(order.title, systemImage: order.systemImage)
                    }
                }
            } label: {
                Label("Sort: \(store.downloadSortOrder.title)", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Button("All") { statusFilter = nil }
                Divider()
                ForEach(TransferStatus.allCases, id: \.self) { status in
                    Button(status.title) { statusFilter = status }
                }
            } label: {
                Label(statusFilter?.title ?? "All", systemImage: "line.3.horizontal.decrease.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(8)
        .macMuleSurface()
    }
}

// MARK: - Uploads

struct UploadsView: View {
    @EnvironmentObject private var store: MacMuleStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "Uploads", subtitle: subtitleText, systemImage: "arrow.up.circle")

            if store.uploads.isEmpty {
                EmptySectionView(
                    icon: "arrow.up.circle",
                    title: "No active uploads",
                    subtitle: "Shared files will appear here when other clients request them."
                )
            } else {
                MetricsStrip(metrics: [
                    StatMetric(title: "Upload", value: ByteCountFormatter.macMuleString(store.totalUploadSpeed) + "/s", systemImage: "arrow.up"),
                    StatMetric(title: "Uploading", value: "\(store.uploads.count)", systemImage: "person.badge.plus"),
                    StatMetric(title: "Shared", value: "\(store.sharedFiles.count)", systemImage: "folder")
                ])
                .padding(.horizontal, MacMuleTheme.spacingXL)
                .padding(.bottom, MacMuleTheme.spacingMD)

                Divider()

                List(store.uploads) { item in
                    UploadRow(item: item)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .macMulePageBackground()
    }

    private var subtitleText: String {
        guard store.uploads.isEmpty == false else { return "" }
        return "\(store.uploads.count) active" + (store.uploads.count == 1 ? "" : "s") + " · " +
            ByteCountFormatter.macMuleString(store.totalUploadSpeed) + "/s"
    }
}

// MARK: - Shared Files

struct SharedFilesView: View {
    @EnvironmentObject private var store: MacMuleStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(
                title: "Shared",
                subtitle: "\(store.sharedFiles.count) file\(store.sharedFiles.count == 1 ? "" : "s")",
                systemImage: "folder"
            )

            if store.sharedFiles.isEmpty {
                EmptySectionView(
                    icon: "folder",
                    title: "No shared files",
                    subtitle: "Completed files will be shared automatically if the option is enabled in Settings."
                )
            } else {
                List(store.sharedFiles) { file in
                    SharedFileRow(file: file)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .macMulePageBackground()
    }
}

private struct SharedFileRow: View {
    let file: SharedFile

    var body: some View {
        HStack(spacing: MacMuleTheme.spacingMD) {
            FileIcon(kind: file.kind)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.fileName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(file.sizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.quaternary)
                    Text("\(file.requests) requests")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.quaternary)
                    Text(file.uploadedText + " uploaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 9)
        .padding(.horizontal, MacMuleTheme.spacingMD)
        .macMuleSurface(cornerRadius: MacMuleTheme.radiusMD)
    }
}

// MARK: - Network

struct NetworkView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var showAddServer = false
    @State private var newServerHost = ""
    @State private var newServerPort = "4661"
    @State private var serverListURL = ""

    private var shouldShowLowIDWarning: Bool {
        guard store.network.isConnected else { return false }
        let status = store.network.statusText.lowercased()
        return status.contains("lowid") || status.contains("low id")
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "Servers", subtitle: store.network.statusText, systemImage: "server.rack")

            ServersHeroPanel(showAddServer: $showAddServer)
                .padding(.horizontal, MacMuleTheme.spacingXL)
                .padding(.bottom, MacMuleTheme.spacingMD)

            MetricsStrip(metrics: [
                StatMetric(title: "TCP", value: ":\(store.network.tcpPort)", systemImage: "arrow.left.arrow.right"),
                StatMetric(title: "UDP", value: ":\(store.network.udpPort)", systemImage: "antenna.radiowaves.left.and.right"),
                StatMetric(title: "Servers", value: "\(store.servers.count)", systemImage: "server.rack"),
                StatMetric(title: "Kad", value: "\(store.network.kadNodes) nodes", systemImage: "point.3.connected.trianglepath.dotted")
            ])
            .padding(.horizontal, MacMuleTheme.spacingXL)
            .padding(.bottom, MacMuleTheme.spacingMD)

            if shouldShowLowIDWarning {
                LowIDWarningCard(tcpPort: store.network.tcpPort, udpPort: store.network.udpPort)
                    .padding(.horizontal, MacMuleTheme.spacingXL)
                    .padding(.bottom, MacMuleTheme.spacingMD)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ServersActionBar(showAddServer: $showAddServer, serverListURL: $serverListURL)
                .padding(.horizontal, MacMuleTheme.spacingXL)
                .padding(.bottom, MacMuleTheme.spacingSM)

            ServerListURLBar(url: $serverListURL)
                .padding(.horizontal, MacMuleTheme.spacingXL)
                .padding(.bottom, MacMuleTheme.spacingSM)

            CoreRuntimePanel()
                .padding(.horizontal, MacMuleTheme.spacingXL)
                .padding(.bottom, MacMuleTheme.spacingMD)

            Divider()

            if store.servers.isEmpty {
                EmptySectionView(
                    icon: "server.rack",
                    title: "No servers",
                    subtitle: "Add servers manually or import a list from a server.met URL."
                )
            } else {
                List(store.servers) { server in
                    ServerRow(server: server) {
                        store.connect(to: server)
                    } onRemove: {
                        store.remove(server: server)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .macMulePageBackground()
        .animation(.easeInOut(duration: 0.18), value: shouldShowLowIDWarning)
        .sheet(isPresented: $showAddServer) {
            AddServerSheet(host: $newServerHost, port: $newServerPort) { host, port in
                store.addServer(host: host, port: port)
                newServerHost = ""
                newServerPort = "4661"
                showAddServer = false
            } onCancel: {
                newServerHost = ""
                newServerPort = "4661"
                showAddServer = false
            }
        }
    }
}

private struct ServersHeroPanel: View {
    @EnvironmentObject private var store: MacMuleStore
    @Binding var showAddServer: Bool

    private var connectedServer: ServerSnapshot? {
        store.servers.first { $0.health == .connected }
    }

    private var statusColor: Color {
        guard store.network.isConnected else { return .secondary }
        return store.network.highID ? .green : .orange
    }

    var body: some View {
        HStack(spacing: MacMuleTheme.spacingLG) {
            VStack(alignment: .leading, spacing: MacMuleTheme.spacingMD) {
                HStack(spacing: MacMuleTheme.spacingSM) {
                    Image(systemName: "server.rack")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .frame(width: 42, height: 42)
                        .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectedServer?.name ?? "No server connected")
                            .font(.headline)
                            .lineLimit(1)
                        Text(connectedServer?.address ?? "Choose a server from the list or connect automatically")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(store.network.isConnected ? (store.network.highID ? "High ID" : "Low ID") : "Offline")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                }
                Text(store.network.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Divider()
            VStack(spacing: MacMuleTheme.spacingSM) {
                Button { store.connectToBestServer() } label: {
                    Label("Connect to best", systemImage: "bolt.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.servers.isEmpty)
                Button { showAddServer = true } label: {
                    Label("Add server", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .frame(width: 180)
        }
        .padding(MacMuleTheme.spacingLG)
        .macMuleElevated()
        .overlay {
            RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
                .strokeBorder(statusColor.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct ServersActionBar: View {
    @EnvironmentObject private var store: MacMuleStore
    @Binding var showAddServer: Bool
    @Binding var serverListURL: String

    var body: some View {
        HStack(spacing: 6) {
            Button { store.connectToBestServer() } label: {
                Label("Best connect", systemImage: "bolt")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(store.servers.isEmpty)

            Button { showAddServer = true } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                let pasted = NSPasteboard.general.string(forType: .string) ?? ""
                serverListURL = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
            } label: {
                Label("Paste server.met", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button { store.resetServers() } label: {
                Label("Restore list", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Text("\(store.servers.count) server" + (store.servers.count == 1 ? "" : "s"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .macMuleSurface()
    }
}

private struct LowIDWarningCard: View {
    let tcpPort: Int
    let udpPort: Int

    var body: some View {
        HStack(alignment: .top, spacing: MacMuleTheme.spacingMD) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text("Connected with Low ID")
                    .font(.subheadline.weight(.semibold))
                Text("The server connection exists, but peers cannot open incoming connections to your Mac. This reduces sources and speed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Open TCP port \(tcpPort) and UDP port \(udpPort) on your router/firewall.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(MacMuleTheme.spacingMD)
        .macMuleElevated()
        .overlay {
            RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
                .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
        }
    }
}

private struct ServerListURLBar: View {
    @EnvironmentObject private var store: MacMuleStore
    @Binding var url: String

    private var isValidURL: Bool {
        let t = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("http://") || t.hasPrefix("https://")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                TextField("server.met URL…", text: $url)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onSubmit { if isValidURL { store.fetchServerList(from: url) } }
                Button {
                    let pasted = NSPasteboard.general.string(forType: .string) ?? ""
                    url = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .help("Paste from clipboard")
                Button { store.fetchServerList(from: url) } label: {
                    if store.isFetchingServerList {
                        ProgressView().controlSize(.small).scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isValidURL == false || store.isFetchingServerList)
                .help("Refresh list")
            }
            .padding(.horizontal, MacMuleTheme.spacingMD)
            .padding(.vertical, 8)
            .macMuleSurface()

            if let error = store.serverListFetchError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }
        }
    }
}

private struct ServerRow: View {
    let server: ServerSnapshot
    var onConnect: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: MacMuleTheme.spacingMD) {
            Image(systemName: "server.rack")
                .font(.caption.weight(.semibold))
                .foregroundStyle(server.health.tint)
                .frame(width: 28, height: 28)
                .background(server.health.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(server.name)
                        .font(.callout.weight(.medium))
                    if server.isPreferred {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .help("Preferred server")
                    }
                }
                Text(server.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(server.health.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(server.health.tint)
                if server.users > 0 || server.pingMilliseconds > 0 {
                    Text("\(server.users.formatted()) users · \(server.pingMilliseconds) ms")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if let onConnect {
                Button { onConnect() } label: {
                    Label(
                        server.health == .connected ? "Connected" : "Connect",
                        systemImage: server.health == .connected ? "checkmark.circle.fill" : "arrow.right.circle"
                    )
                    .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(server.health == .connected)
            }

            if let onRemove {
                Button(role: .destructive) { onRemove() } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Remove server")
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, MacMuleTheme.spacingMD)
        .macMuleSurface(cornerRadius: MacMuleTheme.radiusMD)
        .contextMenu {
            if let onConnect, server.health != .connected {
                Button("Connect") { onConnect() }
            }
            if let onRemove {
                Button("Remove", role: .destructive) { onRemove() }
            }
        }
    }
}

struct AddServerSheet: View {
    @Binding var host: String
    @Binding var port: String
    let onAdd: (String, String) -> Void
    let onCancel: () -> Void
    @State private var ed2kURL = ""

    private var isValid: Bool {
        host.trimmingCharacters(in: .whitespaces).isEmpty == false &&
        UInt16(port.trimmingCharacters(in: .whitespaces)) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacMuleTheme.spacingXL) {
            Text("Add eD2k server")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 5) {
                Text("Server URL (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    TextField("ed2k://|server|host|port|/", text: $ed2kURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: ed2kURL) { _, new in
                            if let (h, p) = parseED2KServerURL(new) {
                                host = h
                                port = String(p)
                            }
                        }
                    Button {
                        let pasted = NSPasteboard.general.string(forType: .string) ?? ""
                        ed2kURL = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .help("Paste from clipboard")
                }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: MacMuleTheme.spacingMD, verticalSpacing: MacMuleTheme.spacingMD) {
                GridRow {
                    Text("Host")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    TextField("e.g. emule.example.com or 1.2.3.4", text: $host)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Port")
                        .foregroundStyle(.secondary)
                    TextField("4661", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add") { onAdd(host, port) }
                    .buttonStyle(.borderedProminent)
                    .disabled(isValid == false)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(MacMuleTheme.spacingXL)
        .frame(width: 400)
    }

    private func parseED2KServerURL(_ raw: String) -> (String, UInt16)? {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.hasPrefix("ed2k://|server|") else { return nil }
        let body = raw.dropFirst("ed2k://|server|".count)
        let parts = body.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2,
              let portNum = UInt16(parts[1]),
              parts[0].isEmpty == false else { return nil }
        return (parts[0], portNum)
    }
}

private struct CoreRuntimePanel: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var showExportError = false
    @State private var exportErrorMessage = ""

    private var visibleLogs: [MacMuleCoreLogEntry] {
        Array(store.coreRuntimeLogs.suffix(6).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacMuleTheme.spacingMD) {
            HStack(spacing: MacMuleTheme.spacingSM) {
                Image(systemName: store.coreRuntimeStatus.systemImage)
                    .font(.title3)
                    .foregroundStyle(store.coreRuntimeStatus.isWarning ? .orange : .blue)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.coreRuntimeStatus.title)
                        .font(.headline)
                    Text(store.coreRuntimeStatus.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button { exportLogs() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(store.coreRuntimeLogs.isEmpty)
                .help("Export logs")
                Button { store.restartCore() } label: {
                    if store.isRestartingCore {
                        ProgressView().controlSize(.small).scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(store.canRestartCore == false || store.isRestartingCore)
                .help("Restart core")
            }

            if visibleLogs.isEmpty == false {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(visibleLogs) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 64, alignment: .leading)
                            Text(entry.level.title)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(entry.level.tint)
                                .frame(width: 40, alignment: .leading)
                            Text(entry.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .padding(8)
                .macMuleSurface(cornerRadius: 6)
            }
        }
        .padding(MacMuleTheme.spacingMD)
        .macMuleElevated()
        .alert("Export error", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
    }

    private func exportLogs() {
        let logs = store.coreRuntimeLogs
        let lines = logs.map { entry in
            let ts = entry.timestamp.formatted(date: .numeric, time: .standard)
            return "[\(ts)] [\(entry.level.title)] \(entry.message)"
        }
        let content = lines.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.title = "Export MacMule logs"
        panel.nameFieldStringValue = "macmule-\(Date().formatted(.iso8601)).log"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportErrorMessage = error.localizedDescription
            showExportError = true
        }
    }
}

// MARK: - Statistics

struct StatisticsView: View {
    @EnvironmentObject private var store: MacMuleStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(title: "Statistics", subtitle: "Session: " + store.sessionDurationText, systemImage: "chart.xyaxis.line")

            MetricsStrip(metrics: store.statistics)
                .padding(.horizontal, MacMuleTheme.spacingXL)
                .padding(.bottom, MacMuleTheme.spacingXL)

            ThroughputChart(
                downloadHistory: store.downloadSpeedHistory,
                uploadHistory: store.uploadSpeedHistory,
                downloadSpeed: store.totalDownloadSpeed,
                uploadSpeed: store.totalUploadSpeed
            )
            .padding(.horizontal, MacMuleTheme.spacingXL)

            Spacer()
        }
        .macMulePageBackground()
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var showIncomingFolderPicker = false
    @State private var showTempFolderPicker = false

    var body: some View {
        ScrollView {
            HeaderBar(title: "Settings", subtitle: "Daemon, folder and network preferences", systemImage: "gearshape")

            Form {
                Section {
                    LabeledContent("Incoming (daemon)") {
                        HStack(spacing: 6) {
                            Text(store.coreIncomingDirectoryURL.path)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 240, alignment: .leading)
                            Button("Choose…") { showIncomingFolderPicker = true }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("Show") { NSWorkspace.shared.open(store.coreIncomingDirectoryURL) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    LabeledContent("Temp (daemon)") {
                        HStack(spacing: 6) {
                            Text(store.coreTempDirectoryURL.path)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 240, alignment: .leading)
                            Button("Choose…") { showTempFolderPicker = true }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            Button("Show") { NSWorkspace.shared.open(store.coreTempDirectoryURL) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                } header: {
                    Label("Folders", systemImage: "folder")
                }

                Section {
                    LabeledContent("Max download") {
                        HStack(spacing: MacMuleTheme.spacingMD) {
                            Slider(value: $store.maxDownloadKilobytes, in: 128...20_480, step: 128)
                                .frame(width: 200)
                            Text("\(Int(store.maxDownloadKilobytes)) KB/s")
                                .monospacedDigit()
                                .frame(width: 90, alignment: .trailing)
                                .font(.callout)
                        }
                    }
                    LabeledContent("Max upload") {
                        HStack(spacing: MacMuleTheme.spacingMD) {
                            Slider(value: $store.maxUploadKilobytes, in: 64...10_240, step: 64)
                                .frame(width: 200)
                            Text("\(Int(store.maxUploadKilobytes)) KB/s")
                                .monospacedDigit()
                                .frame(width: 90, alignment: .trailing)
                                .font(.callout)
                        }
                    }
                } header: {
                    Label("Bandwidth", systemImage: "speedometer")
                }

                Section {
                    Toggle("Connect when opening the app", isOn: $store.autoConnect)
                    Toggle("Share completed downloads", isOn: $store.shareCompletedDownloads)
                } header: {
                    Label("Network", systemImage: "network")
                }

                Section {
                    LabeledContent("TCP") {
                        Text(":\(store.network.tcpPort)").monospacedDigit()
                    }
                    LabeledContent("UDP") {
                        Text(":\(store.network.udpPort)").monospacedDigit()
                    }
                } header: {
                    Label("Ports", systemImage: "arrow.left.arrow.right")
                } footer: {
                    Text("Ports are configured in the daemon. Make sure your firewall allows them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, MacMuleTheme.spacingXL)
        }
        .macMulePageBackground()
        .fileImporter(isPresented: $showIncomingFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                store.downloadDirectory = url.path
            }
        }
        .fileImporter(isPresented: $showTempFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                store.tempDirectory = url.path
            }
        }
    }
}
