import Foundation

// MARK: - Shared helpers

/// A tolerant list of version strings. brew has emitted both `["1.0"]` and
/// `"1.0"` for `installed_versions` across releases; accept both and never fail
/// the whole snapshot for one odd row.
public struct StringList: Codable, Hashable, Sendable {
    public var values: [String]

    public init(_ values: [String] = []) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let list = try? container.decode([String].self) {
            values = list
        } else if let single = try? container.decode(String.self) {
            values = [single]
        } else {
            values = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

/// Minimal JSON tree used for cask artifacts / depends_on, where brew's shape is
/// loose and we only need to display it, not model every variant.
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var displayText: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return "—"
        case .array(let value): return value.map(\.displayText).joined(separator: ", ")
        case .object(let value):
            return value.keys.sorted().map { "\($0): \(value[$0]?.displayText ?? "—")" }.joined(separator: ", ")
        }
    }
}

// MARK: - info --json=v2

public struct BrewInfoResponse: Codable, Sendable {
    public var formulae: [BrewFormula]
    public var casks: [BrewCask]

    public init(formulae: [BrewFormula] = [], casks: [BrewCask] = []) {
        self.formulae = formulae
        self.casks = casks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formulae = (try? container.decode([BrewFormula].self, forKey: .formulae)) ?? []
        casks = (try? container.decode([BrewCask].self, forKey: .casks)) ?? []
    }
}

public struct BrewFormula: Codable, Sendable, Identifiable {
    public var name: String
    public var fullName: String?
    public var tap: String?
    public var desc: String?
    public var license: String?
    public var homepage: String?
    public var versions: FormulaVersions?
    public var installed: [InstalledKeg]?
    public var dependencies: [String]?
    public var buildDependencies: [String]?
    public var optionalDependencies: [String]?
    public var conflictsWith: [String]?
    public var kegOnly: Bool?
    public var kegOnlyReason: KegOnlyReason?
    public var outdated: Bool?
    public var pinned: Bool?
    public var deprecated: Bool?
    public var disabled: Bool?
    public var deprecationReason: String?
    public var disableReason: String?
    public var caveats: String?
    public var aliases: [String]?
    public var service: JSONValue?

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case tap
        case desc
        case license
        case homepage
        case versions
        case installed
        case dependencies
        case buildDependencies = "build_dependencies"
        case optionalDependencies = "optional_dependencies"
        case conflictsWith = "conflicts_with"
        case kegOnly = "keg_only"
        case kegOnlyReason = "keg_only_reason"
        case outdated
        case pinned
        case deprecated
        case disabled
        case deprecationReason = "deprecation_reason"
        case disableReason = "disable_reason"
        case caveats
        case aliases
        case service
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        fullName = try? container.decodeIfPresent(String.self, forKey: .fullName)
        tap = try? container.decodeIfPresent(String.self, forKey: .tap)
        desc = try? container.decodeIfPresent(String.self, forKey: .desc)
        license = try? container.decodeIfPresent(String.self, forKey: .license)
        homepage = try? container.decodeIfPresent(String.self, forKey: .homepage)
        versions = try? container.decodeIfPresent(FormulaVersions.self, forKey: .versions)
        installed = try? container.decodeIfPresent([InstalledKeg].self, forKey: .installed)
        dependencies = try? container.decodeIfPresent([String].self, forKey: .dependencies)
        buildDependencies = try? container.decodeIfPresent([String].self, forKey: .buildDependencies)
        optionalDependencies = try? container.decodeIfPresent([String].self, forKey: .optionalDependencies)
        conflictsWith = try? container.decodeIfPresent([String].self, forKey: .conflictsWith)
        kegOnly = try? container.decodeIfPresent(Bool.self, forKey: .kegOnly)
        kegOnlyReason = try? container.decodeIfPresent(KegOnlyReason.self, forKey: .kegOnlyReason)
        outdated = try? container.decodeIfPresent(Bool.self, forKey: .outdated)
        pinned = try? container.decodeIfPresent(Bool.self, forKey: .pinned)
        deprecated = try? container.decodeIfPresent(Bool.self, forKey: .deprecated)
        disabled = try? container.decodeIfPresent(Bool.self, forKey: .disabled)
        deprecationReason = try? container.decodeIfPresent(String.self, forKey: .deprecationReason)
        disableReason = try? container.decodeIfPresent(String.self, forKey: .disableReason)
        caveats = try? container.decodeIfPresent(String.self, forKey: .caveats)
        aliases = try? container.decodeIfPresent([String].self, forKey: .aliases)
        service = try? container.decodeIfPresent(JSONValue.self, forKey: .service)
    }
}

