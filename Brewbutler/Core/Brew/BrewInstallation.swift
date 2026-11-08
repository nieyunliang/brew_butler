import Foundation

public struct BrewVersion: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let raw: String

    public init?(string: String) {
        let pattern = #"(\d+)\.(\d+)\.(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)),
              match.numberOfRanges == 4,
              let majorRange = Range(match.range(at: 1), in: string),
              let minorRange = Range(match.range(at: 2), in: string),
              let patchRange = Range(match.range(at: 3), in: string),
              let major = Int(string[majorRange]),
              let minor = Int(string[minorRange]),
              let patch = Int(string[patchRange])
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
        // raw 只保留版本号本身：`brew --version` 的第一行是「Homebrew 7.0.12」，
        // 若把整行塞进 raw，summary 会拼成「Homebrew Homebrew 7.0.12」。
        self.raw = (string as NSString).substring(with: match.range(at: 0))
    }

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.raw = "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: BrewVersion, rhs: BrewVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { raw }
}

public struct BrewCapabilities: Codable, Hashable, Sendable {
    public var versionText: String
    public var vulns: Bool
    public var outdatedJSONv2: Bool
    public var listVersionsJSON: Bool
    public var jqPath: String?
    public var dryRun: Bool
    public var trust: Bool
    public var updateIfNeeded: Bool
    public var missing: Bool
    public var log: Bool
    public var servicesJSON: Bool
    public var checkedAt: Date
    public var degradedReasons: [String]

    public init(
        versionText: String = "",
        vulns: Bool = false,
        outdatedJSONv2: Bool = false,
        listVersionsJSON: Bool = false,
        jqPath: String? = nil,
        dryRun: Bool = false,
        trust: Bool = false,
        updateIfNeeded: Bool = false,
        missing: Bool = false,
        log: Bool = false,
        servicesJSON: Bool = false,
        checkedAt: Date = Date(),
        degradedReasons: [String] = []
    ) {
        self.versionText = versionText
        self.vulns = vulns
        self.outdatedJSONv2 = outdatedJSONv2
        self.listVersionsJSON = listVersionsJSON
        self.jqPath = jqPath
        self.dryRun = dryRun
        self.trust = trust
        self.updateIfNeeded = updateIfNeeded
        self.missing = missing
        self.log = log
        self.servicesJSON = servicesJSON
        self.checkedAt = checkedAt
        self.degradedReasons = degradedReasons
    }

    public var version: BrewVersion? { BrewVersion(string: versionText) }

    public var isDegraded: Bool { !degradedReasons.isEmpty }

    public var summary: String {
        let versionLabel = version.map(\.raw) ?? versionText
        return versionLabel.isEmpty ? "Homebrew" : "Homebrew \(versionLabel)"
    }
}

public struct BrewInstallation: Codable, Sendable, Hashable {
    public var executablePath: String
    public var prefix: String
    public var cellar: String
    public var cache: String
    public var repository: String
    public var capabilities: BrewCapabilities

    public init(
        executablePath: String,
        prefix: String,
        cellar: String,
        cache: String,
        repository: String,
        capabilities: BrewCapabilities
    ) {
        self.executablePath = executablePath
        self.prefix = prefix
        self.cellar = cellar
        self.cache = cache
        self.repository = repository
        self.capabilities = capabilities
    }

    public var executableURL: URL { URL(fileURLWithPath: executablePath) }
    public var version: BrewVersion? { capabilities.version }
    public var versionText: String { capabilities.summary }

    public var binPaths: [String] {
        var paths = ["\(prefix)/bin", "\(prefix)/sbin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        if let jq = capabilities.jqPath {
            paths.append((jq as NSString).deletingLastPathComponent)
        }
        var seen = Set<String>()
        return paths.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

public enum BrewEnvironmentError: Error, LocalizedError, Sendable {
    case notFound
    case notExecutable(String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "找不到 Homebrew。请安装 Homebrew，或在设置中指定 brew 路径。"
        case .notExecutable(let path):
            return "找到了 \(path)，但它无法运行（可能缺少执行权限或安装已损坏）。请在终端执行 chmod +x \"\(path)\" 后重试，或重新安装 Homebrew。"
        }
    }

    /// UI 用来区分「没装」与「装了但坏了」：后者的下一步是修权限/重装，
    /// 而不是再次安装 Homebrew。
    public var isNotExecutable: Bool {
        if case .notExecutable = self { return true }
        return false
    }
}
