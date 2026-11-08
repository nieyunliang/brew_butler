import Foundation

/// Finds Homebrew without relying on the GUI process PATH. Search order:
/// user override → fixed Apple-silicon/Intel/Linuxbrew paths → login shell.
public struct BrewLocator: Sendable {
    public static let candidatePaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
        "/home/linuxbrew/.linuxbrew/bin/brew"
    ]

    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = BrewProcessRunner()) {
        self.runner = runner
    }

    public func locate(override: String? = nil) async -> Result<BrewInstallation, BrewEnvironmentError> {
        let candidates = candidateCandidates(override: override)
        // 与 notFound 区分：路径存在但不可执行 / 可执行但 --version 失败，都说明
        // 「装了但坏了」，下一步是修权限或重装，而不是重新安装 Homebrew。
        var blockedPath: String?

        for path in candidates {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            guard FileManager.default.isExecutableFile(atPath: path) else {
                blockedPath = blockedPath ?? path
                continue
            }
            if let installation = await verify(path: path) {
                return .success(installation)
            }
            blockedPath = blockedPath ?? path
        }

        if let shellPath = await loginShellBrewPath(), !candidates.contains(shellPath) {
            guard FileManager.default.fileExists(atPath: shellPath) else {
                return blockedPath.map { .failure(.notExecutable($0)) } ?? .failure(.notFound)
            }
            guard FileManager.default.isExecutableFile(atPath: shellPath) else {
                return .failure(.notExecutable(blockedPath ?? shellPath))
            }
            if let installation = await verify(path: shellPath) {
                return .success(installation)
            }
            blockedPath = blockedPath ?? shellPath
        }

        if let blockedPath { return .failure(.notExecutable(blockedPath)) }
        return .failure(.notFound)
    }

    /// Lists every brew binary that exists on this Mac (fixed paths, login-shell
    /// PATH and the user override), including ones that exist but cannot run.
    /// Used by Settings to let the user pick which installation Brewbutler manages.
    public func discoverCandidates(override: String? = nil) async -> [BrewCandidate] {
        var paths = candidateCandidates(override: override)
        if let shellPath = await loginShellBrewPath(), !paths.contains(shellPath) {
            paths.append(shellPath)
        }

        var seen = Set<String>()
        var result: [BrewCandidate] = []
        for path in paths {
            guard seen.insert(path).inserted else { continue }
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let executable = FileManager.default.isExecutableFile(atPath: path)
            var versionText: String?
            if executable,
               let probe = await execute(executable: URL(fileURLWithPath: path), arguments: ["--version"], timeout: 5),
               probe.exitCode == 0 {
                versionText = (probe.stdout + "\n" + probe.stderr)
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty }
            }
            result.append(BrewCandidate(path: path, versionText: versionText, isExecutable: executable))
        }
        return result
    }

    private func candidateCandidates(override: String?) -> [String] {
        var paths: [String] = []
        if let override, !override.isEmpty { paths.append(override) }
        paths.append(contentsOf: Self.candidatePaths)
        return paths
    }

    /// The one deliberate shell launch in the codebase: locating brew requires
    /// the user's rc files, and `/bin/zsh -lc "command -v brew"` is a fixed
    /// string with no user input — the no-shell rule governs brew invocations
    /// (argv arrays via SpawnedProcess), not this fixed probe. zsh is macOS's
    /// default login shell; a bash user's PATH almost always matches anyway.
    private func loginShellBrewPath() async -> String? {
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "command -v brew"],
            environment: {
                var environment = ProcessInfo.processInfo.environment
                environment["HOMEBREW_NO_ENV_HINTS"] = "1"
                return environment
            }(),
            timeout: 3,
            captureMode: .separated
        )
        guard let result = try? await runner.run(request, onEvent: { _ in }) else { return nil }
        let lines = (result.stdout + "\n" + result.stderr)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") }
        // rc-file noise can precede the real answer; brew always lives at an
        // absolute path ending in /brew.
        return lines.last { $0.hasSuffix("/brew") } ?? lines.last
    }

    private func verify(path: String) async -> BrewInstallation? {
        let executable = URL(fileURLWithPath: path)
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }

        let versionResult = await execute(executable: executable, arguments: ["--version"], timeout: 5)
        guard let versionResult, versionResult.exitCode == 0 else { return nil }
        let versionText = (versionResult.stdout + "\n" + versionResult.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard BrewVersion(string: versionText) != nil else { return nil }

        async let prefix = value(executable: executable, argument: "--prefix", fallback: "/opt/homebrew")
        async let cellar = value(executable: executable, argument: "--cellar", fallback: "")
        async let cache = value(executable: executable, argument: "--cache", fallback: "")
        async let repository = value(executable: executable, argument: "--repository", fallback: "")
        let resolvedPrefix = await prefix
        let capabilities = await BrewCapabilityDetector(runner: runner).detect(executable: executable, versionText: versionText)
        let resolvedCellar = await cellar
        let resolvedCache = await cache
        let resolvedRepository = await repository

        return BrewInstallation(
            executablePath: path,
            prefix: resolvedPrefix,
            cellar: resolvedCellar.isEmpty ? "\(resolvedPrefix)/Cellar" : resolvedCellar,
            cache: resolvedCache,
            repository: resolvedRepository,
            capabilities: capabilities
        )
    }

    private func execute(executable: URL, arguments: [String], timeout: TimeInterval) async -> ProcessResult? {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOMEBREW_NO_COLOR"] = "1"
        environment["HOMEBREW_NO_EMOJI"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        let request = ProcessRequest(
            executable: executable,
            arguments: arguments,
            environment: environment,
            timeout: timeout,
            captureMode: .separated
        )
        return try? await runner.run(request, onEvent: { _ in })
    }

    private func value(executable: URL, argument: String, fallback: String) async -> String {
        guard let result = await execute(executable: executable, arguments: [argument], timeout: 5) else { return fallback }
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : text
    }
}