public struct FormulaVersions: Codable, Sendable {
    public var stable: String?
    public var head: String?
    public var bottle: Bool?

    public init(stable: String? = nil, head: String? = nil, bottle: Bool? = nil) {
        self.stable = stable
        self.head = head
        self.bottle = bottle
    }
}

public struct InstalledKeg: Codable, Sendable {
    public var version: String
    public var time: Int?
    public var installedOnRequest: Bool?
    public var builtAsBottle: Bool?
    public var pouredFromBottle: Bool?
    public var runtimeDependencies: [RuntimeDependency]?

    enum CodingKeys: String, CodingKey {
        case version
        case time
        case installedOnRequest = "installed_on_request"
        case builtAsBottle = "built_as_bottle"
        case pouredFromBottle = "poured_from_bottle"
        case runtimeDependencies = "runtime_dependencies"
    }

    public init(
        version: String,
        time: Int? = nil,
        installedOnRequest: Bool? = nil,
        runtimeDependencies: [RuntimeDependency]? = nil
    ) {
        self.version = version
        self.time = time
        self.installedOnRequest = installedOnRequest
        self.runtimeDependencies = runtimeDependencies
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decode(String.self, forKey: .version)) ?? "—"
        time = try? container.decodeIfPresent(Int.self, forKey: .time)
        installedOnRequest = try? container.decodeIfPresent(Bool.self, forKey: .installedOnRequest)
        builtAsBottle = try? container.decodeIfPresent(Bool.self, forKey: .builtAsBottle)
        pouredFromBottle = try? container.decodeIfPresent(Bool.self, forKey: .pouredFromBottle)
        runtimeDependencies = try? container.decodeIfPresent([RuntimeDependency].self, forKey: .runtimeDependencies)
    }
}

public struct RuntimeDependency: Codable, Sendable, Hashable {
    public var fullName: String
    public var version: String?
    public var pkgVersion: String?
    public var declaredDirectly: Bool?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case version
        case pkgVersion = "pkg_version"
        case declaredDirectly = "declared_directly"
    }

    public init(fullName: String, version: String? = nil, pkgVersion: String? = nil, declaredDirectly: Bool? = nil) {
        self.fullName = fullName
        self.version = version
        self.pkgVersion = pkgVersion
        self.declaredDirectly = declaredDirectly
    }
}

public struct KegOnlyReason: Codable, Sendable, Hashable {
    public var reason: String?
    public var explanation: String?
}

public struct BrewCask: Codable, Sendable, Identifiable {
    public var token: String
    public var fullToken: String?
    public var names: [String]?
    public var desc: String?
    public var version: String?
    public var installed: String?
    public var installedTime: Int?
    public var outdated: Bool?
    public var pinned: Bool?
    public var tap: String?
    public var homepage: String?
    public var url: String?
    public var caveats: String?
    public var autoUpdates: Bool?
    public var deprecated: Bool?
    public var disabled: Bool?
    public var artifacts: [JSONValue]?
    public var dependsOn: JSONValue?

    public var id: String { token }

    enum CodingKeys: String, CodingKey {
        case token
        case fullToken = "full_token"
        case names = "name"
        case desc
        case version
        case installed
        case installedTime = "installed_time"
        case outdated
        case pinned
        case tap
        case homepage
        case url
        case caveats
        case autoUpdates = "auto_updates"
        case deprecated
        case disabled
        case artifacts
        case dependsOn = "depends_on"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = (try? container.decode(String.self, forKey: .token)) ?? ""
        fullToken = try? container.decodeIfPresent(String.self, forKey: .fullToken)
        names = try? container.decodeIfPresent([String].self, forKey: .names)
        desc = try? container.decodeIfPresent(String.self, forKey: .desc)
        version = try? container.decodeIfPresent(String.self, forKey: .version)
        installed = try? container.decodeIfPresent(String.self, forKey: .installed)
        installedTime = try? container.decodeIfPresent(Int.self, forKey: .installedTime)
        outdated = try? container.decodeIfPresent(Bool.self, forKey: .outdated)
        pinned = try? container.decodeIfPresent(Bool.self, forKey: .pinned)
        tap = try? container.decodeIfPresent(String.self, forKey: .tap)
        homepage = try? container.decodeIfPresent(String.self, forKey: .homepage)
        url = try? container.decodeIfPresent(String.self, forKey: .url)
        caveats = try? container.decodeIfPresent(String.self, forKey: .caveats)
        autoUpdates = try? container.decodeIfPresent(Bool.self, forKey: .autoUpdates)
        deprecated = try? container.decodeIfPresent(Bool.self, forKey: .deprecated)
        disabled = try? container.decodeIfPresent(Bool.self, forKey: .disabled)
        artifacts = try? container.decodeIfPresent([JSONValue].self, forKey: .artifacts)
        dependsOn = try? container.decodeIfPresent(JSONValue.self, forKey: .dependsOn)
    }

