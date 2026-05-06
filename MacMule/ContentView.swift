import AppKit
import Combine
import SwiftUI

// MARK: - Navigation State

@MainActor
private final class SectionSelection: ObservableObject {
    @Published var section: MacMuleSection? = .dashboard
}

// MARK: - Root View

struct ContentView: View {
    @EnvironmentObject private var store: MacMuleStore
    @StateObject private var nav = SectionSelection()
    @State private var toolbarSearch = ""

    var body: some View {
        NavigationSplitView {
            SidebarNavList(nav: nav)
                .safeAreaInset(edge: .top, spacing: 0) { SidebarBrandHeader() }
                .safeAreaInset(edge: .bottom, spacing: 0) { SidebarStatusFooter() }
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
        } detail: {
            DetailContainerView(nav: nav)
        }
        .frame(minWidth: 1020, minHeight: 660)
        .macMulePageBackground()
        .task { await store.start() }
        .onChange(of: store.selectedSection) { _, s in
            if nav.section != s { nav.section = s }
        }
        .onChange(of: nav.section) { _, s in
            if store.selectedSection != s { store.selectedSection = s }
        }
        .toolbar(id: "main") {
            ToolbarItem(id: "quickSearch", placement: .principal) {
                ToolbarSearchField(text: $toolbarSearch)
                    .frame(width: 280)
            }
            ToolbarItem(id: "connectToggle", placement: .primaryAction) {
                Button {
                    store.toggleConnection()
                } label: {
                    Label(
                        store.network.isConnected ? "Disconnect" : "Connect",
                        systemImage: store.network.isConnected
                            ? "bolt.horizontal.circle.fill"
                            : "bolt.horizontal.circle"
                    )
                }
                .help(store.network.isConnected ? "Disconnect from eD2k" : "Connect to eD2k")
                .tint(store.network.isConnected ? .red : .accentColor)
            }
        }
    }
}

// MARK: - Sidebar

private struct SidebarBrandHeader: View {
    @EnvironmentObject private var store: MacMuleStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("MacMule")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    HStack(spacing: 4) {
                        Circle()
                            .fill(store.network.isConnected ? .green : .secondary.opacity(0.4))
                            .frame(width: 5, height: 5)
                        Text(store.network.isConnected ? "Network online" : "Offline")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack(spacing: 6) {
                SidebarTrafficChip(value: ByteCountFormatter.macMuleString(store.totalDownloadSpeed) + "/s", systemImage: "arrow.down", color: .blue)
                SidebarTrafficChip(value: ByteCountFormatter.macMuleString(store.totalUploadSpeed) + "/s", systemImage: "arrow.up", color: .green)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.5)
        }
        .background(.regularMaterial)
    }
}

private struct SidebarTrafficChip: View {
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(value, systemImage: systemImage)
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(color.opacity(0.12), lineWidth: 1)
            }
    }
}

private struct SidebarNavList: View {
    @EnvironmentObject private var store: MacMuleStore
    @ObservedObject var nav: SectionSelection

    var body: some View {
        List(selection: $nav.section) {
            Section {
                sidebarButton(for: .dashboard)
                sidebarButton(for: .search)
            } header: {
                sidebarSectionHeader("Overview")
            }

            Section {
                ForEach([MacMuleSection.downloads, .uploads, .shared], id: \.self) { s in
                    sidebarButton(for: s)
                }
            } header: {
                sidebarSectionHeader("Transfers")
            }

            Section {
                sidebarButton(for: .kad)
            } header: {
                sidebarSectionHeader("DHT")
            }

            Section {
                ForEach([MacMuleSection.network, .statistics, .settings], id: \.self) { s in
                    sidebarButton(for: s)
                }
            } header: {
                sidebarSectionHeader("Network")
            }

            Section {
                sidebarButton(for: .logs)
            } header: {
                sidebarSectionHeader("Diagnostics")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MacMule")
    }

    @ViewBuilder
    private func sidebarSectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
    }

    @ViewBuilder
    private func sidebarButton(for section: MacMuleSection) -> some View {
        let isSelected = nav.section == section
        Label {
            HStack {
                Text(section.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                Spacer()
                sidebarBadge(for: section)
            }
        } icon: {
            Image(systemName: section.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 22, height: 22)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 5)
                )
        }
        .tag(section)
        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
    }

