import Foundation

public struct ProcessRequest: Sendable {
    public enum CaptureMode: String, Sendable {
        /// PTY-backed, stdout + stderr share one ordered stream. Best for live logs.
        case merged
        /// Two pipes. stdout stays clean for JSON decoding; stderr is kept for diagnostics.
        case separated
    }

    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: URL?
    public var timeout: TimeInterval?
    public var captureMode: CaptureMode

    public init(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL? = nil,
        timeout: TimeInterval? = nil,
        captureMode: CaptureMode = .merged
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.timeout = timeout
        self.captureMode = captureMode
    }
}

public enum ProcessChannel: String, Sendable {
    case merged
    case stdout
    case stderr
}

public struct ProcessLine: Sendable, Hashable {
    public var text: String
    public var channel: ProcessChannel

    public init(text: String, channel: ProcessChannel = .merged) {
        self.text = text
        self.channel = channel
    }
}

public struct ProcessResult: Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var combinedOutput: String
    public var duration: TimeInterval
    public var cancelled: Bool
    public var timedOut: Bool

    public init(
        exitCode: Int32,
        stdout: String = "",
        stderr: String = "",
        combinedOutput: String = "",
        duration: TimeInterval = 0,
        cancelled: Bool = false,
        timedOut: Bool = false
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.combinedOutput = combinedOutput
        self.duration = duration
        self.cancelled = cancelled
        self.timedOut = timedOut
    }
}

public enum ProcessEvent: Sendable {
    case started(pid: Int32)
    case line(ProcessLine)
    case finished(ProcessResult)
}

public protocol ProcessRunning: Sendable {
    func run(
        _ request: ProcessRequest,
        onEvent: @escaping @Sendable (ProcessEvent) -> Void
    ) async throws -> ProcessResult
}

public enum ProcessError: Error, LocalizedError, Sendable {
    case launchFailed(String)
    case spawnFailed(Int32)
    case notExecutable(String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let detail):
            return "无法启动进程：\(detail)"
        case .spawnFailed(let code):
            return "无法启动进程（错误码 \(code)）：\(String(cString: strerror(code)))"
        case .notExecutable(let path):
            return "不可执行的路径：\(path)"
        }
    }
}