    public init(token: String, names: [String]? = nil, desc: String? = nil, version: String? = nil) {
        self.token = token
        self.names = names
        self.desc = desc
        self.version = version
    }
}

// MARK: - outdated --json=v2

public struct BrewOutdatedResponse: Codable, Sendable {
    public var formulae: [OutdatedFormula]
    public var casks: [OutdatedCask]

    public init(formulae: [OutdatedFormula] = [], casks: [OutdatedCask] = []) {
        self.formulae = formulae
        self.casks = casks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formulae = (try? container.decode([OutdatedFormula].self, forKey: .formulae)) ?? []
        casks = (try? container.decode([OutdatedCask].self, forKey: .casks)) ?? []
    }
}

public struct OutdatedFormula: Codable, Sendable, Identifiable {
    public var name: String
    public var installedVersions: StringList
    public var currentVersion: String?
    public var pinned: Bool?
    public var pinnedVersion: String?

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case installedVersions = "installed_versions"
        case currentVersion = "current_version"
        case pinned
        case pinnedVersion = "pinned_version"
    }

    public init(
        name: String,
        installedVersions: [String] = [],
        currentVersion: String? = nil,
        pinned: Bool? = nil,
        pinnedVersion: String? = nil
    ) {
        self.name = name
        self.installedVersions = StringList(installedVersions)
        self.currentVersion = currentVersion
        self.pinned = pinned
        self.pinnedVersion = pinnedVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        installedVersions = (try? container.decode(StringList.self, forKey: .installedVersions)) ?? StringList()
        currentVersion = try? container.decodeIfPresent(String.self, forKey: .currentVersion)
        pinned = try? container.decodeIfPresent(Bool.self, forKey: .pinned)
        pinnedVersion = try? container.decodeIfPresent(String.self, forKey: .pinnedVersion)
    }
}

public struct OutdatedCask: Codable, Sendable, Identifiable {
    public var token: String
    public var name: String?
    public var installedVersions: StringList
    public var currentVersion: String?
    public var pinned: Bool?

    public var id: String { token }

    enum CodingKeys: String, CodingKey {
        case token
        case name
        case installedVersions = "installed_versions"
        case currentVersion = "current_version"
        case pinned
    }

    public init(
        token: String,
        name: String? = nil,
        installedVersions: [String] = [],
        currentVersion: String? = nil,
        pinned: Bool? = nil
    ) {
        self.token = token
        self.name = name
        self.installedVersions = StringList(installedVersions)
        self.currentVersion = currentVersion
        self.pinned = pinned
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = (try? container.decode(String.self, forKey: .token)) ?? ""
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        installedVersions = (try? container.decode(StringList.self, forKey: .installedVersions)) ?? StringList()
        currentVersion = try? container.decodeIfPresent(String.self, forKey: .currentVersion)
        pinned = try? container.decodeIfPresent(Bool.self, forKey: .pinned)
    }
}

// MARK: - list --versions --json

public struct BrewListVersionsResponse: Codable, Sendable {
    public var formulae: [ListedFormula]

    public init(formulae: [ListedFormula] = []) {
        self.formulae = formulae
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formulae = (try? container.decode([ListedFormula].self, forKey: .formulae)) ?? []
    }
}

public struct ListedFormula: Codable, Sendable {
    public var name: String
    public var versions: [String]
    public var linkedVersion: String?
    public var optlinkedVersion: String?
    public var pinnedVersion: String?

