import Foundation

/// Display-only progress stages for the update progress panel. Labels are
/// user-visible; do not rename without syncing `docs/ui-design.md` 文案表.
public enum BrewProgressStage: String, Sendable, Equatable {
    case preparing
    case downloading
    case installing
    case finishing

    public var label: String {
        switch self {
        case .preparing: return "准备中"
        case .downloading: return "下载中"
        case .installing: return "安装中"
        case .finishing: return "清理中"
        }
    }
}

/// A progress signal extracted from one line of brew's human-readable output.
public enum BrewProgressEvent: Sendable, Equatable {
    /// brew began working on a specific package (`==> Upgrading wget`).
    case packageStarted(String)
    case stage(BrewProgressStage)
}

/// Parses `==>` stage markers from brew output into display-only progress
/// events (technical-notes §4.2). Outcomes are NEVER derived from this parser;
/// success/failure is decided by exit codes plus outdated verification.
///
/// Known limitation（需技术验证）: per-package attribution relies on
/// `==> Upgrading/Installing/Reinstalling <name>` lines. The exact format of
/// these lines during a real `brew upgrade` has not been captured on this
/// machine (upgrade mutates state), so consumers must tolerate a run where no
/// `packageStarted` event ever fires and degrade to task-level progress.
public enum BrewProgressParser {
    /// Verbs observed in real Homebrew output, mapped to display stages.
    /// Unknown `==>` verbs return nil so the UI keeps the previous state
    /// instead of guessing a label.
    private static let stageVerbs: [String: BrewProgressStage] = [
        "Auto-updating": .preparing,
        "Reading": .preparing,
        "Refreshing": .preparing,
        "Checking": .preparing,
        "Downloading": .downloading,
        "Fetching": .downloading,
        "Installing": .installing,
        "Upgrading": .installing,
        "Reinstalling": .installing,
        "Pouring": .installing,
        "Moving": .installing,
        "Patching": .installing,
        "Finishing": .finishing,
        "Cleaning": .finishing,
        "Purging": .finishing,
        "Summary": .finishing,
        "Caveats": .finishing
    ]

    /// Verbs that introduce per-package work. `Pouring` is excluded on purpose:
    /// its argument is a bottle filename, not a package name.
    private static let packageStartVerbs: Set<String> = ["Upgrading", "Installing", "Reinstalling"]

    public static func event(forLine line: String) -> BrewProgressEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("==>") else { return nil }
        if let name = packageName(fromLine: trimmed) {
            return .packageStarted(name)
        }
        guard let verb = verb(in: trimmed), let stage = stageVerbs[verb] else { return nil }
        return .stage(stage)
    }

    /// Extracts the package name from a per-package stage line such as
    /// `==> Upgrading wget`. Summary lines (`==> Upgrading 2 outdated
    /// packages`), dependency notes (`==> Installing dependency: foo`) and
    /// lines whose first argument is not a plausible token are rejected so a
    /// parsing miss degrades to generic stage progress instead of advancing
    /// the wrong row.
    public static func packageName(fromLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("==>"),
              let verb = verb(in: trimmed),
              packageStartVerbs.contains(verb) else { return nil }
        var remainder = String(trimmed.dropFirst("==> ".count + verb.count))
            .trimmingCharacters(in: .whitespaces)
        // Reject summary/aggregate lines before touching the name candidate.
        let lowered = remainder.lowercased()
        if lowered.contains("outdated") || lowered.contains("dependenc") || lowered.contains("packages") {
            return nil
        }
        guard let tokens = optionalTokens(remainder) else { return nil }
        // `==> Installing Cask iterm2` / `==> Upgrading Formula wget` carry a
        // kind qualifier before the name.
        var index = 0
        if index < tokens.count, ["cask", "formula"].contains(tokens[index].lowercased()) {
            index += 1
        }
        guard index < tokens.count else { return nil }
        let name = tokens[index].trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        // A bare number or a version-ish token is never a package name.
        if name.isEmpty || name.allSatisfy({ $0.isNumber }) || name.hasPrefix("--") { return nil }
        return String(name)
    }

    private static func optionalTokens(_ text: String) -> [Substring]? {
        let tokens = text.split(separator: " ")
        return tokens.isEmpty ? nil : tokens
    }

    private static func verb(in line: String) -> String? {
        let body = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return body.split(separator: " ").first.map(String.init)
    }
}
