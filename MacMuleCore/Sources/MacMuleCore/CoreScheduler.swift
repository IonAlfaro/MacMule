import Foundation

public enum ScheduleActionType: String, Codable, Equatable, Sendable {
    case setUploadLimit = "Limit upload"
    case setDownloadLimit = "Limit download"
    case pauseCategory = "Pause category"
    case resumeCategory = "Resume category"
    case limitSources = "Limit sources"
    case setMaxConnections = "Max connections"
    case disconnect = "Disconnect"
    case connect = "Connect"

    public var defaultValue: String {
        switch self {
        case .setUploadLimit: "100"
        case .setDownloadLimit: "500"
        case .pauseCategory: ""
        case .resumeCategory: ""
        case .limitSources: "10"
        case .setMaxConnections: "100"
        case .disconnect: ""
        case .connect: ""
        }
    }
}

public struct ScheduleAction: Codable, Equatable, Sendable {
    public var type: ScheduleActionType
    public var value: String

    public init(type: ScheduleActionType, value: String = "") {
        self.type = type
        self.value = value
    }
}

public struct ScheduleEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var days: Set<Int>
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int
    public var enabled: Bool
    public var actions: [ScheduleAction]

    public init(
        id: UUID = UUID(),
        title: String,
        days: Set<Int> = [1,2,3,4,5],
        startHour: Int = 23,
        startMinute: Int = 0,
        endHour: Int = 7,
        endMinute: Int = 0,
        enabled: Bool = true,
        actions: [ScheduleAction] = [ScheduleAction(type: .setUploadLimit, value: "50")]
    ) {
        self.id = id
        self.title = title
        self.days = days
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.enabled = enabled
        self.actions = actions
    }

    public var dayNames: [String] {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return days.sorted().map { $0 < names.count ? names[$0] : "?" }
    }

    public var formattedTime: String {
        String(format: "%02d:%02d - %02d:%02d", startHour, startMinute, endHour, endMinute)
    }

    public func isActive(at date: Date = Date()) -> Bool {
        guard enabled, !days.isEmpty else { return false }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date) - 1
        guard days.contains(weekday) else { return false }
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let nowMinutes = hour * 60 + minute
        let start = startHour * 60 + startMinute
        let end = endHour * 60 + endMinute
        if start <= end {
            return nowMinutes >= start && nowMinutes <= end
        } else {
            return nowMinutes >= start || nowMinutes <= end
        }
    }
}

public final class CoreScheduler: @unchecked Sendable {
    public var enabled: Bool = false
    private var entries: [ScheduleEntry] = []
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.macmule.scheduler", qos: .utility)
    private let actionHandler: (ScheduleAction) -> Void
    private let logHandler: (@Sendable (String) -> Void)?
    private var lastActiveActionIDs: Set<UUID> = []
    private let fileURL: URL

    public init(
        fileURL: URL,
        actionHandler: @escaping (ScheduleAction) -> Void,
        logHandler: (@Sendable (String) -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self.actionHandler = actionHandler
        self.logHandler = logHandler
    }

    public func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(SchedulerData.self, from: data)
        enabled = decoded.enabled
        entries = decoded.entries
    }

    public func save() throws {
        let data = try JSONEncoder().encode(SchedulerData(enabled: enabled, entries: entries))
        try data.write(to: fileURL, options: .atomic)
    }

    public func allEntries() -> [ScheduleEntry] {
        entries
    }

    public func addEntry(_ entry: ScheduleEntry) {
        entries.append(entry)
        checkAndApply()
        try? save()
    }

    public func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        checkAndApply()
        try? save()
    }

    public func updateEntry(_ entry: ScheduleEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        }
        checkAndApply()
        try? save()
    }

    public func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(60))
        timer.setEventHandler { [weak self] in
            self?.checkAndApply()
        }
        timer.resume()
        self.timer = timer
        checkAndApply()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
        lastActiveActionIDs = []
    }

    private func checkAndApply() {
        guard enabled else { return }
        var activeIDs = Set<UUID>()
        for entry in entries where entry.isActive() {
            activeIDs.insert(entry.id)
            if !lastActiveActionIDs.contains(entry.id) {
                log("Scheduler: entry '\(entry.title)' activated")
                for action in entry.actions {
                    actionHandler(action)
                }
            }
        }
        for id in lastActiveActionIDs.subtracting(activeIDs) {
            if let entry = entries.first(where: { $0.id == id }) {
                log("Scheduler: entry '\(entry.title)' deactivated")
            }
        }
        lastActiveActionIDs = activeIDs
    }

    private func log(_ message: String) {
        logHandler?(message)
    }
}

private struct SchedulerData: Codable {
    var enabled: Bool
    var entries: [ScheduleEntry]
}
