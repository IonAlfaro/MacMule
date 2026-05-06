import SwiftUI

struct SearchTabView: View {
    @EnvironmentObject private var store: MacMuleStore
    
    private var canSearch: Bool {
        store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search params bar
            VStack(spacing: 8) {
                // Search text field
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search the eD2k network...", text: $store.searchQuery)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            guard canSearch else { return }
                            store.runSearch()
                        }
                    
                    if store.isSearching {
                        ProgressView()
                            .controlSize(.small)
                    }
                    
                    Button("Search") {
                        store.runSearch()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.isSearching || !canSearch)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                
                // Advanced filters
                HStack(spacing: 16) {
                    Picker("Method", selection: $store.searchMethod) {
                        ForEach(SearchMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    
                    Picker("Type", selection: $store.searchFileKind) {
                        Text("All").tag(nil as FileKind?)
                        ForEach(FileKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind as FileKind?)
                        }
                    }
                    .frame(width: 150)
                    
                    HStack {
                        Text("Size:")
                            .font(.caption)
                        TextField("Min", text: $store.searchMinSizeKB)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("-")
                        TextField("Max", text: $store.searchMaxSizeKB)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("MB")
                            .font(.caption)
                    }
                    
                    TextField("Extension", text: $store.searchExtensionFilter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    
                    Spacer()
                }
                .font(.caption)
            }
            .padding(12)
            .background(.quaternary.opacity(0.3))
            
            Divider()
            
            // Results
            if store.searchResults.isEmpty {
                EmptySectionView(
                    icon: "magnifyingglass",
                        title: "No results",
                    subtitle: store.isSearching
                        ? "Searching..."
                        : store.network.isConnected == false && store.searchMethod == .server
                            ? "Not connected to any eD2k server. Connect to a server and try again."
                            : "Run a search to see files"
                )
            } else {
                Table(store.searchResults) {
                    TableColumn("Name") { result in
                        HStack(spacing: 6) {
                            FileIcon(kind: result.kind, size: .small)
                            Text(result.fileName)
                        }
                    }
                    
                    TableColumn("Size") { result in
                        Text(result.sizeText)
                            .font(.caption.monospacedDigit())
                    }
                    .width(100)
                    
                    TableColumn("Sources") { result in
                        Text("\(result.sources)")
                            .font(.caption.monospacedDigit())
                    }
                    .width(60)
                    
                    TableColumn("Availability") { result in
                        Text("\(result.availability)")
                            .font(.caption.monospacedDigit())
                    }
                    .width(80)
                    
                    TableColumn("Network") { result in
                        Text(result.network)
                            .font(.caption)
                    }
                    .width(80)
                    
                    TableColumn("") { result in
                        Button {
                            store.addDownload(from: result)
                        } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .width(60)
                }
                .tableStyle(.bordered(alternatesRowBackgrounds: true))
            }
        }
    }
}

#Preview {
    SearchTabView()
        .environmentObject(MacMuleStore())
}
