import Foundation

public enum BrewFailureKind: String, Sendable {
    case cancelled
    case timedOut
    case notFound
    case permissionDenied
    case networkFailure
    case parseFailure
    case brewFailure

    public var label: String {
        switch self {
        case .cancelled: return "已取消"
        case .timedOut: return "超时"
        case .notFound: return "未找到"
        case .permissionDenied: return "权限不足"
        case .networkFailure: return "网络失败"
        case .parseFailure: return "解析失败"
        case .brewFailure: return "命令失败"
        }
    }

    public var suggestion: String {
        switch self {
        case .cancelled:
            return "任务已停止。若操作可能已部分完成，请在终端复查后再重试。"
        case .timedOut:
            return "命令超时。可重试，或在终端中直接运行以观察完整输出。"
        case .notFound:
            return "请确认包名或命令存在；可在发现页搜索，或先运行 brew update。"
        case .permissionDenied:
            return "Homebrew 目录不可写。运行 brew doctor 查看权限问题，并修复 cache / prefix 权限。"
        case .networkFailure:
            return "检查网络或代理设置；离线时可使用上次缓存的结果。"
        case .parseFailure:
            return "brew 输出结构与预期不同。已保留原始输出，可在诊断中查看或复制反馈。"
        case .brewFailure:
            return "查看日志中的 Error 行；可在终端手动执行同一命令以获得完整上下文。"
        }
    }
}

public struct BrewCommandError: Error, LocalizedError, Sendable {
    public var command: String
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var kind: BrewFailureKind
    public var firstErrorLine: String?

    public init(
        command: String,
        exitCode: Int32,
        stdout: String,
        stderr: String,
        kind: BrewFailureKind,
        firstErrorLine: String? = nil
    ) {
        self.command = command
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.kind = kind
        self.firstErrorLine = firstErrorLine
    }

    public var errorDescription: String? {
        let detail = firstErrorLine ?? (kind == .cancelled ? "任务已取消" : "退出码 \(exitCode)")
        return "\(command) 失败：\(detail)"
    }

    public var diagnosticText: String {
        """
        命令：\(command)
        退出码：\(exitCode)
        错误类型：\(kind.label)
        建议：\(kind.suggestion)
        \(firstErrorLine.map { "关键错误行：\($0)" } ?? "")
        """
    }
}

public struct BrewClient: Sendable {
    public let environment: BrewEnvironment
    public let runner: any ProcessRunning

    public init(
        installation: BrewInstallation,
        settings: BrewEnvironmentSettings = BrewEnvironmentSettings(),
        runner: any ProcessRunning = BrewProcessRunner()
    ) {
        self.environment = BrewEnvironment(installation: installation, settings: settings)
        self.runner = runner
    }

    public init(environment: BrewEnvironment, runner: any ProcessRunning = BrewProcessRunner()) {
        self.environment = environment
        self.runner = runner
    }

    public var installation: BrewInstallation { environment.installation }
    public var executable: URL { environment.executable }

    public static let commandName = "brew"

    // MARK: - Raw execution

    private func execute(
        _ arguments: [String],
        scope: BrewEnvironmentScope,
        capture: ProcessRequest.CaptureMode,
        timeout: TimeInterval?,
        onEvent: @escaping @Sendable (ProcessEvent) -> Void
    ) async throws -> ProcessResult {
        let request = ProcessRequest(
            executable: executable,
            arguments: arguments,
            environment: environment.environment(for: scope),
            timeout: timeout,
            captureMode: capture
        )
        do {
            return try await runner.run(request, onEvent: onEvent)
        } catch let error as ProcessError {
            throw error
        } catch {
            throw ProcessError.launchFailed(error.localizedDescription)
        }
    }

    // MARK: - Read-only JSON commands

    public func infoInstalled() async throws -> BrewInfoResponse {
        try await decodeJSON(
            BrewInfoResponse.self,
            arguments: ["info", "--json=v2", "--installed"],
            timeout: 30
        )
    }

    public func info(for name: String, kind: PackageSnapshot.Kind) async throws -> BrewInfoResponse {
        _ = try BrewArgumentValidator.validatePackageToken(name)
        var arguments = ["info", "--json=v2"]
        if kind == .cask { arguments.append("--cask") }
        arguments.append(name)
        return try await decodeJSON(BrewInfoResponse.self, arguments: arguments, timeout: 30)
    }