    enum CodingKeys: String, CodingKey {
        case name
        case versions
        case linkedVersion = "linked_version"
        case optlinkedVersion = "optlinked_version"
        case pinnedVersion = "pinned_version"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        versions = (try? container.decodeIfPresent([String].self, forKey: .versions)) ?? []
        linkedVersion = try? container.decodeIfPresent(String.self, forKey: .linkedVersion)
        optlinkedVersion = try? container.decodeIfPresent(String.self, forKey: .optlinkedVersion)
        pinnedVersion = try? container.decodeIfPresent(String.self, forKey: .pinnedVersion)
    }
}

// MARK: - services list --json

public struct BrewService: Codable, Sendable, Identifiable, Hashable {
    public var name: String
    public var status: String?
    public var user: String?
    public var file: String?
    public var exitCode: Int?

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case status
        case user
        case file
        case exitCode = "exit_code"
    }

    public init(name: String, status: String? = nil, user: String? = nil, file: String? = nil, exitCode: Int? = nil) {
        self.name = name
        self.status = status
        self.user = user
        self.file = file
        self.exitCode = exitCode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        user = try? container.decodeIfPresent(String.self, forKey: .user)
        file = try? container.decodeIfPresent(String.self, forKey: .file)
        exitCode = try? container.decodeIfPresent(Int.self, forKey: .exitCode)
    }

    public var lifecycle: ServiceLifecycle {
        switch (status ?? "").lowercased() {
        case "started", "running": return .running
        case "stopped", "none": return .stopped
        case "error": return .error
        case "scheduled": return .scheduled
        default: return .unknown
        }
    }
}

public enum ServiceLifecycle: String, Sendable, CaseIterable {
    case running, stopped, error, scheduled, unknown

    public var label: String {
        switch self {
        case .running: return "运行中"
        case .stopped: return "已停止"
        case .error: return "异常"
        case .scheduled: return "已计划"
        case .unknown: return "未知"
        }
    }
}

// MARK: - vulns --json

public struct VulnReport: Codable, Sendable {
    public var findings: [VulnerabilityFinding]
    public var skippedFormulae: [String]
    public var checked: Int
    public var complete: Bool
    public var outdatedWithoutSBOM: [String]
    public var unscannedFormulae: [String: String]
    public var scannedAt: Date
    public var duration: TimeInterval
    public var exitCode: Int32
    public var stderrNote: String?

    public init(
        findings: [VulnerabilityFinding] = [],
        skippedFormulae: [String] = [],
        checked: Int = 0,
        complete: Bool = false,
        outdatedWithoutSBOM: [String] = [],
        unscannedFormulae: [String: String] = [:],
        scannedAt: Date = Date(),
        duration: TimeInterval = 0,
        exitCode: Int32 = 0,
        stderrNote: String? = nil
    ) {
        self.findings = findings
        self.skippedFormulae = skippedFormulae
        self.checked = checked
        self.complete = complete
        self.outdatedWithoutSBOM = outdatedWithoutSBOM
        self.unscannedFormulae = unscannedFormulae
        self.scannedAt = scannedAt
        self.duration = duration
        self.exitCode = exitCode
        self.stderrNote = stderrNote
    }

    enum CodingKeys: String, CodingKey {
        case findings
        case skippedFormulae = "skipped_formulae"
        case checked
        case complete
        case outdatedWithoutSBOM = "outdated_without_sbom"
        case unscannedFormulae = "unscanned_formulae"
        case scannedAt
        case duration
        case exitCode
        case stderrNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        findings = (try? container.decode([VulnerabilityFinding].self, forKey: .findings)) ?? []
        skippedFormulae = (try? container.decodeIfPresent([String].self, forKey: .skippedFormulae)) ?? []
        checked = (try? container.decodeIfPresent(Int.self, forKey: .checked)) ?? 0
        complete = (try? container.decodeIfPresent(Bool.self, forKey: .complete)) ?? false
        outdatedWithoutSBOM = (try? container.decodeIfPresent([String].self, forKey: .outdatedWithoutSBOM)) ?? []
        unscannedFormulae = (try? container.decodeIfPresent([String: String].self, forKey: .unscannedFormulae)) ?? [:]
        scannedAt = (try? container.decodeIfPresent(Date.self, forKey: .scannedAt)) ?? Date()
        duration = (try? container.decodeIfPresent(TimeInterval.self, forKey: .duration)) ?? 0
        exitCode = (try? container.decodeIfPresent(Int32.self, forKey: .exitCode)) ?? 0
        stderrNote = try? container.decodeIfPresent(String.self, forKey: .stderrNote)
    }

