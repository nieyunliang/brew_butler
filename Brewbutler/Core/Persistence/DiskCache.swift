import Foundation

public struct CachedValue<Value> {
    public var value: Value
    public var savedAt: Date
}

/// Small JSON file cache in Application Support. Used for the installed index,
/// outdated results, vulnerability reports and capability detection. No large
/// text (logs / raw JSON) is stored here.
public final class DiskCache: @unchecked Sendable {
    public let directory: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "dev.brewbutler.diskcache")

    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.directory = base.appendingPathComponent("Brewbutler/Cache", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func url(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "-")
        return directory.appendingPathComponent("\(safe).json")
    }

    public func load<Value: Codable>(_ type: Value.Type, key: String) -> CachedValue<Value>? {
        queue.sync(execute: { () -> CachedValue<Value>? in
            guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
            guard let envelope = try? JSONDecoder().decode(DecodeEnvelope<Value>.self, from: data) else { return nil }
            return CachedValue(value: envelope.value, savedAt: envelope.savedAt)
        })
    }

    public func save<Value: Encodable>(_ value: Value, key: String, savedAt: Date = Date()) {
        queue.sync {
            let envelope = EncodeEnvelope(value: value, savedAt: savedAt)
            guard let data = try? JSONEncoder().encode(envelope) else { return }
            try? data.write(to: url(for: key), options: .atomic)
        }
    }

    public func remove(key: String) {
        queue.sync {
            try? fileManager.removeItem(at: url(for: key))
        }
    }

    public func removeAll() {
        queue.sync {
            try? fileManager.removeItem(at: directory)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public func age(of key: String) -> TimeInterval? {
        queue.sync {
            guard let attributes = try? fileManager.attributesOfItem(atPath: url(for: key).path),
                  let date = attributes[.modificationDate] as? Date else { return nil }
            return Date().timeIntervalSince(date)
        }
    }

    private struct DecodeEnvelope<Value: Codable>: Decodable {
        var value: Value
        var savedAt: Date
    }

    private struct EncodeEnvelope<Value: Encodable>: Encodable {
        var value: Value
        var savedAt: Date
    }
}
