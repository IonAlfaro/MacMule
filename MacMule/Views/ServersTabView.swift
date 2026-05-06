import SwiftUI

struct ServersTabView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var showingAddServer = false
    @State private var serverMetURL = ""
    @State private var selectedServer: ServerSnapshot?
    @State private var logTab: ServerLogTab = .info
    @State private var addHost = ""
    @State private var addPort = "4661"
    
    private static let logDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
    
    enum ServerLogTab: String, CaseIterable {
        case info = "Info"
        case log = "Log"
        case verbose = "Verbose"
    }
    
    var body: some View {
        HSplitView {
            // Left: Server list
            VStack(spacing: 0) {
                Table(store.servers) {
                    TableColumn("") { server in
                        Circle()
                            .fill(server.health == .connected ? .green : .gray)
                            .frame(width: 8, height: 8)
                    }
                    .width(30)
                    
                    TableColumn("Name") { server in
                        Text(server.name)
                    }
                    
                    TableColumn("Address") { server in
                        Text(server.address)
                            .font(.caption.monospacedDigit())
                    }
                    
                    TableColumn("Ping") { server in
                        Text("\(server.pingMilliseconds)ms")
                            .font(.caption.monospacedDigit())
                    }
                    .width(60)
                    
                    TableColumn("Users") { server in
                        Text("\(server.users)")
                            .font(.caption.monospacedDigit())
                    }
                    .width(80)
                    
                    TableColumn("Files") { server in
                        Text("\(server.files)")
                            .font(.caption.monospacedDigit())
                    }
                    .width(80)
                }
                .tableStyle(.bordered(alternatesRowBackgrounds: true))
                
                Divider()
                
                // Controls
                VStack(spacing: 8) {
                    HStack {
                        Button("Add") {
                            showingAddServer = true
                        }
                        .controlSize(.small)
                        
                        Button("Refresh") {
                            store.fetchServerList(from: serverMetURL)
                        }
                        .controlSize(.small)
                        
                        Button("Reset") {
                            store.resetServers()
                        }
                        .controlSize(.small)
                        .help("Reset the server list to its default values")
                    }
                    
                    HStack {
                        Button(store.servers.contains(where: { $0.health == .connected }) ? "Disconnect" : "Connect") {
                            if let server = store.servers.first(where: { $0.health == .connected }) {
                                store.remove(server: server)
                            } else if let server = store.servers.first {
                                store.connect(to: server)
                            }
                        }
                        .controlSize(.small)
                        .tint(.accentColor)
                    }
                    
                    HStack {
                        Text("server.met URL:")
                            .font(.caption)
                        TextField("", text: $serverMetURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(minWidth: 150)
                        Button("Import") {
                            store.fetchServerList(from: serverMetURL)
                        }
                        .controlSize(.small)
                    }
                }
                .padding(8)
                .background(.quaternary.opacity(0.3))
            }
            .frame(minWidth: 400)
            
            // Right: Info + Log panel
            VStack(spacing: 0) {
                // Server info card
                if let server = selectedServer ?? store.servers.first(where: { $0.health == .connected }) {
                    Form {
                        Section("Server information") {
                            LabeledContent("Name", value: server.name)
                            LabeledContent("Address", value: server.address)
                            LabeledContent("Users", value: "\(server.users)")
                            LabeledContent("Files", value: "\(server.files)")
                            LabeledContent("Ping", value: "\(server.pingMilliseconds)ms")
                            LabeledContent("Status", value: server.health.rawValue)
                        }
                        Section("Actions") {
                            Button {
                                store.connect(to: server)
                            } label: {
                                Label("Connect", systemImage: "bolt.horizontal")
                            }
                            Button {
                                store.connect(to: server)
                            } label: {
                                Label("Test connection", systemImage: "antenna.radiowaves.left.and.right")
                            }
                            .help("Send a TCP ping to verify the server responds")
                        }
                    }
                    .formStyle(.grouped)
                    .padding()
                } else {
                    VStack {
                        Spacer()
                        Text("No server selected")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                
                Divider()
                
                // Log panel with tabs
                VStack(spacing: 0) {
                    Picker("Log", selection: $logTab) {
                        ForEach(ServerLogTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(8)
                    
                    HStack {
                        Spacer()
                        Button {
                            let text = store.coreRuntimeLogs.map {
                                "\(Self.logDateFormatter.string(from: $0.timestamp)) \($0.message)"
                            }.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        } label: {
                            Label("Copy log", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Copy the entire log to the clipboard")
                    }
                    .padding(.horizontal, 8)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(store.coreRuntimeLogs.prefix(50)) { log in
                                HStack(spacing: 6) {
                                    Text(log.timestamp, style: .time)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text(log.message)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(8)
                    }
                }
                .frame(minHeight: 150)
                .background(.quaternary.opacity(0.2))
            }
            .frame(minWidth: 350)
        }
        .sheet(isPresented: $showingAddServer) {
            AddServerSheet(
                host: $addHost,
                port: $addPort,
                onAdd: { host, port in
                    store.addServer(host: host, port: port)
                },
                onCancel: {
                    showingAddServer = false
                }
            )
        }
    }
}

#Preview {
    ServersTabView()
        .environmentObject(MacMuleStore())
}
