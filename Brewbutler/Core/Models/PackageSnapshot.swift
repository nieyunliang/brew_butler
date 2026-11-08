import Foundation

/// The UI-facing, version-agnostic package record. Built from `info --json=v2`
/// and enriched with `outdated` and `vulns` results. Everything is optional-safe
/// so a brew schema change degrades to "—" instead of a crash.
public struct PackageSnapshot: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable, CaseIterable, Hashable {
        case formula
        case cask

        public var label: String { rawValue }
        public var pluralLabel: String { rawValue == "formula" ? "formula" : "cask" }
    }

    public let id: String
    public var name: String
    public var fullName: String
    public var kind: Kind
    public var tap: String?
    public var desc: String?
    public var license: String?
    public var homepage: String?
    public var installedVersion: String?
    public var stableVersion: String?
    public var installedAt: Date?
    public var installedOnRequest: Bool?
    public var kegOnly: Bool
    public var kegOnlyReason: String?
    public var outdated: Bool
    public var pinned: Bool
    public var deprecated: Bool
    public var disabled: Bool
    public var statusNote: String?
    public var caveats: String?
    public var dependencies: [String]
    public var runtimeDependencies: [RuntimeDependency]
    public var conflictsWith: [String]
    public var hasService: Bool
    public var autoUpdates: Bool?
    public var artifacts: [JSONValue]
    public var diskUsageBytes: Int64?
    public var vulnerabilityFinding: VulnerabilityFinding?

    public init(
        id: String,
        name: String,
        fullName: String,
        kind: Kind,
        tap: String? = nil,
        desc: String? = nil,
        license: String? = nil,
        homepage: String? = nil,
        installedVersion: String? = nil,
        stableVersion: String? = nil,
        installedAt: Date? = nil,
        installedOnRequest: Bool? = nil,
        kegOnly: Bool = false,
        kegOnlyReason: String? = nil,
        outdated: Bool = false,
        pinned: Bool = false,
        deprecated: Bool = false,
        disabled: Bool = false,
        statusNote: String? = nil,
        caveats: String? = nil,
        dependencies: [String] = [],
        runtimeDependencies: [RuntimeDependency] = [],
        conflictsWith: [String] = [],
        hasService: Bool = false,
        autoUpdates: Bool? = nil,
        artifacts: [JSONValue] = [],
        diskUsageBytes: Int64? = nil,
        vulnerabilityFinding: VulnerabilityFinding? = nil
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.kind = kind
        self.tap = tap
        self.desc = desc
        self.license = license
        self.homepage = homepage
        self.installedVersion = installedVersion
        self.stableVersion = stableVersion
        self.installedAt = installedAt
        self.installedOnRequest = installedOnRequest
        self.kegOnly = kegOnly
        self.kegOnlyReason = kegOnlyReason
        self.outdated = outdated
        self.pinned = pinned
        self.deprecated = deprecated
        self.disabled = disabled
        self.statusNote = statusNote
        self.caveats = caveats
        self.dependencies = dependencies
        self.runtimeDependencies = runtimeDependencies
        self.conflictsWith = conflictsWith
        self.hasService = hasService
        self.autoUpdates = autoUpdates
        self.artifacts = artifacts
        self.diskUsageBytes = diskUsageBytes
        self.vulnerabilityFinding = vulnerabilityFinding
    }

    public var displayName: String {
        if let first = name.split(separator: "/").last, kind == .formula {
            return String(first)
        }
        return name
    }

    public var displayVersion: String { installedVersion ?? stableVersion ?? "—" }

    /// A package can only be shown as "有已知漏洞" when the scan actually covered it.
    public var vulnerabilitySeverity: VulnSeverity? { vulnerabilityFinding?.worstSeverity }

    public var hasVulnerability: Bool { vulnerabilityFinding != nil }

    public var isDeprecatedOrDisabled: Bool { deprecated || disabled }

    public var allDependencies: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in dependencies + runtimeDependencies.map(\.fullName) where seen.insert(name).inserted {
            result.append(name)
        }
        return result
    }

    public var installCommand: String {
        switch kind {
        case .formula: return "brew install \(name)"
        case .cask: return "brew install --cask \(name)"
        }
    }

    public var uninstallCommand: String {
        switch kind {
        case .formula: return "brew uninstall --formula \(name)"
        case .cask: return "brew uninstall --cask \(name)"
        }
    }
}

