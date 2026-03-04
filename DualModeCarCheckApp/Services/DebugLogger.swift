import Foundation
import Observation

nonisolated enum DebugLogCategory: String, CaseIterable, Sendable, Identifiable, Codable {
    case automation = "Automation"
    case login = "Login"
    case ppsr = "PPSR"
    case superTest = "Super Test"
    case network = "Network"
    case proxy = "Proxy"
    case dns = "DNS"
    case vpn = "VPN"
    case url = "URL Rotation"
    case fingerprint = "Fingerprint"
    case stealth = "Stealth"
    case webView = "WebView"
    case persistence = "Persistence"
    case system = "System"
    case evaluation = "Evaluation"
    case screenshot = "Screenshot"
    case timing = "Timing"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .automation: "gearshape.2.fill"
        case .login: "person.badge.key.fill"
        case .ppsr: "car.side.fill"
        case .superTest: "bolt.horizontal.circle.fill"
        case .network: "wifi"
        case .proxy: "network"
        case .dns: "lock.shield.fill"
        case .vpn: "shield.lefthalf.filled"
        case .url: "arrow.triangle.2.circlepath"
        case .fingerprint: "fingerprint"
        case .stealth: "eye.slash.fill"
        case .webView: "safari.fill"
        case .persistence: "externaldrive.fill"
        case .system: "cpu"
        case .evaluation: "chart.bar.xaxis"
        case .screenshot: "camera.fill"
        case .timing: "stopwatch.fill"
        }
    }

    var color: String {
        switch self {
        case .automation: "blue"
        case .login: "green"
        case .ppsr: "cyan"
        case .superTest: "purple"
        case .network: "orange"
        case .proxy: "red"
        case .dns: "indigo"
        case .vpn: "teal"
        case .url: "mint"
        case .fingerprint: "pink"
        case .stealth: "gray"
        case .webView: "blue"
        case .persistence: "brown"
        case .system: "secondary"
        case .evaluation: "yellow"
        case .screenshot: "purple"
        case .timing: "orange"
        }
    }
}

nonisolated enum DebugLogLevel: String, CaseIterable, Sendable, Comparable, Codable {
    case trace = "TRACE"
    case debug = "DEBUG"
    case info = "INFO"
    case success = "OK"
    case warning = "WARN"
    case error = "ERR"
    case critical = "CRIT"

    nonisolated static func < (lhs: DebugLogLevel, rhs: DebugLogLevel) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var sortOrder: Int {
        switch self {
        case .trace: 0
        case .debug: 1
        case .info: 2
        case .success: 3
        case .warning: 4
        case .error: 5
        case .critical: 6
        }
    }

    var emoji: String {
        switch self {
        case .trace: "🔍"
        case .debug: "🐛"
        case .info: "ℹ️"
        case .success: "✅"
        case .warning: "⚠️"
        case .error: "❌"
        case .critical: "🔴"
        }
    }
}

nonisolated struct DebugLogEntry: Identifiable, Sendable, Codable {
    let id: UUID
    let timestamp: Date
    let category: DebugLogCategory
    let level: DebugLogLevel
    let message: String
    let detail: String?
    let sessionId: String?
    let durationMs: Int?
    let metadata: [String: String]?

    init(
        category: DebugLogCategory,
        level: DebugLogLevel,
        message: String,
        detail: String? = nil,
        sessionId: String? = nil,
        durationMs: Int? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.category = category
        self.level = level
        self.message = message
        self.detail = detail
        self.sessionId = sessionId
        self.durationMs = durationMs
        self.metadata = metadata
    }

    var formattedTime: String {
        DateFormatters.timeWithMillis.string(from: timestamp)
    }

    var fullTimestamp: String {
        DateFormatters.fullTimestamp.string(from: timestamp)
    }

    var compactLine: String {
        let dur = durationMs.map { " [\($0)ms]" } ?? ""
        let sess = sessionId.map { " <\($0)>" } ?? ""
        return "[\(formattedTime)] [\(level.rawValue)] [\(category.rawValue)]\(sess)\(dur) \(message)"
    }

    var exportLine: String {
        let dur = durationMs.map { " duration=\($0)ms" } ?? ""
        let sess = sessionId.map { " session=\($0)" } ?? ""
        let det = detail.map { " | \($0)" } ?? ""
        let meta = metadata.map { dict in
            " {" + dict.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") + "}"
        } ?? ""
        return "[\(fullTimestamp)] [\(level.rawValue)] [\(category.rawValue)]\(sess)\(dur) \(message)\(det)\(meta)"
    }
}

