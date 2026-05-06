import SwiftUI

struct SettingsSheetView: View {
    @EnvironmentObject private var store: MacMuleStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(0..<settingsTabs.count, id: \.self) { index in
                        TabButton(
                            title: settingsTabs[index],
                            isSelected: selectedTab == index
                        ) {
                            selectedTab = index
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .background(.quaternary.opacity(0.3))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(spacing: 24) {
                    switch selectedTab {
                    case 0: GeneralSettingsView()
                    case 1: ConnectionSettingsView()
                    case 2: SecuritySettingsView()
                    case 3: DirectoriesSettingsView()
                    case 4: FilesSettingsView()
                    case 5: NotificationsSettingsView()
                    case 6: DisplaySettingsView()
                    case 7: ServersSettingsView()
                    case 8: WebSettingsView()
                    case 9: SchedulerSettingsView()
                    case 10: TweaksSettingsView()
                    case 11: StatsSettingsView()
                    case 12: CategoriesSettingsView()
                    default: EmptyView()
                    }
                }
                .padding(24)
            }
            
            Divider()
            
            // Buttons
            HStack {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("Save") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding()
        }
        .frame(width: 800, height: 600)
    }
    
    private let settingsTabs = [
        "General",
        "Connection",
        "Security",
        "Directories",
        "Files",
        "Notifications",
        "Display",
        "Servers",
        "Web",
        "Scheduler",
        "Tweaks",
        "Statistics",
        "Categories"
    ]
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? .blue.opacity(0.2) : Color.clear)
                .foregroundStyle(isSelected ? .blue : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Pages

struct GeneralSettingsView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var language = "English" // TODO: wire to store
    @State private var autoStart = false // TODO: wire to store
    @State private var startMinimized = false // TODO: wire to store
    @State private var confirmExit = true // TODO: wire to store
    @State private var autoConnect = true // TODO: wire to store
    @State private var checkUpdates = true // TODO: wire to store
    @State private var updateDays = 7 // TODO: wire to store
    
    var body: some View {
        GroupBox("General settings") {
            Form {
                Section("Identity") {
                    TextField("Nickname", text: $store.nickname)
                    
                    Picker("Language", selection: $language) {
                        Text("Spanish").tag("Spanish")
                        Text("English").tag("English")
                        Text("Deutsch").tag("Deutsch")
                    }
                }
                
                Section("Startup") {
                    Toggle("Start at login", isOn: $autoStart)
                    Toggle("Start minimized", isOn: $startMinimized)
                    Toggle("Confirm on quit", isOn: $confirmExit)
                    Toggle("Connect automatically", isOn: $autoConnect)
                }
                
                Section("Updates") {
                    Toggle("Check for new versions", isOn: $checkUpdates)
                    if checkUpdates {
                        Stepper("Every \(updateDays) days", value: $updateDays, in: 1...30)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct ConnectionSettingsView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var disableUDP = false // TODO: wire to store
    
    var body: some View {
        GroupBox("Connection") {
            Form {
                Section("Ports") {
                    HStack {
                        TextField("TCP", text: $store.tcpPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        TextField("UDP", text: $store.udpPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    Toggle("Disable UDP", isOn: $disableUDP)
                }
                
                Section("Limits") {
                    TextField("Max connections", text: $store.maxConnections)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Max sources per file", text: $store.maxSourcesPerFile)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("Networks") {
                    Toggle("Enable Kad", isOn: $store.enableKad)
                    Toggle("Enable UPnP", isOn: $store.enableUPnP)
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct SecuritySettingsView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var ipFilterLevel = "127" // TODO: wire to store
    @State private var filterServers = false // TODO: wire to store
    @State private var onlyObfuscated = false // TODO: wire to store
    @State private var spamFilter = true // TODO: wire to store
    
    var body: some View {
        GroupBox("Security") {
            Form {
                Section("IP filter") {
                    TextField("Level", text: $ipFilterLevel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    
                    Toggle("Filter servers by IP", isOn: $filterServers)
                    
                    HStack {
                        Button("Reload") { }
                        Button("Edit") { }
                        Button("Update from URL") { }
                    }
                }
                
                Section("Obfuscation") {
                    Toggle("Enable obfuscation", isOn: $store.obfuscationEnabled)
                    Toggle("Only obfuscated connections", isOn: $onlyObfuscated)
                        .disabled(!store.obfuscationEnabled)
                }
                
                Section("Identification") {
                    Toggle("Use secure identification", isOn: $store.secureIdentEnabled)
                    Toggle("Anti-spam filter", isOn: $spamFilter)
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct DirectoriesSettingsView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var sharedDirs: [String] = [] // TODO: wire to store
    
    var body: some View {
        GroupBox("Directories") {
            Form {
                Section("Downloads") {
                    HStack {
                        Text("Incoming:")
                        TextField("", text: $store.downloadDirectory)
                        Button("Browse...") { }
                            .controlSize(.small)
                    }
                    
                    HStack {
                        Text("Temp:")
                        TextField("", text: $store.tempDirectory)
                        Button("Browse...") { }
                            .controlSize(.small)
                    }
                }
                
                Section("Shared") {
                    List(sharedDirs, id: \.self) { dir in
                        Text(dir)
                    }
                    .frame(height: 80)
                    
                    HStack {
                        Button("Add") { }
                        Button("Remove") { }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct FilesSettingsView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var addPaused = false // TODO: wire to store
    @State private var watchClipboard = true // TODO: wire to store
    @State private var autoCleanup = true // TODO: wire to store
    @State private var videoPlayer = "/Applications/VLC.app" // TODO: wire to store
    @State private var createBackup = true // TODO: wire to store
    
    var body: some View {
        GroupBox("Files") {
            Form {
                Section("Downloads") {
                    Toggle("Add new files paused", isOn: $addPaused)
                    Toggle("Watch clipboard for ed2k links", isOn: $watchClipboard)
                    Toggle("Auto-clean file names", isOn: $autoCleanup)
                }
                
                Section("Preview") {
                    HStack {
                        Text("Player:")
                        TextField("", text: $videoPlayer)
                        Button("Browse...") { }
                            .controlSize(.small)
                    }
                    
                    Toggle("Create preview backup", isOn: $createBackup)
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct NotificationsSettingsView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var soundEnabled = false // TODO: wire to store
    @State private var soundFile = "" // TODO: wire to store
    @State private var notifyDownload = true // TODO: wire to store
    @State private var notifyChat = false // TODO: wire to store
    @State private var notifyLog = false // TODO: wire to store
    
    var body: some View {
        GroupBox("Notifications") {
            Form {
                Section("Sound") {
                    Toggle("Enable sounds", isOn: $soundEnabled)
                    if soundEnabled {
                        HStack {
                            TextField("WAV file", text: $soundFile)
                            Button("Browse...") { }
                                .controlSize(.small)
                        }
                        Button("Test") { }
                            .controlSize(.small)
                    }
                }
                
                Section("Events") {
                    Toggle("Download finished", isOn: $notifyDownload)
                    Toggle("Chat message", isOn: $notifyChat)
                    Toggle("Log message", isOn: $notifyLog)
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct DisplaySettingsView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var showTransferToolbar = true // TODO: wire to store
    @State private var showCatInfo = true // TODO: wire to store
    @State private var showPercent = true // TODO: wire to store
    
    var body: some View {
        GroupBox("Display") {
            Form {
                Section("Transfers") {
                    Toggle("Auto-remove completed", isOn: $store.autoRemoveCompleted)
                    Toggle("Show transfers toolbar", isOn: $showTransferToolbar)
                    Toggle("Show category info", isOn: $showCatInfo)
                    Toggle("Show download percentage", isOn: $showPercent)
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct ServersSettingsView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var deadRetries = 3 // TODO: wire to store
    @State private var autoUpdate = false // TODO: wire to store
    @State private var addFromConnect = true // TODO: wire to store
    @State private var addFromClients = false // TODO: wire to store
    @State private var usePriorities = true // TODO: wire to store
    @State private var safeConnect = true // TODO: wire to store
    
    var body: some View {
        GroupBox("Servers") {
            Form {
                Section("Connection") {
                    Stepper("Dead server retries: \(deadRetries)", value: $deadRetries, in: 1...10)
                    Toggle("Auto-update list on startup", isOn: $autoUpdate)
                    Toggle("Add servers when connecting", isOn: $addFromConnect)
                    Toggle("Add servers from clients", isOn: $addFromClients)
                }
                
                Section("Priorities") {
                    Toggle("Use priorities", isOn: $usePriorities)
                    Toggle("Safe connection", isOn: $safeConnect)
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct WebSettingsView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var enabled = false // TODO: wire to store
    @State private var port = "4080" // TODO: wire to store
    @State private var password = "" // TODO: wire to store
    @State private var gzip = true // TODO: wire to store
    
    var body: some View {
        GroupBox("Web interface") {
            Form {
                Section("Server") {
                    Toggle("Enable", isOn: $enabled)
                    TextField("Port", text: $port)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Password", text: $password)
                    Toggle("GZip compression", isOn: $gzip)
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct SchedulerSettingsView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var showingNewSchedule = false

    var body: some View {
        GroupBox("Scheduler") {
            Form {
                Section("Schedules") {
                    Toggle("Enable scheduler", isOn: Binding(
                        get: { store.schedulerEnabled },
                        set: { store.schedulerEnable($0) }
                    ))

                    ForEach(store.scheduleEntries) { entry in
                        HStack {
                            Text(entry.title)
                            Spacer()
                            Text(entry.formattedTime).font(.caption).foregroundStyle(.secondary)
                            ForEach(entry.dayNames, id: \.self) { day in
                                Text(day).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for idx in offsets {
                            store.schedulerRemoveEntry(id: store.scheduleEntries[idx].id)
                        }
                    }

                    Button("New schedule") {
                        showingNewSchedule = true
                    }
                }
            }
            .formStyle(.grouped)
        }
        .sheet(isPresented: $showingNewSchedule) {
            NewScheduleView(store: store)
        }
    }
}

struct NewScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    var store: MacMuleStore

    var body: some View {
        VStack(spacing: 16) {
            Text("New schedule").font(.headline)
            Button("Close") { dismiss() }
        }
        .padding()
        .frame(width: 300, height: 150)
    }
}

struct TweaksSettingsView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var bufferSize = 256 // TODO: wire to store
    @State private var queueSize = 5000 // TODO: wire to store
    @State private var maxConnPer5Sec = 10 // TODO: wire to store
    @State private var maxHalfOpen = 8 // TODO: wire to store
    @State private var checkDiskSpace = true // TODO: wire to store
    @State private var minFreeSpace = 1024 // TODO: wire to store
    
    var body: some View {
        GroupBox("Advanced tweaks") {
            Form {
                Section("Buffers") {
                    Stepper("File buffer size: \(bufferSize) KB", value: $bufferSize, in: 16...1536, step: 128)
                    Stepper("Queue size: \(queueSize)", value: $queueSize, in: 2000...10000, step: 1000)
                }
                
                Section("TCP/IP") {
                    TextField("Max connections/5 sec", text: .constant("\(maxConnPer5Sec)"))
                        .textFieldStyle(.roundedBorder)
                    TextField("Max half-open", text: .constant("\(maxHalfOpen)"))
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("Disk") {
                    Toggle("Check space", isOn: $checkDiskSpace)
                    if checkDiskSpace {
                        TextField("Min free space (MB)", text: .constant("\(minFreeSpace)"))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct StatsSettingsView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var updateInterval = 5 // TODO: wire to store
    @State private var averageTime = 60 // TODO: wire to store
    
    var body: some View {
        GroupBox("Statistics") {
            Form {
                Section("Charts") {
                    Stepper("Refresh interval: \(updateInterval)s", value: $updateInterval, in: 1...60)
                    Stepper("Average time: \(averageTime)s", value: $averageTime, in: 30...300, step: 30)
                }
            }
            .formStyle(.grouped)
        }
    }
}

#Preview {
    SettingsSheetView()
        .environmentObject(MacMuleStore())
}