public struct OutdatedEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var kind: PackageSnapshot.Kind
    public var installedVersions: [String]
    public var currentVersion: String
    public var pinned: Bool
    public var severity: VulnSeverity?
    public var finding: VulnerabilityFinding?

    public init(
        id: String,
        name: String,
        kind: PackageSnapshot.Kind,
        installedVersions: [String] = [],
        currentVersion: String,
        pinned: Bool = false,
        severity: VulnSeverity? = nil,
        finding: VulnerabilityFinding? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.installedVersions = installedVersions
        self.currentVersion = currentVersion
        self.pinned = pinned
        self.severity = severity
        self.finding = finding
    }

    public var installedText: String { installedVersions.joined(separator: ", ") }
    public var isSecurityUpdate: Bool { finding != nil }
}

public struct PackageIndex: Sendable {
    public var packages: [PackageSnapshot]
    public var reverseDependencies: [String: [String]]
    public var outdated: [OutdatedEntry]
    public var vulnReport: VulnReport?
    public var fetchedAt: Date

    public init(
        packages: [PackageSnapshot],
        reverseDependencies: [String: [String]] = [:],
        outdated: [OutdatedEntry] = [],
        vulnReport: VulnReport? = nil,
        fetchedAt: Date = Date()
    ) {
        self.packages = packages
        self.reverseDependencies = reverseDependencies
        self.outdated = outdated
        self.vulnReport = vulnReport
        self.fetchedAt = fetchedAt
    }

    public var formulae: [PackageSnapshot] { packages.filter { $0.kind == .formula } }
    public var casks: [PackageSnapshot] { packages.filter { $0.kind == .cask } }
    public var securityUpdates: [OutdatedEntry] { outdated.filter(\.isSecurityUpdate) }

    /// Resolves both short names and tap-qualified full names (outdated rows use
    /// full_name, package rows use the short name, so UpdatesView detail lookup
    /// must accept either).
    public func package(named name: String, kind: PackageSnapshot.Kind? = nil) -> PackageSnapshot? {
        if let kind {
            return packages.first { ($0.name == name || $0.fullName == name) && $0.kind == kind }
        }
        return packages.first { $0.name == name || $0.fullName == name }
    }

    public func dependents(of name: String) -> [String] {
        reverseDependencies[name] ?? []
    }

    /// Deterministic hash of the installed snapshot; the vuln cache is keyed by it.
    public var snapshotHash: String {
        let seed = packages
            .map { "\($0.kind.rawValue):\($0.name)@\($0.installedVersion ?? "-")" }
            .sorted()
            .joined(separator: "|")
        return StableHash.fnv1a(seed)
    }

