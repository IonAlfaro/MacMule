import SwiftUI

// MARK: - Design System

enum MacMuleTheme {
    // Background hierarchy
    static let page = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceElevated = Color(nsColor: .textBackgroundColor)

    // Text hierarchy
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    // Borders & dividers
    static let border = Color.secondary.opacity(0.13)
    static let borderFocused = Color.accentColor.opacity(0.3)
    static let divider = Color.secondary.opacity(0.08)

    // Semantic colors
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue
    static let download = Color.blue
    static let upload = Color.green
    static let network = Color.teal
    static let kad = Color.indigo

    // Spacing
    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 12
    static let spacingLG: CGFloat = 16
    static let spacingXL: CGFloat = 24
    static let spacingXXL: CGFloat = 32

    // Border radius
    static let radiusSM: CGFloat = 5
    static let radiusMD: CGFloat = 8
    static let radiusLG: CGFloat = 8
    static let radiusXL: CGFloat = 8

    // Accent tints for metric categories
    static func metricTint(for image: String) -> Color {
        if image.contains("arrow.down") { return .blue }
        if image.contains("arrow.up") { return .green }
        if image.contains("person") { return .teal }
        if image.contains("bolt") { return .yellow }
        if image.contains("checkmark") { return .green }
        if image.contains("server") { return .indigo }
        if image.contains("antenna") || image.contains("network") { return .cyan }
        return .accentColor
    }
}

struct MacMulePageBackdrop: View {
    var body: some View {
        ZStack {
            MacMuleTheme.page
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    MacMuleTheme.network.opacity(0.045),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)
        }
    }
}

// MARK: - View Modifiers

extension View {
    func macMuleSurface(cornerRadius: CGFloat = MacMuleTheme.radiusMD) -> some View {
        background(MacMuleTheme.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(MacMuleTheme.border, lineWidth: 1)
            }
    }

    func macMuleElevated(cornerRadius: CGFloat = MacMuleTheme.radiusMD) -> some View {
        background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(MacMuleTheme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }

    func macMulePageBackground() -> some View {
        background(MacMulePageBackdrop())
    }

    func macMuleHoverHighlight(_ isHovered: Bool, tint: Color = .accentColor, _ action: @escaping () -> Void = {}) -> some View {
        self
            .background(
                isHovered ? tint.opacity(0.06) : .clear,
                in: RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
                    .strokeBorder(isHovered ? tint.opacity(0.18) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD))
    }
}

// MARK: - Header Bar

struct HeaderBar: View {
    let title: String
    var subtitle: String = ""
    var systemImage: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: MacMuleTheme.spacingMD) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                if subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, MacMuleTheme.spacingXL)
        .padding(.top, MacMuleTheme.spacingLG)
        .padding(.bottom, MacMuleTheme.spacingMD)
        .background(.bar)
        .background {
            VStack(spacing: 0) {
                Spacer()
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.clear, Color.accentColor.opacity(0.16), .clear],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - Metrics Strip

struct MetricsStrip: View {
    let metrics: [StatMetric]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MacMuleTheme.spacingSM) {
                ForEach(metrics) { MetricCard(metric: $0) }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: MacMuleTheme.spacingSM)],
                spacing: MacMuleTheme.spacingSM
            ) {
                ForEach(metrics) { MetricCard(metric: $0) }
            }
        }
    }
}

struct MetricCard: View {
    let metric: StatMetric
    private var tint: Color { MacMuleTheme.metricTint(for: metric.systemImage) }

    var body: some View {
        HStack(spacing: MacMuleTheme.spacingSM) {
            Image(systemName: metric.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: MacMuleTheme.radiusSM))

            VStack(alignment: .leading, spacing: 1) {
                Text(metric.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(metric.value)
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, MacMuleTheme.spacingMD)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52)
        .macMuleElevated()
        .contentShape(RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD))
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(tint.opacity(0.5))
                .frame(width: 20, height: 2)
                .clipShape(Capsule())
                .padding(.leading, MacMuleTheme.spacingMD)
        }
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let label: String
    var systemImage: String? = nil
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = systemImage {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(label)
                    .font(.caption.weight(.semibold))
                if let count {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : Color(nsColor: .tertiaryLabelColor))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(isSelected ? .white.opacity(0.15) : Color(nsColor: .quaternaryLabelColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isSelected ? Color.accentColor : MacMuleTheme.surface,
                in: RoundedRectangle(cornerRadius: MacMuleTheme.radiusSM)
            )
            .overlay {
                RoundedRectangle(cornerRadius: MacMuleTheme.radiusSM)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : MacMuleTheme.border, lineWidth: 1)
            }
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: MacMuleTheme.radiusSM))
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResult
    let addAction: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: MacMuleTheme.spacingMD) {
            FileIcon(kind: result.kind, size: .normal)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.fileName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(result.sizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.quaternary)
                    Text(result.network)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.quaternary)
                    Text("\(result.sources) sources")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: addAction) {
                Label("Download", systemImage: "arrow.down.circle.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Download")
        }
        .padding(.vertical, 9)
        .padding(.horizontal, MacMuleTheme.spacingMD)
        .background(
            isHovered ? Color.accentColor.opacity(0.08) : MacMuleTheme.surface.opacity(0.55),
            in: RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
                .strokeBorder(isHovered ? Color.accentColor.opacity(0.18) : MacMuleTheme.divider, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD))
        .onHover { isHovered = $0 }
    }
}

