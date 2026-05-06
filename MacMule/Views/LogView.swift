import SwiftUI

struct LogView: View {
    @EnvironmentObject private var store: MacMuleStore
    @State private var levelFilter: MacMuleCoreLogLevel? = nil

    private var filteredLogs: [MacMuleCoreLogEntry] {
        guard let level = levelFilter else { return store.coreRuntimeLogs }
        return store.coreRuntimeLogs.filter { $0.level == level }
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(
                title: "Logs",
                subtitle: "\(store.coreRuntimeLogs.count) entr" + (store.coreRuntimeLogs.count == 1 ? "y" : "ies"),
                systemImage: "text.alignleft"
            )

            HStack(spacing: 6) {
                FilterPill(label: "All", count: store.coreRuntimeLogs.count, isSelected: levelFilter == nil) {
                    levelFilter = nil
                }
                FilterPill(
                    label: "Info",
                    systemImage: "i.circle",
                    count: store.coreRuntimeLogs.filter { $0.level == .info }.count,
                    isSelected: levelFilter == .info
                ) { levelFilter = levelFilter == .info ? nil : .info }
                FilterPill(
                    label: "Warnings",
                    systemImage: "exclamationmark.triangle",
                    count: store.coreRuntimeLogs.filter { $0.level == .warning }.count,
                    isSelected: levelFilter == .warning
                ) { levelFilter = levelFilter == .warning ? nil : .warning }
                FilterPill(
                    label: "Errors",
                    systemImage: "xmark.octagon",
                    count: store.coreRuntimeLogs.filter { $0.level == .error }.count,
                    isSelected: levelFilter == .error
                ) { levelFilter = levelFilter == .error ? nil : .error }
            }
            .padding(.horizontal, MacMuleTheme.spacingXL)
            .padding(.bottom, 8)

            Divider()

            if filteredLogs.isEmpty {
                EmptySectionView(
                    icon: "text.alignleft",
                    title: "No log entries",
                    subtitle: levelFilter != nil
                        ? "There are no logs for the selected level."
                        : "The core has not emitted logs yet."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredLogs) { entry in
                            logEntryRow(entry)
                        }
                    }
                    .padding(.horizontal, MacMuleTheme.spacingXL)
                    .padding(.vertical, 10)
                }
            }
        }
        .macMulePageBackground()
    }

    private func logEntryRow(_ entry: MacMuleCoreLogEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .leading)

            Text(entry.level.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(entry.level.logBadgeColor)
                .frame(width: 44, alignment: .leading)

            Text(entry.message)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(MacMuleTheme.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(MacMuleTheme.divider, lineWidth: 1)
        }
    }
}

private extension MacMuleCoreLogLevel {
    var logBadgeColor: Color {
        switch self {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}