    public static func build(
        info: BrewInfoResponse,
        outdated: BrewOutdatedResponse?,
        vulnReport: VulnReport?,
        listVersions: BrewListVersionsResponse? = nil,
        fetchedAt: Date = Date()
    ) -> PackageIndex {
        // First-wins dictionaries: brew should not emit duplicate rows, but a
        // malformed/duplicated payload must never crash the whole app.
        let outdatedFormulae = Dictionary(
            (outdated?.formulae ?? []).map { ($0.name, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let outdatedCasks = Dictionary(
            (outdated?.casks ?? []).map { ($0.token, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        // `outdated --json=v2` keys formula rows by full_name (e.g. user/tap/foo),
        // while info/list rows may only carry the short name; index both so tap
        // formulae merge instead of silently keeping only info's outdated flag.
        var outdatedFormulaeByShortName: [String: OutdatedFormula] = [:]
        for row in outdated?.formulae ?? [] where !row.name.isEmpty {
            let shortName = row.name.split(separator: "/").last.map(String.init) ?? row.name
            if outdatedFormulaeByShortName[shortName] == nil {
                outdatedFormulaeByShortName[shortName] = row
            }
        }
        let findings = vulnReport?.findingsByFormula ?? [:]

        var packages: [PackageSnapshot] = []

        for formula in info.formulae {
            guard !formula.name.isEmpty else { continue }
            let keg = formula.installed?.first
            let outdatedRow = outdatedFormulae[formula.fullName ?? formula.name]
                ?? outdatedFormulae[formula.name]
                ?? outdatedFormulaeByShortName[formula.name]
            let isOutdated = formula.outdated == true || outdatedRow != nil
            packages.append(
                PackageSnapshot(
                    id: "formula:\(formula.name)",
                    name: formula.name,
                    fullName: formula.fullName ?? formula.name,
                    kind: .formula,
                    tap: formula.tap,
                    desc: formula.desc,
                    license: formula.license,
                    homepage: formula.homepage,
                    installedVersion: keg?.version,
                    stableVersion: formula.versions?.stable,
                    installedAt: keg?.time.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    installedOnRequest: keg?.installedOnRequest,
                    kegOnly: formula.kegOnly == true,
                    kegOnlyReason: formula.kegOnlyReason?.explanation ?? formula.kegOnlyReason?.reason,
                    outdated: isOutdated,
                    pinned: formula.pinned == true || outdatedRow?.pinned == true,
                    deprecated: formula.deprecated == true,
                    disabled: formula.disabled == true,
                    statusNote: formula.disableReason ?? formula.deprecationReason,
                    caveats: formula.caveats,
                    dependencies: formula.dependencies ?? [],
                    runtimeDependencies: keg?.runtimeDependencies ?? [],
                    conflictsWith: formula.conflictsWith ?? [],
                    hasService: formula.service != nil,
                    vulnerabilityFinding: findings[formula.name]?.first
                )
            )
        }

        // `list --versions` can surface local kegs that `info` refuses to load
        // (for example formulae from an untrusted tap). Keep them visible with an
        // explicit metadata warning instead of silently losing installed packages.
        if let listVersions {
            let known = Set(packages.map { "\($0.kind.rawValue):\($0.name)" })
            for row in listVersions.formulae where !row.name.isEmpty && !known.contains("formula:\(row.name)") {
                let outdatedRow = outdatedFormulae[row.name] ?? outdatedFormulaeByShortName[row.name]
                packages.append(
                    PackageSnapshot(
                        id: "formula:\(row.name)",
                        name: row.name,
                        fullName: row.name,
                        kind: .formula,
                        installedVersion: row.versions.last,
                        outdated: outdatedRow != nil,
                        pinned: row.pinnedVersion != nil,
                        statusNote: "元数据不可用（可能来自未受信任的 tap）",
                        vulnerabilityFinding: findings[row.name]?.first
                    )
                )
            }
        }

        for cask in info.casks {
            guard !cask.token.isEmpty else { continue }
            let outdatedRow = outdatedCasks[cask.token]
            packages.append(
                PackageSnapshot(
                    id: "cask:\(cask.token)",
                    name: cask.token,
                    fullName: cask.fullToken ?? cask.token,
                    kind: .cask,
                    tap: cask.tap,
                    desc: cask.desc,
                    license: nil,
                    homepage: cask.homepage,
                    installedVersion: cask.installed,
                    stableVersion: cask.version,
                    installedAt: cask.installedTime.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    installedOnRequest: true,
                    kegOnly: false,
                    kegOnlyReason: nil,
                    outdated: cask.outdated == true || outdatedRow != nil,
                    pinned: cask.pinned == true || outdatedRow?.pinned == true,
                    deprecated: cask.deprecated == true,
                    disabled: cask.disabled == true,
                    caveats: cask.caveats,
                    dependencies: [],
                    runtimeDependencies: [],
                    conflictsWith: [],
                    hasService: false,
                    autoUpdates: cask.autoUpdates,
                    artifacts: cask.artifacts ?? []
                )
            )
        }

        packages.sort { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        let reverse = Self.computeReverseDependencies(packages)

        var entries: [OutdatedEntry] = []
        var seenEntryIDs = Set<String>()
        for row in outdated?.formulae ?? [] where !row.name.isEmpty {
            let id = "formula:\(row.name)"
            guard seenEntryIDs.insert(id).inserted else { continue }
            let finding = findings[row.name]?.first
            entries.append(
                OutdatedEntry(
                    id: id,
                    name: row.name,
                    kind: .formula,
                    installedVersions: row.installedVersions.values,
                    currentVersion: row.currentVersion ?? "—",
                    pinned: row.pinned == true,
                    severity: finding?.worstSeverity,
                    finding: finding
                )
            )
        }
        for row in outdated?.casks ?? [] where !row.token.isEmpty {
            let id = "cask:\(row.token)"
            guard seenEntryIDs.insert(id).inserted else { continue }
            entries.append(
                OutdatedEntry(
                    id: id,
                    name: row.token,
                    kind: .cask,
                    installedVersions: row.installedVersions.values,
                    currentVersion: row.currentVersion ?? "—",
                    pinned: row.pinned == true
                )
            )
        }
        entries.sort { lhs, rhs in
            if lhs.isSecurityUpdate != rhs.isSecurityUpdate { return lhs.isSecurityUpdate }
            let lhsSev = lhs.severity?.rank ?? -1
            let rhsSev = rhs.severity?.rank ?? -1
            if lhsSev != rhsSev { return lhsSev > rhsSev }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        return PackageIndex(
            packages: packages,
            reverseDependencies: reverse,
            outdated: entries,
            vulnReport: vulnReport,
            fetchedAt: fetchedAt
        )
    }

    public static func computeReverseDependencies(_ packages: [PackageSnapshot]) -> [String: [String]] {
        var reverse: [String: Set<String>] = [:]
        for package in packages where package.kind == .formula {
            for dependency in package.allDependencies {
                reverse[dependency, default: []].insert(package.name)
            }
        }
        return reverse.mapValues { $0.sorted() }
    }
}

public enum StableHash {
    public static func fnv1a(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
