import SwiftUI

struct SharedTabView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var showingAddFolder = false
    
    var body: some View {
        HSplitView {
            // Left: Directory tree
            VStack(spacing: 0) {
                Text("Shared folders")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                
                Text("No shared folders configured. Add folders in Preferences > Directories.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                
                Spacer()
                
                Divider()
                
                HStack {
                    Button("Add") {
                        // Open preferences
                    }
                    .controlSize(.small)
                    
                    Button("Rescan") {
                        // Trigger rescan
                    }
                    .controlSize(.small)
                }
                .padding(8)
            }
            .frame(minWidth: 200)
            
            // Right: Shared files list + detail
            VStack(spacing: 0) {
                Table(store.sharedFiles) {
                    TableColumn("Name") { file in
                        HStack(spacing: 6) {
                            FileIcon(kind: file.kind, size: .small)
                            Text(file.fileName)
                        }
                    }
                    
                    TableColumn("Size") { file in
                        Text(file.sizeText)
                            .font(.caption.monospacedDigit())
                    }
                    .width(100)
                    
                    TableColumn("Requests") { file in
                        Text("\(file.requests)")
                            .font(.caption.monospacedDigit())
                    }
                    .width(80)
                    
                    TableColumn("Uploaded") { file in
                        Text(file.uploadedText)
                            .font(.caption.monospacedDigit())
                    }
                    .width(100)
                }
                .tableStyle(.bordered(alternatesRowBackgrounds: true))
                
                Divider()
                
                // File detail
                if let file = store.sharedFiles.first {
                    Form {
                        Section("Information") {
                            LabeledContent("Name", value: file.fileName)
                            LabeledContent("Size", value: file.sizeText)
                            LabeledContent("Requests", value: "\(file.requests)")
                            LabeledContent("Uploaded", value: file.uploadedText)
                        }
                        
                        Section("Actions") {
                            Button("Copy ed2k link") {
                                // Copy ed2k link
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .padding()
                }
            }
        }
        .sheet(isPresented: $showingAddFolder) {
            // Add folder picker sheet
        }
    }
}

#Preview {
    SharedTabView()
        .environmentObject(MacMuleStore())
}
