import Foundation

// MARK: - Search

public struct BrewSearchResult: Identifiable, Hashable, Sendable {
    public var name: String
    public var summary: String
    public var kind: PackageSnapshot.Kind

    public var id: String { "\(kind.rawValue):\(name)" }

    public init(name: String, summary: String = "", kind: PackageSnapshot.Kind) {
        self.name = name
        self.summary = summary
        self.kind = kind
    }
}

// MARK: - Cleanup

public struct CleanupPreview: Sendable, Hashable {
    public struct Removal: Sendable, Hashable {
        public var path: String
        public var detail: String?
    }

    public var removals: [Removal]
    public var reclaimText: String?
    public var warnings: [String]
    public var raw: String

    public var isEmpty: Bool { removals.isEmpty && reclaimText == nil }
}

// MARK: - Doctor

public struct DoctorIssue: Identifiable, Hashable, Sendable {
    public enum Level: String, Sendable {
        case warning
        case error
    }

    public var id: String { title + detail.prefix(64) }
    public var title: String
    public var detail: String
    public var level: Level
    public var isPermissionIssue: Bool
    public var suggestedCommands: [String]
}

public struct DoctorReport: Sendable, Hashable {
    public var issues: [DoctorIssue]
    public var raw: String
    public var intro: String
}

// MARK: - Missing dependencies

public struct MissingEntry: Identifiable, Hashable, Sendable {
    public var id: String { package }
    public var package: String
    public var missing: [String]
}

public struct MissingReport: Sendable, Hashable {
    public var entries: [MissingEntry]
    public var raw: String
    public var hasIssues: Bool { !entries.isEmpty }
}

// MARK: - Autoremove

public struct AutoremovePreview: Sendable, Hashable {
    public var packages: [String]
    public var raw: String
}

public enum BrewTextParser {
    // MARK: search