    /// Packages with at least one finding, keyed by formula name.
    public var findingsByFormula: [String: [VulnerabilityFinding]] {
        Dictionary(grouping: findings, by: \.formula)
    }

    public var affectedFormulaCount: Int {
        Set(findings.map(\.formula)).count
    }

    public var totalVulnerabilityCount: Int {
        findings.reduce(0) { $0 + $1.vulnerabilities.count }
    }

    public var severityCounts: [VulnSeverity: Int] {
        var counts: [VulnSeverity: Int] = [:]
        for finding in findings {
            for vulnerability in finding.vulnerabilities {
                counts[vulnerability.severity, default: 0] += 1
            }
        }
        return counts
    }

    public var fixableFindingCount: Int {
        findings.filter { $0.vulnerabilities.contains { !$0.fixedVersions.isEmpty } }.count
    }
}

public struct VulnerabilityFinding: Codable, Sendable, Identifiable, Hashable {
    public var formula: String
    public var version: String?
    public var tag: String?
    public var repoURL: String?
    public var vulnerabilities: [Vulnerability]
    public var patched: [String]?

    public var id: String { formula }

    enum CodingKeys: String, CodingKey {
        case formula
        case version
        case tag
        case repoURL = "repo_url"
        case vulnerabilities
        case patched
    }

    public init(
        formula: String,
        version: String? = nil,
        tag: String? = nil,
        repoURL: String? = nil,
        vulnerabilities: [Vulnerability] = [],
        patched: [String]? = nil
    ) {
        self.formula = formula
        self.version = version
        self.tag = tag
        self.repoURL = repoURL
        self.vulnerabilities = vulnerabilities
        self.patched = patched
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formula = (try? container.decode(String.self, forKey: .formula)) ?? ""
        version = try? container.decodeIfPresent(String.self, forKey: .version)
        tag = try? container.decodeIfPresent(String.self, forKey: .tag)
        repoURL = try? container.decodeIfPresent(String.self, forKey: .repoURL)
        vulnerabilities = (try? container.decodeIfPresent([Vulnerability].self, forKey: .vulnerabilities)) ?? []
        patched = try? container.decodeIfPresent([String].self, forKey: .patched)
    }

    public var worstSeverity: VulnSeverity {
        vulnerabilities.map(\.severity).max() ?? .unknown
    }

    public var hasFix: Bool {
        vulnerabilities.contains { !$0.fixedVersions.isEmpty }
    }
}

public struct Vulnerability: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var severity: VulnSeverity
    public var summary: String?
    public var aliases: [String]
    public var fixedVersions: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case severity
        case summary
        case aliases
        case fixedVersions = "fixed_versions"
    }

    public init(
        id: String,
        severity: VulnSeverity = .unknown,
        summary: String? = nil,
        aliases: [String] = [],
        fixedVersions: [String] = []
    ) {
        self.id = id
        self.severity = severity
        self.summary = summary
        self.aliases = aliases
        self.fixedVersions = fixedVersions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        severity = VulnSeverity(rawValue: ((try? container.decodeIfPresent(String.self, forKey: .severity)) ?? "").lowercased()) ?? .unknown
        summary = try? container.decodeIfPresent(String.self, forKey: .summary)
        aliases = (try? container.decodeIfPresent([String].self, forKey: .aliases)) ?? []
        fixedVersions = (try? container.decodeIfPresent([String].self, forKey: .fixedVersions)) ?? []
    }

    public var osvURL: URL? {
        URL(string: "https://osv.dev/vulnerability/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)")
    }
}

public enum VulnSeverity: String, Codable, Sendable, CaseIterable, Comparable {
    case critical, high, medium, low, unknown

    public var rank: Int {
        switch self {
        case .critical: return 4
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .unknown: return 0
        }
    }

    public var label: String {
        switch self {
        case .critical: return "严重"
        case .high: return "高危"
        case .medium: return "中危"
        case .low: return "低危"
        case .unknown: return "未知"
        }
    }

    public static func < (lhs: VulnSeverity, rhs: VulnSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}