    @ViewBuilder
    private func sidebarBadge(for section: MacMuleSection) -> some View {
        switch section {
        case .downloads:
            let count = store.activeDownloadCount
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
            }
        case .uploads:
            if store.uploads.isEmpty == false {
                Text("\(store.uploads.count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
            }
        case .shared:
            if store.sharedFiles.isEmpty == false {
                Text("\(store.sharedFiles.count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
            }
        default:
            EmptyView()
        }
    }
}

// MARK: - Sidebar Status Footer

private struct SidebarStatusFooter: View {
    @EnvironmentObject private var store: MacMuleStore

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 6, height: 6)
                    Text(store.network.isConnected ? "Connected" : "Disconnected")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text(store.network.statusText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if store.totalDownloadSpeed > 0 || store.totalUploadSpeed > 0 {
                    HStack(spacing: 10) {
                        if store.totalDownloadSpeed > 0 {
                            Label(ByteCountFormatter.macMuleString(store.totalDownloadSpeed) + "/s",
                                  systemImage: "arrow.down")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.blue)
                        }
                        if store.totalUploadSpeed > 0 {
                            Label(ByteCountFormatter.macMuleString(store.totalUploadSpeed) + "/s",
                                  systemImage: "arrow.up")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.green)
                        }
                    }
                } else {
                    Text("No traffic")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
    }

    private var connectionColor: Color {
        guard store.network.isConnected else { return .secondary.opacity(0.35) }
        let status = store.network.statusText.lowercased()
        if status.contains("lowid") || status.contains("low id") { return .orange }
        return .green
    }
}

// MARK: - Detail Container

private struct DetailContainerView: View {
    @EnvironmentObject private var store: MacMuleStore
    @ObservedObject var nav: SectionSelection

    var body: some View {
        Group {
            switch nav.section ?? .dashboard {
            case .dashboard:   DashboardView()
            case .search:      SearchView()
            case .downloads:   DownloadsView()
            case .uploads:     UploadsView()
            case .shared:      SharedFilesView()
            case .kad:         KadTabView()
            case .network:     NetworkView()
            case .statistics:  StatisticsView()
            case .settings:    SettingsView()
            case .logs:        LogView()
            }
        }
        .transition(.opacity)
        .macMulePageBackground()
    }
}

// MARK: - Toolbar Status Views

private struct ToolbarSearchField: View {
    @EnvironmentObject private var store: MacMuleStore
    @Binding var text: String

    private var canSearch: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search eD2k/Kad", text: $text)
                .textFieldStyle(.plain)
                .onSubmit { run() }
            if store.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.75)
            }
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(canSearch ? Color.accentColor.opacity(0.25) : MacMuleTheme.border, lineWidth: 1)
        }
    }

    private func run() {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return }
        store.searchQuery = query
        store.selectedSection = .search
        store.runSearch()
    }
}

private struct CoreRuntimeStatusView: View {
    @EnvironmentObject private var store: MacMuleStore

    var body: some View {
        Label(store.coreRuntimeStatus.title, systemImage: store.coreRuntimeStatus.systemImage)
            .font(.caption)
            .foregroundStyle(store.coreRuntimeStatus.isWarning ? .orange : .secondary)
            .labelStyle(.titleAndIcon)
            .help(store.coreRuntimeStatus.detail)
    }
}

private struct ConnectionStatusView: View {
    @EnvironmentObject private var store: MacMuleStore

    private var isLowIDConnection: Bool {
        guard store.network.isConnected else { return false }
        let status = store.network.statusText.lowercased()
        return status.contains("lowid") || status.contains("low id")
    }

    private var indicatorColor: Color {
        guard store.network.isConnected else { return Color.secondary.opacity(0.35) }
        return isLowIDConnection ? .orange : .green
    }

    private var helpText: String {
        if isLowIDConnection {
            return "Low ID: conectado, pero con conectividad limitada. Revisa firewall/NAT y abre TCP:\(store.network.tcpPort) y UDP:\(store.network.udpPort)."
        }
        if store.network.highID {
            return "High ID - bien conectado"
        }
        return store.network.statusText
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 6, height: 6)
            Text(store.network.statusText)
                .font(.caption)
                .foregroundStyle(store.network.isConnected ? .primary : .secondary)
        }
        .help(helpText)
    }
}