    public static func parseSearch(_ output: String, defaultKind: PackageSnapshot.Kind = .formula) -> [BrewSearchResult] {
        var results: [BrewSearchResult] = []
        var sectionKind: PackageSnapshot.Kind = defaultKind
        var seen = Set<String>()

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("==>") {
                let header = line.replacingOccurrences(of: "==>", with: "").trimmingCharacters(in: .whitespaces).lowercased()
                if header.hasPrefix("cask") { sectionKind = .cask }
                else if header.hasPrefix("formula") { sectionKind = .formula }
                continue
            }
            if line.hasPrefix("Warning:") || line.hasPrefix("Error:") || line.hasPrefix("Please note") {
                continue
            }

            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let name = parts.first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? line
            guard BrewArgumentValidator.isValidPackageToken(name) else { continue }
            let summary = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
            let key = "\(sectionKind.rawValue):\(name)"
            guard seen.insert(key).inserted else { continue }
            results.append(BrewSearchResult(name: name, summary: summary, kind: sectionKind))
        }
        return results
    }

    // MARK: cleanup

    public static func parseCleanupPreview(_ output: String) -> CleanupPreview {
        var removals: [CleanupPreview.Removal] = []
        var reclaim: String?
        var warnings: [String] = []

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Would remove:") || line.hasPrefix("Would remove ") {
                let payload = line.replacingOccurrences(of: "Would remove:", with: "")
                    .replacingOccurrences(of: "Would remove", with: "")
                    .trimmingCharacters(in: .whitespaces)
                let path = payload.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespaces) ?? payload
                let detail = payload.contains("(") ? payload.components(separatedBy: " (").dropFirst().joined(separator: " (") : nil
                removals.append(.init(path: path, detail: detail?.replacingOccurrences(of: ")", with: "")))
            } else if line.contains("This operation would free") {
                if let range = line.range(of: "free ") {
                    reclaim = String(line[range.upperBound...])
                        .replacingOccurrences(of: " of disk space.", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if reclaim?.hasSuffix(".") == true { reclaim?.removeLast() }
                }
            } else if line.hasPrefix("Warning: Skipping") {
                warnings.append(line.replacingOccurrences(of: "Warning: ", with: ""))
            } else if line.hasPrefix("Warning:") {
                warnings.append(line.replacingOccurrences(of: "Warning: ", with: ""))
            }
        }
        return CleanupPreview(removals: removals, reclaimText: reclaim, warnings: warnings, raw: output)
    }

    // MARK: doctor

    public static func parseDoctor(_ output: String) -> DoctorReport {
        let lines = output.components(separatedBy: .newlines)
        var issues: [DoctorIssue] = []
        var introLines: [String] = []
        var currentTitle: String?
        var currentLevel: DoctorIssue.Level = .warning
        var currentDetail: [String] = []
        var sawHeader = false

        func flush() {
            guard let title = currentTitle else { return }
            let detail = currentDetail.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            issues.append(makeDoctorIssue(title: title, detail: detail, level: currentLevel))
            currentTitle = nil
            currentDetail = []
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Warning:") || trimmed.hasPrefix("Error:") {
                flush()
                sawHeader = true
                let level: DoctorIssue.Level = trimmed.hasPrefix("Error:") ? .error : .warning
                let title = trimmed
                    .replacingOccurrences(of: "Warning:", with: "")
                    .replacingOccurrences(of: "Error:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentTitle = title
                currentLevel = level
            } else if sawHeader {
                currentDetail.append(rawLine)
            } else {
                introLines.append(rawLine)
            }
        }
        flush()

        return DoctorReport(issues: issues, raw: output, intro: introLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func makeDoctorIssue(title: String, detail: String, level: DoctorIssue.Level) -> DoctorIssue {
        let lowered = (title + "\n" + detail).lowercased()
        let permissionMarkers = ["not writable", "permission denied", "operation not permitted", "read-only file system", "can't be written", "cannot be written", "not writable by"]
        let isPermission = permissionMarkers.contains { lowered.contains($0) }
        let commands = extractCommands(from: detail)
        return DoctorIssue(
            title: title,
            detail: detail,
            level: level,
            isPermissionIssue: isPermission,
            suggestedCommands: commands
        )
    }

    public static func extractCommands(from text: String) -> [String] {
        var commands: [String] = []
        let patterns = [
            #"`(brew [^`]+)`"#,
            #"(?m)^\s*(brew [A-Za-z0-9 @+._/=<>:-]+)\s*$"#,
            #"(?m)^\s*Run `(brew [^`]+)`"#,
            #"(?m)^\s*Please run `(brew [^`]+)`"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: nsRange) where match.numberOfRanges > 1 {
                if let range = Range(match.range(at: 1), in: text) {
                    let command = String(text[range]).trimmingCharacters(in: .whitespaces)
                    if !commands.contains(command) { commands.append(command) }
                }
            }
        }
        // The `brew trust --formula …` blocks are printed as plain lines with two
        // leading spaces; the generic regex above catches them.
        return commands
    }

    // MARK: missing

    public static func parseMissing(_ output: String) -> MissingReport {
        var entries: [MissingEntry] = []
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("Warning:") || line.hasPrefix("Error:") { continue }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let package = parts.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? line
            let missingText = parts.count > 1 ? String(parts[1]) : ""
            let missing = missingText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !package.isEmpty {
                entries.append(MissingEntry(package: package, missing: missing))
            }
        }
        return MissingReport(entries: entries, raw: output)
    }

    // MARK: autoremove

    public static func parseAutoremovePreview(_ output: String) -> AutoremovePreview {
        var packages: [String] = []
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let lowered = line.lowercased()
            if lowered.hasPrefix("would autoremove") || lowered.hasPrefix("would remove") {
                let payload = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                let name = payload.components(separatedBy: " (").first?.trimmingCharacters(in: .whitespaces) ?? payload
                if !name.isEmpty, !packages.contains(name) { packages.append(name) }
            }
        }
        return AutoremovePreview(packages: packages, raw: output)
    }

    // MARK: list

    public static func parseLineList(_ output: String) -> [String] {
        output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") && !$0.hasPrefix("Warning:") && !$0.hasPrefix("Error:") }
    }
}
