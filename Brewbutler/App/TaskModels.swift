import Foundation

struct LogLine: Identifiable, Equatable {
    enum Kind: Equatable {
        case normal
        case stage
        case warning
        case error
        case success
    }

    var id = UUID()
    var text: String
    var kind: Kind

    init(text: String) {
        self.text = text
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("==>") {
            kind = .stage
        } else if trimmed.hasPrefix("Error:") || trimmed.hasPrefix("error:") {
            kind = .error
        } else if trimmed.hasPrefix("Warning:") {
            kind = .warning
        } else if trimmed.contains("successfully") || trimmed.hasPrefix("🍺") {
            kind = .success
        } else {
            kind = .normal
        }
    }
}

/// Writes task logs to Application Support as plain text. Metadata lives in
/// history.json; large text is deliberately kept out of the database/cache.
final class TaskLogStore: @unchecked Sendable {
    let directory: URL
    private let queue = DispatchQueue(label: "dev.brewbutler.tasklog")
    private var writers: [UUID: FileHandle] = [:]

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        directory = base.appendingPathComponent("Brewbutler/Logs", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func begin(recordID: UUID) -> String {
        queue.sync {
            let name = "\(Self.timestamp())-\(recordID.uuidString.prefix(8)).log"
            let url = directory.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            if let handle = try? FileHandle(forWritingTo: url) {
                writers[recordID] = handle
            }
            return name
        }
    }

    func append(_ text: String, recordID: UUID) {
        queue.async {
            guard let handle = self.writers[recordID] else { return }
            if let data = (text + "\n").data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        }
    }

    func end(recordID: UUID) {
        queue.async {
            guard let handle = self.writers.removeValue(forKey: recordID) else { return }
            try? handle.close()
        }
    }

    func text(for fileName: String) -> String {
        let url = directory.appendingPathComponent(fileName)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Filesystem location of a task log. C-13: the in-memory console is
    /// truncated past 4000 lines, the file on disk is the complete record.
    func fileURL(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    func prune(records: [TaskRecord], maxRecords: Int = 20, maxBytes: Int64 = 50 * 1024 * 1024) {
        let fileManager = FileManager.default
        var keep = Array(records.prefix(maxRecords))
        var files: [(URL, Int64)] = []
        for record in keep {
            guard let name = record.logFileName else { continue }
            let url = directory.appendingPathComponent(name)
            let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
            files.append((url, size))
        }
        var total = files.reduce(Int64(0)) { $0 + $1.1 }
        while total > maxBytes && !keep.isEmpty {
            guard let last = keep.popLast(), let name = last.logFileName else { break }
            let url = directory.appendingPathComponent(name)
            let size = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
            try? fileManager.removeItem(at: url)
            total -= size
        }
        // Delete orphaned log files that no longer belong to retained records.
        let keepNames = Set(keep.compactMap(\.logFileName))
        if let entries = try? fileManager.contentsOfDirectory(atPath: directory.path) {
            for entry in entries where entry.hasSuffix(".log") && !keepNames.contains(entry) {
                try? fileManager.removeItem(at: directory.appendingPathComponent(entry))
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

struct TaskRecord: Identifiable, Codable, Hashable {
    enum Status: String, Codable {
        case pending
        case running
        case cancelling
        case succeeded
        case failed
        case unverified
        case cancelled
        case interrupted

        var label: String {
            switch self {
            case .pending: return "排队中"
            case .running: return "运行中"
            case .cancelling: return "正在取消"
            case .succeeded: return "成功"
            case .failed: return "失败"
            case .unverified: return "未确认"
            case .cancelled: return "已取消"
            case .interrupted: return "上次未完成"
            }
        }

        var isTerminal: Bool {
            switch self {
            case .succeeded, .failed, .unverified, .cancelled, .interrupted: return true
            default: return false
            }
        }
    }

    var id: UUID
    var title: String
    var commandText: String
    var action: String
    var packageID: String?
    var packageName: String?
    var packageKind: String?
    var status: Status
    var createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var exitCode: Int32?
    var message: String?
    var suggestion: String?
    var verificationNote: String?
    var logFileName: String?

    var duration: TimeInterval? {
        guard let startedAt else { return nil }
        return (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }
}

/// Aggregated outcome of a batch update (全部更新 / 更新所选), shown once every
/// task in the batch reaches a terminal state.
struct TaskBatchSummary: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var succeeded: Int
    var failed: Int
    var cancelled: Int
    var unverified: Int
    var skipped: Int
    /// Number of *tasks* that failed, as opposed to `failed` which counts
    /// packages for aggregate batches (全部更新 is one task / N package rows).
    /// Kept at the end with a default so existing consumers stay source-compatible.
    var failedTaskCount: Int = 0
    var failedRecordIDs: [UUID]
    var failedTitles: [String]
    var startedAt: Date
    var finishedAt: Date
    var remainingOutdated: Int?

    var total: Int { succeeded + failed + cancelled + unverified + skipped }

    var hasFailures: Bool { failed > 0 || unverified > 0 }
}

final class TaskHistoryStore: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "dev.brewbutler.history")

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent("Brewbutler", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("history.json")
    }

    func load() -> [TaskRecord] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            return (try? JSONDecoder().decode([TaskRecord].self, from: data)) ?? []
        }
    }

    func save(_ records: [TaskRecord]) {
        queue.async {
            guard let data = try? JSONEncoder().encode(Array(records.prefix(20))) else { return }
            try? data.write(to: self.fileURL, options: .atomic)
        }
    }
}
