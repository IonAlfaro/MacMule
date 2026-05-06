import SwiftUI

struct StatisticsTabView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var statsRange: StatsRange = .session
    @State private var selectedCategory: StatsCategory = .transfer
    
    enum StatsRange: String, CaseIterable {
        case session = "Session"
        case cumulative = "Cumulative"
    }
    
    enum StatsCategory: String, CaseIterable {
        case transfer = "Transfers"
        case upload = "Upload"
        case download = "Download"
        case connections = "Connections"
        case clients = "Clients"
        case servers = "Servers"
    }
    
    var body: some View {
        HSplitView {
            // Left: Stats tree
            VStack(alignment: .leading, spacing: 0) {
                Picker("Range", selection: $statsRange) {
                    ForEach(StatsRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(12)
                
                Divider()
                
                List(selection: $selectedCategory) {
                    Section("Transfers") {
                        Label("Session", systemImage: "clock")
                        Label("Total", systemImage: "calendar")
                    }
                    
                    Section("Upload") {
                        Label("Session", systemImage: "clock")
                        Label("Total", systemImage: "calendar")
                    }
                    
                    Section("Download") {
                        Label("Session", systemImage: "clock")
                        Label("Total", systemImage: "calendar")
                    }
                    
                    Section("Connections") {
                        Label("Session", systemImage: "clock")
                        Label("Total", systemImage: "calendar")
                    }
                    
                    Section("Clients") {
                        Label("Software", systemImage: "laptopcomputer")
                        Label("Network", systemImage: "network")
                    }
                    
                    Section("Servers") {
                        Label("Connected", systemImage: "server.rack")
                        Label("Files", systemImage: "doc")
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 200)
            
            // Right: Charts
            VStack(spacing: 16) {
                // Combined stats chart
                VStack(alignment: .leading, spacing: 4) {
                    Text("Network traffic")
                        .font(.headline)
                    
                    ThroughputChart(
                        downloadHistory: store.downloadSpeedHistory,
                        uploadHistory: store.uploadSpeedHistory,
                        downloadSpeed: store.totalDownloadSpeed,
                        uploadSpeed: store.totalUploadSpeed
                    )
                    .frame(height: 200)
                }
                
                // Connection graph
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active connections")
                        .font(.headline)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary.opacity(0.3))
                        .frame(height: 100)
                        .overlay {
                            Text("Chart available when connection data exists")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                }
                
                Spacer()
                
                // Projections
                VStack(alignment: .leading, spacing: 8) {
                    Text("Projections")
                        .font(.headline)
                    
                    HStack(spacing: 24) {
                        Label {
                            Text("2h 14m remaining")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                        }
                        
                        Label {
                            Text("14h total in queue")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "list.bullet")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(MacMuleTheme.border, lineWidth: 1)
                }
            }
            .padding()
        }
        .macMulePageBackground()
    }
}

#Preview {
    StatisticsTabView()
        .environmentObject(MacMuleStore())
}