    public func outdated(greedy: Bool = false) async throws -> BrewOutdatedResponse {
        var arguments = ["outdated", "--json=v2"]
        if greedy { arguments.append("--greedy") }
        return try await decodeJSON(
            BrewOutdatedResponse.self,
            arguments: arguments,
            timeout: 90,
            acceptedExitCodes: [0, 1]
        )
    }

    public func listVersions() async throws -> BrewListVersionsResponse {
        try await decodeJSON(
            BrewListVersionsResponse.self,
            arguments: ["list", "--versions", "--json"],
            timeout: 30
        )
    }

    public func services() async throws -> [BrewService] {
        let result = try await execute(
            ["services", "list", "--json"],
            scope: .readOnly,
            capture: .separated,
            timeout: 15,
            onEvent: { _ in }
        )
        if let services = try? decode([BrewService].self, from: result.stdout) {
            return services
        }
        if result.exitCode != 0 {
            throw makeError(command: "brew services list --json", result: result, kind: .brewFailure)
        }
        return try decodeOrThrow([BrewService].self, from: result.stdout, command: "brew services list --json", result: result)
    }

    /// `brew vulns` exits 1 when findings exist. Success is defined by parseable
    /// JSON, never by the exit code alone.
    public func vulns() async throws -> VulnReport {
        let result = try await execute(
            ["vulns", "--json"],
            scope: .readOnly,
            capture: .separated,
            timeout: 300,
            onEvent: { _ in }
        )
        if result.timedOut {
            throw makeError(command: "brew vulns --json", result: result, kind: .timedOut)
        }
        if result.cancelled {
            throw makeError(command: "brew vulns --json", result: result, kind: .cancelled)
        }
        guard var report = try? decode(VulnReport.self, from: result.stdout) else {
            throw makeError(command: "brew vulns --json", result: result, kind: .parseFailure)
        }
        report.scannedAt = Date()
        report.duration = result.duration
        report.exitCode = result.exitCode
        let note = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        report.stderrNote = note.isEmpty ? nil : note
        return report
    }

    /// Decodes a read-only JSON command with explicit failure semantics:
    /// - timeout / cancellation always win, even when stdout happens to parse;
    /// - a parseable payload is only accepted for exit codes in `acceptedExitCodes`
    ///   (e.g. `outdated` tolerates exit 1 for cache/API warnings);
    /// - any other non-zero exit is classified from the output instead of being
    ///   reported as a parse error.
    private func decodeJSON<T: Decodable>(
        _ type: T.Type,
        arguments: [String],
        timeout: TimeInterval,
        acceptedExitCodes: Set<Int32> = [0]
    ) async throws -> T {
        let result = try await execute(arguments, scope: .readOnly, capture: .separated, timeout: timeout, onEvent: { _ in })
        let command = "brew " + arguments.joined(separator: " ")
        if result.timedOut {
            throw makeError(command: command, result: result, kind: .timedOut)
        }
        if result.cancelled {
            throw makeError(command: command, result: result, kind: .cancelled)
        }
        if let value = try? decode(type, from: result.stdout) {
            guard result.exitCode == 0 || acceptedExitCodes.contains(result.exitCode) else {
                throw makeError(command: command, result: result, kind: Self.classify(result))
            }
            return value
        }
        let kind: BrewFailureKind = result.exitCode != 0 ? Self.classify(result) : .parseFailure
        throw makeError(command: command, result: result, kind: kind)
    }