/// One brew binary found on disk. `versionText == nil` while `isExecutable`
/// means the file exists but `brew --version` failed (corrupt or broken install).
public struct BrewCandidate: Identifiable, Hashable, Sendable {
    public var path: String
    public var versionText: String?
    public var isExecutable: Bool

    public var id: String { path }

    public init(path: String, versionText: String? = nil, isExecutable: Bool) {
        self.path = path
        self.versionText = versionText
        self.isExecutable = isExecutable
    }

    public var displayName: String {
        (path as NSString).deletingLastPathComponent
    }
}

public struct BrewCapabilityDetector: Sendable {
    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = BrewProcessRunner()) {
        self.runner = runner
    }

    public func detect(executable: URL, versionText: String) async -> BrewCapabilities {
        async let helpText = helpOutput(executable: executable, arguments: ["--help"])
        async let outdatedHelp = helpOutput(executable: executable, arguments: ["outdated", "--help"])
        async let listHelp = helpOutput(executable: executable, arguments: ["list", "--help"])
        async let upgradeHelp = helpOutput(executable: executable, arguments: ["upgrade", "--help"])
        async let vulnsHelp = helpOutput(executable: executable, arguments: ["vulns", "--help"])
        async let servicesHelp = helpOutput(executable: executable, arguments: ["services", "--help"])

        let mainHelp = await helpText
        let outdatedText = await outdatedHelp
        let listText = await listHelp
        let upgradeText = await upgradeHelp
        let vulnsText = await vulnsHelp
        let servicesText = await servicesHelp

        let commandList = mainHelp.text
        let jqPath = Self.locateJQ(prefixHint: executable.deletingLastPathComponent().deletingLastPathComponent().path)
        let hasVulns = vulnsText.exitCode == 0 && !vulnsText.text.isEmpty
        let hasOutdatedV2 = outdatedText.text.contains("--json") || commandList.contains("outdated")
        let hasListVersions = listText.text.contains("--versions") && listText.text.contains("--json")
        let hasDryRun = upgradeText.text.contains("--dry-run")
        let hasTrust = commandList.contains("trust") || vulnsText.text.contains("untrusted")
        let hasUpdateIfNeeded = commandList.contains("update-if-needed")
        let hasMissing = commandList.contains("missing")
        let hasLog = commandList.contains("log")
        let hasServicesJSON = servicesText.text.contains("--json") || servicesText.text.contains("list")

        var reasons: [String] = []
        if !hasVulns { reasons.append("当前 Homebrew 不支持 brew vulns，漏洞扫描不可用") }
        if !hasOutdatedV2 { reasons.append("outdated --json=v2 不可用，更新列表可能降级") }
        if !hasListVersions || jqPath == nil {
            reasons.append("未检测到 jq 或 list --versions --json，轻量快路径已禁用")
        }
        if !hasDryRun { reasons.append("upgrade --dry-run 不可用，升级预览已禁用") }
        if let version = BrewVersion(string: versionText), version < BrewVersion(major: 7, minor: 0, patch: 0) {
            reasons.append("Homebrew \(version.raw) 低于 v1.0 支持的 7.0，已进入只读模式")
        }

        return BrewCapabilities(
            versionText: versionText.components(separatedBy: .newlines).first ?? versionText,
            vulns: hasVulns,
            outdatedJSONv2: hasOutdatedV2,
            listVersionsJSON: hasListVersions && jqPath != nil,
            jqPath: jqPath,
            dryRun: hasDryRun,
            trust: hasTrust,
            updateIfNeeded: hasUpdateIfNeeded,
            missing: hasMissing,
            log: hasLog,
            servicesJSON: hasServicesJSON,
            checkedAt: Date(),
            degradedReasons: reasons
        )
    }

    private func helpOutput(executable: URL, arguments: [String]) async -> HelpProbe {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOMEBREW_NO_COLOR"] = "1"
        environment["HOMEBREW_NO_EMOJI"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        let request = ProcessRequest(
            executable: executable,
            arguments: arguments,
            environment: environment,
            timeout: 8,
            captureMode: .separated
        )
        guard let result = try? await runner.run(request, onEvent: { _ in }) else {
            return HelpProbe(text: "", exitCode: -1)
        }
        return HelpProbe(text: result.stdout + "\n" + result.stderr, exitCode: result.exitCode)
    }

    static func locateJQ(prefixHint: String?) -> String? {
        var candidates = ["/usr/bin/jq", "/opt/homebrew/bin/jq", "/usr/local/bin/jq"]
        if let prefixHint { candidates.insert("\(prefixHint)/bin/jq", at: 0) }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                candidates.append("\(directory)/jq")
            }
        }
        var seen = Set<String>()
        return candidates.first { candidate in
            guard seen.insert(candidate).inserted else { return false }
            return FileManager.default.isExecutableFile(atPath: candidate)
        }
    }

    private struct HelpProbe: Sendable {
        var text: String
        var exitCode: Int32
    }
}

public extension BrewInstallation {
    var isReadOnly: Bool {
        guard let version else { return true }
        return version < BrewVersion(major: 7, minor: 0, patch: 0)
    }
}