// MARK: - Download Row

struct DownloadRow: View {
    let item: TransferItem
    var onTogglePause: (() -> Void)?
    var onDelete: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: MacMuleTheme.spacingMD) {
            FileIcon(kind: item.kind)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.fileName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    StatusBadge(status: item.status)
                }

                if item.status == .downloading || item.status == .paused || item.status == .verifying {
                    ChunkMap(chunks: item.chunks)
                }

                HStack(spacing: 6) {
                    Text("\(Int(item.progress * 100))%")
                        .font(.caption.monospacedDigit().weight(.medium))

                    ProgressView(value: item.progress)
                        .controlSize(.small)
                        .tint(progressTint)
                        .frame(maxWidth: 120)

                    Text(item.completedText + " / " + item.sizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if item.downloadSpeedBytesPerSecond > 0 {
                        Text(item.estimatedTimeRemainingText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }

                    if item.sources > 0 {
                        Label("\(item.sources)", systemImage: "person.2")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .labelStyle(.iconOnly)
                        Text("\(item.sources)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if item.downloadSpeedBytesPerSecond > 0 {
                        Text(item.downloadSpeedText)
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.blue)
                    }
                }
            }

            DownloadRowActions(
                item: item,
                onTogglePause: onTogglePause,
                onDelete: onDelete
            )
            .opacity(isHovered ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, MacMuleTheme.spacingMD)
        .background(
            isHovered ? Color.accentColor.opacity(0.05) : MacMuleTheme.surface.opacity(0.4),
            in: RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
                .strokeBorder(isHovered ? Color.accentColor.opacity(0.15) : MacMuleTheme.divider, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(progressTint.opacity(item.status == .queued ? 0.25 : 0.7))
                .frame(width: 3)
                .padding(.vertical, 10)
        }
        .contentShape(RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD))
        .onHover { isHovered = $0 }
    }

    private var progressTint: Color {
        switch item.status {
        case .downloading: .blue
        case .verifying: .indigo
        case .completed: .green
        case .failed: .red
        case .paused: .orange
        default: .secondary
        }
    }
}

private struct DownloadRowActions: View {
    let item: TransferItem
    var onTogglePause: (() -> Void)?
    var onDelete: (() -> Void)?

    private var canPauseToggle: Bool {
        item.status != .completed && item.status != .failed
    }