    private func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8), !trimmed.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "empty output"))
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private func decodeOrThrow<T: Decodable>(
        _ type: T.Type,
        from text: String,
        command: String,
        result: ProcessResult
    ) throws -> T {
        do {
            return try decode(type, from: text)
        } catch {
            throw makeError(command: command, result: result, kind: .parseFailure)
        }
    }

    private func makeError(command: String, result: ProcessResult, kind: BrewFailureKind) -> BrewCommandError {
        let kind = result.timedOut ? BrewFailureKind.timedOut : (result.cancelled ? .cancelled : kind)
        let text = result.stdout + "\n" + result.stderr + "\n" + result.combinedOutput
        let errorLine = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("Error:") || $0.hasPrefix("error:") }
        return BrewCommandError(
            command: command,
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            kind: kind,
            firstErrorLine: errorLine
        )
    }


    /// Size of a directory in bytes, via `/usr/bin/du -sk`. Used for package and
    /// Cellar/cache summaries; callers run this off the main thread and cache it.
    public func directorySize(path: String) async throws -> Int64 {
        guard BrewArgumentValidator.isValidPath(path) else {
            throw BrewArgumentValidator.ValidationError.invalidToken(path)
        }
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/du"),
            arguments: ["-sk", path],
            environment: environment,
            timeout: 120,
            captureMode: .separated
        )
        let result = try await runner.run(request, onEvent: { _ in })
        if result.timedOut || result.cancelled {
            throw BrewCommandError(command: "du -sk \(path)", exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, kind: result.timedOut ? .timedOut : .cancelled)
        }
        guard result.exitCode == 0 else {
            throw BrewCommandError(command: "du -sk \(path)", exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr, kind: .brewFailure)
        }
        let first = result.stdout.split(separator: "\t").first ?? result.stdout.split(separator: " ").first
        let kilobytes = Int64(first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
        return kilobytes * 1024
    }

    public var caskroomPath: String { "\(installation.prefix)/Caskroom" }

    public func packageInstallPath(for name: String, kind: PackageSnapshot.Kind) async -> String {
        if kind == .cask {
            return "\(caskroomPath)/\(name)"
        }
        if let path = try? await prefix(for: name), !path.isEmpty { return path }
        return "\(installation.cellar)/\(name)"
    }

    // MARK: - Read-only text commands

    public func search(_ query: String, kind: PackageSnapshot.Kind? = nil, descriptions: Bool = false) async throws -> [BrewSearchResult] {
        let validated = try BrewArgumentValidator.validateSearchQuery(query)
        var arguments = ["search"]
        if descriptions { arguments.append("--desc") }
        if let kind { arguments.append(kind == .cask ? "--cask" : "--formula") }
        arguments.append(validated)
        let result = try await execute(arguments, scope: .readOnly, capture: .separated, timeout: 60, onEvent: { _ in })
        if result.timedOut || result.cancelled {
            // Exit 130 after cancellation must not surface as "no results".
            throw makeError(command: "brew search", result: result, kind: result.timedOut ? .timedOut : .cancelled)
        }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? result.combinedOutput : result.stdout
        let parsed = BrewTextParser.parseSearch(output, defaultKind: kind ?? .formula)
        if parsed.isEmpty && result.exitCode != 0 {
            // `brew search` exits 1 when nothing matches; surface it as an empty
            // result rather than a failure unless there is a real error line.
            if output.contains("Error:") {
                throw makeError(command: "brew search", result: result, kind: .brewFailure)
            }
        }
        return parsed
    }

    public func listCasks() async throws -> [String] {
        let result = try await execute(["list", "--cask"], scope: .readOnly, capture: .separated, timeout: 20, onEvent: { _ in })
        return BrewTextParser.parseLineList(result.stdout)
    }

    public func prefix(for name: String) async throws -> String {
        _ = try BrewArgumentValidator.validatePackageToken(name)
        let result = try await execute(["--prefix", name], scope: .readOnly, capture: .separated, timeout: 15, onEvent: { _ in })
        guard result.exitCode == 0 else {
            throw makeError(command: "brew --prefix \(name)", result: result, kind: .notFound)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func listFiles(for name: String) async throws -> [String] {
        _ = try BrewArgumentValidator.validatePackageToken(name)
        let result = try await execute(["list", name], scope: .readOnly, capture: .separated, timeout: 30, onEvent: { _ in })
        if result.exitCode != 0 {
            throw makeError(command: "brew list \(name)", result: result, kind: .brewFailure)
        }
        return BrewTextParser.parseLineList(result.stdout)
    }

    public func changeLog(for name: String, limit: Int = 20) async throws -> String {
        _ = try BrewArgumentValidator.validatePackageToken(name)
        let safeLimit = max(1, min(limit, 100))
        let result = try await execute(
            ["log", "--oneline", "-n", String(safeLimit), name],
            scope: .readOnly,
            capture: .separated,
            timeout: 30,
            onEvent: { _ in }
        )
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty {
            return result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return output
    }

    public func doctor() async throws -> ProcessResult {
        try await execute(["doctor"], scope: .readOnly, capture: .merged, timeout: 90, onEvent: { _ in })
    }

    public func missing() async throws -> ProcessResult {
        try await execute(["missing"], scope: .readOnly, capture: .separated, timeout: 30, onEvent: { _ in })
    }

    public func cleanupPreview() async throws -> ProcessResult {
        try await execute(["cleanup", "-n"], scope: .readOnly, capture: .merged, timeout: 90, onEvent: { _ in })
    }

    public func autoremovePreview() async throws -> ProcessResult {
        try await execute(["autoremove", "--dry-run"], scope: .readOnly, capture: .merged, timeout: 60, onEvent: { _ in })
    }

    public func config() async throws -> String {
        let result = try await execute(["config"], scope: .readOnly, capture: .separated, timeout: 15, onEvent: { _ in })
        return result.stdout + result.stderr
    }

    // MARK: - Mutating commands

    public func install(_ name: String, kind: PackageSnapshot.Kind, onEvent: @escaping @Sendable (ProcessEvent) -> Void = { _ in }) async throws -> ProcessResult {
        _ = try BrewArgumentValidator.validatePackageToken(name)
        var arguments = ["install"]
        if kind == .cask { arguments.append("--cask") }
        arguments.append(name)
        return try await mutating(arguments, onEvent: onEvent)
    }

    public func uninstall(_ name: String, kind: PackageSnapshot.Kind, zap: Bool = false, onEvent: @escaping @Sendable (ProcessEvent) -> Void = { _ in }) async throws -> ProcessResult {
        _ = try BrewArgumentValidator.validatePackageToken(name)
        var arguments = ["uninstall"]
        arguments.append(kind == .cask ? "--cask" : "--formula")
        if zap && kind == .cask { arguments.append("--zap") }
        arguments.append(name)
        return try await mutating(arguments, onEvent: onEvent)
    }

    public func reinstall(_ name: String, kind: PackageSnapshot.Kind, force: Bool = false, onEvent: @escaping @Sendable (ProcessEvent) -> Void = { _ in }) async throws -> ProcessResult {
        _ = try BrewArgumentValidator.validatePackageToken(name)
        var arguments = ["reinstall"]
        if kind == .cask { arguments.append("--cask") }
        if force { arguments.append("--force") }
        arguments.append(name)
        return try await mutating(arguments, onEvent: onEvent)
    }

    public func upgrade(_ name: String, kind: PackageSnapshot.Kind, onEvent: @escaping @Sendable (ProcessEvent) -> Void = { _ in }) async throws -> ProcessResult {
        _ = try BrewArgumentValidator.validatePackageToken(name)
        var arguments = ["upgrade"]
        if kind == .cask { arguments.append("--cask") }
        arguments.append(name)
        return try await mutating(arguments, onEvent: onEvent)
    }

    public func upgradeAll(
        greedy: Bool = false,
        vulnerable: Bool = false,
        onEvent: @escaping @Sendable (ProcessEvent) -> Void = { _ in }
    ) async throws -> ProcessResult {
        var arguments = ["upgrade"]
        if greedy { arguments.append("--greedy") }
        if vulnerable { arguments.append("--vulnerable") }
        return try await mutating(arguments, onEvent: onEvent)
    }

    public func upgradeDryRun(_ name: String, kind: PackageSnapshot.Kind) async throws -> ProcessResult {
        _ = try BrewArgumentValidator.validatePackageToken(name)
        var arguments = ["upgrade", "--dry-run"]
        if kind == .cask { arguments.append("--cask") }
        arguments.append(name)
        let command = "brew " + arguments.joined(separator: " ")
        let result = try await execute(arguments, scope: .readOnly, capture: .merged, timeout: 120, onEvent: { _ in })
        if result.timedOut {
            throw makeError(command: command, result: result, kind: .timedOut)
        }
        if result.cancelled {
            throw makeError(command: command, result: result, kind: .cancelled)
        }
        guard result.exitCode == 0 else {
            throw makeError(command: command, result: result, kind: Self.classify(result))
        }
        return result
    }

    public func pin(_ name: String, kind: PackageSnapshot.Kind, onEvent: @escaping @Sendable (ProcessEvent) -> Void = { _ in }) async throws -> ProcessResult {
        _ = try BrewArgumentValidator.validatePackageToken(name)
        return try await mutating(["pin", kind == .cask ? "--cask" : "--formula", name], onEvent: onEvent)
    }

    public func unpin(_ name: String, kind: PackageSnapshot.Kind, onEvent: @escaping @Sendable (ProcessEvent) -> Void = { _ in }) async throws -> ProcessResult {
        _ = try BrewArgumentValidator.validatePackageToken(name)
        return try await mutating(["unpin", kind == .cask ? "--cask" : "--formula", name], onEvent: onEvent)
    }

    public func service(_ action: ServiceAction, name: String, onEvent: @escaping @Sendable (ProcessEvent) -> Void = { _ in }) async throws -> ProcessResult {
        _ = try BrewArgumentValidator.validatePackageToken(name)
        return try await mutating(["services", action.rawValue, name], onEvent: onEvent)
    }

    public func cleanup(scrub: Bool = false, prune: String? = nil, onEvent: @escaping @Sendable (ProcessEvent) -> Void = { _ in }) async throws -> ProcessResult {
        var arguments = ["cleanup"]
        if scrub { arguments.append("--scrub") }
        if let prune {
            let allowed = ["all", "8", "30", "90", "365"]
            if allowed.contains(prune) { arguments.append("--prune=\(prune)") }
        }
        return try await mutating(arguments, timeout: 600, onEvent: onEvent)
    }

    public func autoremove(onEvent: @escaping @Sendable (ProcessEvent) -> Void = { _ in }) async throws -> ProcessResult {
        try await mutating(["autoremove"], timeout: 600, onEvent: onEvent)
    }

    public func update(onEvent: @escaping @Sendable (ProcessEvent) -> Void = { _ in }) async throws -> ProcessResult {
        try await mutating(["update"], timeout: 300, onEvent: onEvent)
    }

    public func updateIfNeeded(onEvent: @escaping @Sendable (ProcessEvent) -> Void = { _ in }) async throws -> ProcessResult {
        try await mutating(["update-if-needed"], timeout: 300, onEvent: onEvent)
    }

    public func bundleDump(to path: String) async throws -> ProcessResult {
        guard BrewArgumentValidator.isValidPath(path) else {
            throw BrewArgumentValidator.ValidationError.invalidToken(path)
        }
        return try await execute(["bundle", "dump", "--file=\(path)"], scope: .readOnly, capture: .merged, timeout: 120, onEvent: { _ in })
    }

    public func bundleInstall(from path: String, onEvent: @escaping @Sendable (ProcessEvent) -> Void = { _ in }) async throws -> ProcessResult {
        guard BrewArgumentValidator.isValidPath(path) else {
            throw BrewArgumentValidator.ValidationError.invalidToken(path)
        }
        return try await mutating(["bundle", "install", "--file=\(path)"], timeout: 1800, onEvent: onEvent)
    }

    private func mutating(
        _ arguments: [String],
        timeout: TimeInterval = 1800,
        onEvent: @escaping @Sendable (ProcessEvent) -> Void
    ) async throws -> ProcessResult {
        let result = try await execute(arguments, scope: .mutating, capture: .merged, timeout: timeout, onEvent: onEvent)
        if result.cancelled || result.timedOut {
            throw makeError(command: "brew " + arguments.joined(separator: " "), result: result, kind: result.timedOut ? .timedOut : .cancelled)
        }
        guard result.exitCode == 0 else {
            let kind = Self.classify(result)
            throw makeError(command: "brew " + arguments.joined(separator: " "), result: result, kind: kind)
        }
        return result
    }

    public static func classify(_ result: ProcessResult) -> BrewFailureKind {
        if result.timedOut { return .timedOut }
        if result.cancelled { return .cancelled }
        let text = (result.stdout + "\n" + result.stderr + "\n" + result.combinedOutput).lowercased()
        if text.contains("permission denied") || text.contains("operation not permitted")
            || text.contains("not writable") || text.contains("read-only file system") {
            return .permissionDenied
        }
        if text.contains("could not resolve host") || text.contains("failed to download")
            || text.contains("could not connect") || text.contains("network is unreachable")
            || text.contains("ssl error") || text.contains("timed out") {
            return .networkFailure
        }
        if text.contains("no available formula") || text.contains("no available cask")
            || text.contains("no such file or directory") || text.contains("unknown command")
            || text.contains("no formula or cask") || text.contains("is not installed") {
            return .notFound
        }
        return .brewFailure
    }
}

public enum ServiceAction: String, Sendable, CaseIterable {
    case start
    case stop
    case restart
    case run
    case kill

    public var label: String {
        switch self {
        case .start: return "启动"
        case .stop: return "停止"
        case .restart: return "重启"
        case .run: return "仅运行一次"
        case .kill: return "停止但保留注册"
        }
    }

    public var explanation: String {
        switch self {
        case .run: return "运行一次且不注册开机自启。"
        case .kill: return "停止当前进程，但保留 launchd 注册。"
        default: return ""
        }
    }
}
