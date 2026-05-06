import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var selectedTab: MainTab = .downloads
    @State private var showingSettings = false
    @State private var quickSearch = ""
    
    enum MainTab: String, CaseIterable {
        case servers = "Servers"
        case kad = "Kad"
        case downloads = "Downloads"
        case uploads = "Uploads"
        case shared = "Shared"
        case search = "Search"
        case statistics = "Statistics"
        case messages = "Messages"
        
        var systemImage: String {
            switch self {
            case .servers: "server.rack"
            case .kad: "circle.hexagongrid"
            case .downloads: "arrow.down.circle"
            case .uploads: "arrow.up.circle"
            case .shared: "folder"
            case .search: "magnifyingglass"
            case .statistics: "chart.xyaxis.line"
            case .messages: "message"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content with TabView
            TabView(selection: $selectedTab) {
                ForEach(MainTab.allCases, id: \.self) { tab in
                    tabContent(for: tab)
                        .tabItem {
                            Label(tab.rawValue, systemImage: tab.systemImage)
                        }
                        .tag(tab)
                }
            }
            .tabViewStyle(.automatic)
            
            // Status bar at bottom
            StatusBarView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Speed selector
                Menu {
                    Button("Unlimited") { }
                    Button("Reduced") { }
                    Button("Manual") { }
                } label: {
                    Label("Speed", systemImage: "gauge.medium")
                }
                
                // Quick search
                TextField("Search...", text: $quickSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .onSubmit {
                        if !quickSearch.isEmpty {
                            store.searchQuery = quickSearch
                            store.runSearch()
                        }
                    }
                
                // Settings button
                Button {
                    showingSettings = true
                } label: {
                    Label("Preferences", systemImage: "gearshape")
                }
            }
            
            ToolbarItemGroup(placement: .automatic) {
                // Connect/Disconnect
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
                .tint(store.network.isConnected ? .red : .green)
                
                // Kad toggle
                Button {
                    if store.kad.isRunning {
                        store.kadStop()
                    } else {
                        store.kadStart()
                    }
                } label: {
                    Label("Kad", systemImage: "circle.hexagongrid")
                }
                .tint(store.kad.isRunning ? .green : .secondary)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheetView()
                .environmentObject(store)
        }
        .task { await store.start() }
    }
    
    @ViewBuilder
    private func tabContent(for tab: MainTab) -> some View {
        switch tab {
        case .servers:
            ServersTabView()
        case .kad:
            KadTabView()
        case .downloads:
            DownloadsTabView()
        case .uploads:
            UploadsTabView()
        case .shared:
            SharedTabView()
        case .search:
            SearchTabView()
        case .statistics:
            StatisticsTabView()
        case .messages:
            MessagesTabView()
        }
    }
}

#Preview {
    MainWindowView()
        .environmentObject(MacMuleStore())
        .frame(minWidth: 1200, minHeight: 700)
}