    var body: some View {
        HStack(spacing: 4) {
            if let onTogglePause, canPauseToggle {
                Button { onTogglePause() } label: {
                    Image(systemName: item.status == .paused ? "play.fill" : "pause.fill")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help(item.status == .paused ? "Resume download" : "Pause download")
            }
            if let onDelete {
                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Remove download")
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: 60, alignment: .trailing)
    }
}

// MARK: - Upload Row

struct UploadRow: View {
    let item: TransferItem
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: MacMuleTheme.spacingMD) {
            FileIcon(kind: item.kind)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.fileName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    if item.uploadSpeedBytesPerSecond > 0 {
                        Text(ByteCountFormatter.macMuleString(item.uploadSpeedBytesPerSecond) + "/s")
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 6) {
                    Text(item.sizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if item.sources > 0 {
                        Text("\(item.sources) requesting")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, MacMuleTheme.spacingMD)
        .background(
            isHovered ? Color.green.opacity(0.06) : MacMuleTheme.surface.opacity(0.4),
            in: RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
                .strokeBorder(isHovered ? Color.green.opacity(0.2) : MacMuleTheme.divider, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD))
        .onHover { isHovered = $0 }
    }
}

// MARK: - Download Detail Panel

struct DownloadDetailView: View {
    @EnvironmentObject private var store: MacMuleStore
    let item: TransferItem?

    var body: some View {
        ScrollView {
            if let item {
                VStack(alignment: .leading, spacing: MacMuleTheme.spacingLG) {
                    HStack(alignment: .top, spacing: MacMuleTheme.spacingMD) {
                        FileIcon(kind: item.kind, size: .normal)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.fileName)
                                .font(.headline)
                                .lineLimit(3)
                            Text(item.ed2kHash)
                                .font(.caption.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }

                    HStack(spacing: MacMuleTheme.spacingSM) {
                        if item.status != .completed && item.status != .failed {
                            Button {
                                store.togglePause(downloadID: item.id)
                            } label: {
                                Label(
                                    item.status == .paused ? "Resume" : "Pause",
                                    systemImage: item.status == .paused ? "play.fill" : "pause.fill"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button(role: .destructive) {
                            store.removeDownload(downloadID: item.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading, spacing: MacMuleTheme.spacingSM) {
                        HStack {
                            Text("Progress")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Spacer()
                            Text("\(Int(item.progress * 100))%")
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                        HStack(alignment: .center, spacing: 10) {
                            ProgressView(value: item.progress)
                                .tint(progressTint)
                            StatusBadge(status: item.status)
                        }
                    }

                    ChunkMap(chunks: item.chunks)

                    VStack(spacing: 0) {
                        DetailRow(title: "Size", value: item.sizeText)
                        Divider().opacity(0.6)
                        DetailRow(title: "Completed", value: item.completedText)
                        Divider().opacity(0.6)
                        DetailRow(title: "Speed", value: item.downloadSpeedBytesPerSecond > 0 ? item.downloadSpeedText : "—")
                        Divider().opacity(0.6)
                        DetailRow(title: "Time left", value: item.estimatedTimeRemainingText)
                        Divider().opacity(0.6)
                        DetailRow(title: "Sources", value: "\(item.sources)")
                        Divider().opacity(0.6)
                        DetailRow(title: "Availability", value: "\(item.availability)")
                    }
                    .macMuleElevated()
                }
                .padding(MacMuleTheme.spacingLG)
            } else {
                EmptyDetailPlaceholder(
                    icon: "arrow.down.circle",
                    title: "Select a download",
                    subtitle: "Click a transfer to view its details"
                )
            }
        }
        .macMulePageBackground()
    }

    private var progressTint: Color {
        switch item?.status {
        case .downloading: .blue
        case .verifying: .indigo
        case .completed: .green
        case .failed: .red
        case .paused: .orange
        default: .secondary
        }
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, MacMuleTheme.spacingMD)
        .padding(.vertical, 9)
    }
}

// MARK: - Empty States

struct EmptyDetailPlaceholder: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: MacMuleTheme.spacingSM) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.accentColor.opacity(0.6))
                .frame(width: 56, height: 56)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD))
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 200)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptySectionView: View {
    let icon: String
    let title: String
    let subtitle: String
    var action: (() -> Void)? = nil
    var actionLabel: String? = nil

    var body: some View {
        VStack(spacing: MacMuleTheme.spacingMD) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Color.accentColor.opacity(0.6))
                .frame(width: 64, height: 64)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD))
                .overlay {
                    RoundedRectangle(cornerRadius: MacMuleTheme.radiusMD)
                        .strokeBorder(Color.accentColor.opacity(0.12), lineWidth: 1)
                }
            VStack(spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
            if let action, let actionLabel {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, MacMuleTheme.spacingXS)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Chunk Map

struct ChunkMap: View {
    let chunks: [ChunkState]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Parts")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(chunks.filter { $0 == .complete }.count) / \(chunks.count)")
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 1.5) {
                ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(chunk.tint)
                        .frame(maxWidth: .infinity, minHeight: 10, maxHeight: 10)
                }
            }
        }
    }
}

// MARK: - File Icon

enum FileIconSize {
    case small, normal, large
    var dimension: CGFloat {
        switch self {
        case .small: 20
        case .normal: 34
        case .large: 46
        }
    }
    var font: Font {
        switch self {
        case .small: .caption
        case .normal: .title3
        case .large: .title2
        }
    }
    var cornerRadius: CGFloat {
        switch self {
        case .small: 4
        case .normal: 6
        case .large: 8
        }
    }
}

struct FileIcon: View {
    let kind: FileKind
    var size: FileIconSize = .normal

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(size.font)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(kind.tint)
            .frame(width: size.dimension, height: size.dimension)
            .background(kind.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: size.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .strokeBorder(kind.tint.opacity(0.15), lineWidth: 1)
            }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: TransferStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(status.tint.opacity(0.15), lineWidth: 1)
            }
    }
}

