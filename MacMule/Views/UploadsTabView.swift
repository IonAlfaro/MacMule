import SwiftUI

struct UploadsTabView: View {
    @EnvironmentObject private var store: MacMuleStore
    
    var body: some View {
        VStack(spacing: 0) {
            // Metrics strip
            HStack(spacing: 24) {
                MetricCard(metric: StatMetric(
                    title: "Uploading",
                    value: "\(store.uploads.filter { $0.status == .downloading }.count)",
                    systemImage: "arrow.up.circle"
                ))
                
                MetricCard(metric: StatMetric(
                    title: "Queued",
                    value: "\(store.uploads.count)",
                    systemImage: "list.bullet"
                ))
                
                MetricCard(metric: StatMetric(
                    title: "Total speed",
                    value: ByteCountFormatter.macMuleString(store.totalUploadSpeed) + "/s",
                    systemImage: "gauge.medium"
                ))
            }
            .padding()
            
            Divider()
            
            // Upload list
            Table(store.uploads) {
                TableColumn("Name") { upload in
                    HStack(spacing: 6) {
                        FileIcon(kind: upload.kind, size: .small)
                        Text(upload.fileName)
                    }
                }
                
                TableColumn("Size") { upload in
                    Text(upload.sizeText)
                        .font(.caption.monospacedDigit())
                }
                .width(100)
                
                TableColumn("Uploaded") { upload in
                    Text(upload.completedText)
                        .font(.caption.monospacedDigit())
                }
                .width(100)
                
                TableColumn("Speed") { upload in
                    Text(upload.uploadSpeedText)
                        .font(.caption.monospacedDigit())
                }
                .width(100)
                
                TableColumn("Client") { _ in
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(120)
                
                TableColumn("Queue") { _ in
                    Text("—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .width(60)
            }
            .tableStyle(.bordered(alternatesRowBackgrounds: true))
            
            Divider()
            
            // Upload slots visualization
            VStack(alignment: .leading, spacing: 8) {
                Text("Upload slots")
                    .font(.headline)
                
                HStack(spacing: 16) {
                    ForEach(0..<5, id: \.self) { slot in
                        UploadSlotView(slot: slot, isActive: slot < store.uploads.filter { $0.status == .downloading }.count)
                    }
                }
                .padding(.vertical, 8)
            }
            .padding()
            .background(.quaternary.opacity(0.2))
        }
    }
}

struct UploadSlotView: View {
    let slot: Int
    let isActive: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Text("Slot \(slot + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            ProgressView(value: isActive ? 0.6 : 0)
                .scaleEffect(y: 0.8)
                .frame(width: 100)
            
            Text(isActive ? "Active" : "Inactive")
                .font(.caption2)
                .foregroundStyle(isActive ? .green : .secondary)
        }
    }
}

#Preview {
    UploadsTabView()
        .environmentObject(MacMuleStore())
}