@Observable
@MainActor
class DebugLogger {
    static let shared = DebugLogger()

    private(set) var entries: [DebugLogEntry] = []
    var maxEntries: Int = 10000
    var minimumLevel: DebugLogLevel = .trace
    var enabledCategories: Set<DebugLogCategory> = Set(DebugLogCategory.allCases)
    var isRecording: Bool = true

    private var sessionTimers: [String: Date] = [:]
    private var stepTimers: [String: Date] = [:]

    var filteredEntries: [DebugLogEntry] {
        entries
    }

    var entryCount: Int { entries.count }

    var errorCount: Int {
        entries.filter { $0.level >= .error }.count
    }

    var warningCount: Int {
        entries.filter { $0.level == .warning }.count
    }

    func log(
        _ message: String,
        category: DebugLogCategory = .system,
        level: DebugLogLevel = .info,
        detail: String? = nil,
        sessionId: String? = nil,
        durationMs: Int? = nil,
        metadata: [String: String]? = nil
    ) {
        guard isRecording else { return }
        guard level >= minimumLevel else { return }
        guard enabledCategories.contains(category) else { return }

        let entry = DebugLogEntry(
            category: category,
            level: level,
            message: message,
            detail: detail,
            sessionId: sessionId,
            durationMs: durationMs,
            metadata: metadata
        )

        entries.insert(entry, at: 0)

        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }

    func startTimer(key: String) {
        stepTimers[key] = Date()
    }

    func stopTimer(key: String) -> Int? {
        guard let start = stepTimers.removeValue(forKey: key) else { return nil }
        return Int(Date().timeIntervalSince(start) * 1000)
    }

    func startSession(_ sessionId: String, category: DebugLogCategory, message: String) {
        sessionTimers[sessionId] = Date()
        log(message, category: category, level: .info, sessionId: sessionId)
    }

    func endSession(_ sessionId: String, category: DebugLogCategory, message: String, level: DebugLogLevel = .info) {
        let durationMs: Int?
        if let start = sessionTimers.removeValue(forKey: sessionId) {
            durationMs = Int(Date().timeIntervalSince(start) * 1000)
        } else {
            durationMs = nil
        }
        log(message, category: category, level: level, sessionId: sessionId, durationMs: durationMs)
    }

    func clearAll() {
        entries.removeAll()
        sessionTimers.removeAll()
        stepTimers.removeAll()
    }

    func exportFullLog() -> String {
        let header = """
        === DEBUG LOG EXPORT ===
        Exported: \(DebugLogEntry(category: .system, level: .info, message: "").fullTimestamp)
        Total Entries: \(entries.count)
        Errors: \(errorCount)
        Warnings: \(warningCount)
        ========================
        
        """
        let lines = entries.reversed().map(\.exportLine).joined(separator: "\n")
        return header + lines
    }

    func exportFilteredLog(
        categories: Set<DebugLogCategory>? = nil,
        minLevel: DebugLogLevel? = nil,
        sessionId: String? = nil,
        since: Date? = nil
    ) -> String {
        var filtered = entries.reversed() as [DebugLogEntry]
        if let cats = categories {
            filtered = filtered.filter { cats.contains($0.category) }
        }
        if let lvl = minLevel {
            filtered = filtered.filter { $0.level >= lvl }
        }
        if let sid = sessionId {
            filtered = filtered.filter { $0.sessionId == sid }
        }
        if let date = since {
            filtered = filtered.filter { $0.timestamp >= date }
        }
        return filtered.map(\.exportLine).joined(separator: "\n")
    }

    func entriesForSession(_ sessionId: String) -> [DebugLogEntry] {
        entries.filter { $0.sessionId == sessionId }
    }

    var uniqueSessionIds: [String] {
        let ids = entries.compactMap(\.sessionId)
        return Array(Set(ids)).sorted()
    }

    var categoryBreakdown: [(category: DebugLogCategory, count: Int)] {
        var counts: [DebugLogCategory: Int] = [:]
        for entry in entries {
            counts[entry.category, default: 0] += 1
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    var levelBreakdown: [(level: DebugLogLevel, count: Int)] {
        var counts: [DebugLogLevel: Int] = [:]
        for entry in entries {
            counts[entry.level, default: 0] += 1
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.level < $1.level }
    }
}