// MARK: - Throughput Chart

struct ThroughputChart: View {
    var downloadHistory: [Double] = Array(repeating: 0, count: 60)
    var uploadHistory: [Double] = Array(repeating: 0, count: 60)
    var downloadSpeed: Int64 = 0
    var uploadSpeed: Int64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: MacMuleTheme.spacingMD) {
            HStack {
                Label("Traffic", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                    .labelStyle(.titleOnly)
                Spacer()
                HStack(spacing: MacMuleTheme.spacingLG) {
                    SpeedLegend(color: .blue, label: "↓ " + ByteCountFormatter.macMuleString(downloadSpeed) + "/s")
                    SpeedLegend(color: .green, label: "↑ " + ByteCountFormatter.macMuleString(uploadSpeed) + "/s")
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    VStack(spacing: 0) {
                        ForEach(0..<4) { i in
                            Divider().opacity(0.25)
                            if i < 3 { Spacer() }
                        }
                    }

                    SpeedAreaPath(values: uploadHistory, size: proxy.size)
                        .fill(LinearGradient(
                            colors: [.green.opacity(0.15), .clear],
                            startPoint: .top, endPoint: .bottom
                        ))
                    SpeedAreaPath(values: downloadHistory, size: proxy.size)
                        .fill(LinearGradient(
                            colors: [.blue.opacity(0.15), .clear],
                            startPoint: .top, endPoint: .bottom
                        ))
                    SpeedLinePath(values: uploadHistory, size: proxy.size)
                        .stroke(.green.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    SpeedLinePath(values: downloadHistory, size: proxy.size)
                        .stroke(.blue.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: 140)
            .padding(MacMuleTheme.spacingMD)
            .macMuleElevated()
        }
    }
}

private struct SpeedLegend: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct SpeedLinePath: Shape {
    let values: [Double]
    let size: CGSize

    func path(in _: CGRect) -> Path {
        guard values.isEmpty == false else { return Path() }
        var path = Path()
        let step = size.width / CGFloat(max(values.count - 1, 1))
        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * step
            let y = size.height * (1 - CGFloat(value))
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

private struct SpeedAreaPath: Shape {
    let values: [Double]
    let size: CGSize

    func path(in _: CGRect) -> Path {
        guard values.isEmpty == false else { return Path() }
        var path = Path()
        let step = size.width / CGFloat(max(values.count - 1, 1))
        path.move(to: CGPoint(x: 0, y: size.height))
        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * step
            let y = size.height * (1 - CGFloat(value))
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Color extensions

extension FileKind {
    var tint: Color {
        switch self {
        case .video: .indigo
        case .audio: .pink
        case .archive: .orange
        case .document: .blue
        case .application: .teal
        case .other: .secondary
        }
    }
}

extension TransferStatus {
    var tint: Color {
        switch self {
        case .queued: .secondary
        case .downloading: .blue
        case .paused: .orange
        case .verifying: .indigo
        case .completed: .green
        case .failed: .red
        }
    }
}

extension ChunkState {
    var tint: Color {
        switch self {
        case .missing: Color.secondary.opacity(0.1)
        case .queued: .teal.opacity(0.4)
        case .active: .blue
        case .complete: .green
        case .corrupt: .red
        }
    }
}

extension ServerHealth {
    var tint: Color {
        switch self {
        case .connected: .green
        case .available: .blue
        case .unavailable: .red
        }
    }
}

extension MacMuleCoreLogLevel {
    var tint: Color {
        switch self {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}

// MARK: - Source Row

struct SourceRowView: View {
    let source: SourceDetail

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 7, height: 7)
            Text(source.stateText)
                .font(.subheadline)
                .frame(width: 120, alignment: .leading)
            Text(source.clientName)
                .font(.subheadline)
                .frame(width: 160, alignment: .leading)
                .lineLimit(1)
            Text(source.clientSoftware)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)
            Text(ByteCountFormatter.macMuleString(source.downloadSpeedBytesPerSecond) + "/s")
                .font(.caption.monospacedDigit())
                .frame(width: 100, alignment: .leading)
            Text("\(source.partsAvailable)/\(source.totalParts)")
                .font(.caption.monospacedDigit())
                .frame(width: 60, alignment: .leading)
            Text("\(source.queueRank)")
                .font(.caption.monospacedDigit())
                .frame(width: 50, alignment: .leading)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var stateColor: Color {
        switch source.state {
        case .downloading: .green
        case .connecting, .onQueue: .blue
        case .noNeededParts: .orange
        case .tooManyConnections, .banned, .error: .red
        }
    }
}
