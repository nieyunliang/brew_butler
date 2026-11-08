import Darwin
import Foundation

/// Low-level process launcher used by `BrewProcessRunner`.
///
/// Design constraints from the PRD:
/// - arguments are passed to `posix_spawn` as an argv array; no shell is involved;
/// - the child is its own session/process-group leader, so cancellation can signal
///   the whole brew process tree (`kill(-pid, …)`) instead of orphaning subprocesses;
/// - stdout/stderr are merged through a PTY for live logs, or kept on separate
///   pipes when the caller needs clean JSON;
/// - cancellation escalates SIGINT → SIGTERM → SIGKILL.
final class SpawnedProcess: @unchecked Sendable {
    private let pid: pid_t
    private let request: ProcessRequest
    private let queue: DispatchQueue
    private let startedAt = Date()

    private var readers: [Int32: DispatchSourceRead] = [:]
    private var readerChannels: [Int32: ProcessChannel] = [:]
    private var buffers: [ProcessChannel: LineBuffer] = [:]
    private var processSource: DispatchSourceProcess?
    private var timeoutTimer: DispatchSourceTimer?

    private var stdoutAccum = ""
    private var stderrAccum = ""
    private var combinedAccum = ""
    private var openReaders = 0

    private var exited = false
    private var exitCode: Int32 = -1
    private var cancelled = false
    private var timedOut = false
    private var finished = false
    private var didStartReading = false

    private var onEvent: (@Sendable (ProcessEvent) -> Void)?
    private var continuation: CheckedContinuation<ProcessResult, Never>?

    static func launch(_ request: ProcessRequest) throws -> SpawnedProcess {
        guard FileManager.default.isExecutableFile(atPath: request.executable.path) else {
            throw ProcessError.notExecutable(request.executable.path)
        }
        return try SpawnedProcess(request: request)
    }

    private init(request: ProcessRequest) throws {
        self.request = request
        self.queue = DispatchQueue(label: "dev.brewbutler.process.\(UUID().uuidString)")
        self.buffers = [.merged: LineBuffer(), .stdout: LineBuffer(), .stderr: LineBuffer()]

        var readDescriptors: [(Int32, ProcessChannel)] = []
        var descriptorsToClose: [Int32] = []

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        // Failure paths below (openpty / pipe / posix_spawn) throw before the
        // explicit destroy runs; a defer is the only place both cleanups belong.
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        if request.captureMode == .merged {
            var master: Int32 = -1
            var slave: Int32 = -1
            var window = winsize(ws_row: 40, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0)
            guard openpty(&master, &slave, nil, nil, &window) == 0 else {
                throw ProcessError.spawnFailed(errno)
            }
            readDescriptors.append((master, .merged))
            descriptorsToClose = [slave]
            posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
            posix_spawn_file_actions_adddup2(&fileActions, slave, 1)
            posix_spawn_file_actions_adddup2(&fileActions, slave, 2)
            posix_spawn_file_actions_addclose(&fileActions, master)
            posix_spawn_file_actions_addclose(&fileActions, slave)
        } else {
            var outPipe: [Int32] = [0, 0]
            var errPipe: [Int32] = [0, 0]
            guard pipe(&outPipe) == 0 else { throw ProcessError.spawnFailed(errno) }
            guard pipe(&errPipe) == 0 else {
                close(outPipe[0]); close(outPipe[1])
                throw ProcessError.spawnFailed(errno)
            }
            readDescriptors = [(outPipe[0], .stdout), (errPipe[0], .stderr)]
            descriptorsToClose = [outPipe[1], errPipe[1]]
            posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
            posix_spawn_file_actions_adddup2(&fileActions, outPipe[1], 1)
            posix_spawn_file_actions_adddup2(&fileActions, errPipe[1], 2)
            posix_spawn_file_actions_addclose(&fileActions, outPipe[0])
            posix_spawn_file_actions_addclose(&fileActions, errPipe[0])
            posix_spawn_file_actions_addclose(&fileActions, outPipe[1])
            posix_spawn_file_actions_addclose(&fileActions, errPipe[1])
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // GUI/XCTest parents may have SIGINT/SIGTERM ignored; dispositions survive
        // exec, which would make the cancellation ladder wait for SIGKILL. Reset
        // the signals we rely on and start with an empty signal mask.
        var signalDefaults = sigset_t()
        sigemptyset(&signalDefaults)
        for signal in [SIGINT, SIGTERM, SIGHUP, SIGQUIT, SIGPIPE, SIGALRM] {
            sigaddset(&signalDefaults, signal)
        }
        posix_spawnattr_setsigdefault(&attributes, &signalDefaults)
        var signalMask = sigset_t()
        sigemptyset(&signalMask)
        posix_spawnattr_setsigmask(&attributes, &signalMask)
        let flags = Int16(POSIX_SPAWN_SETSID)
            | Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)
            | Int16(POSIX_SPAWN_SETSIGDEF)
            | Int16(POSIX_SPAWN_SETSIGMASK)
        posix_spawnattr_setflags(&attributes, flags)

        let executable = request.executable.path
        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + request.arguments).map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = request.environment
            .sorted { $0.key < $1.key }
            .map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer {
            for pointer in argv where pointer != nil { free(pointer) }
            for pointer in envp where pointer != nil { free(pointer) }
        }

        var childPID: pid_t = 0
        let spawnResult = posix_spawn(&childPID, executable, &fileActions, &attributes, &argv, &envp)

        for descriptor in descriptorsToClose {
            close(descriptor)
        }

        guard spawnResult == 0 else {
            for (descriptor, _) in readDescriptors { close(descriptor) }
            throw ProcessError.spawnFailed(spawnResult)
        }

        self.pid = childPID
        for (descriptor, channel) in readDescriptors {
            readerChannels[descriptor] = channel
        }

        // Reap as soon as the child exits. Output is drained independently; the
        // two conditions are joined in `finishIfReady`.
        let source = DispatchSource.makeProcessSource(identifier: childPID, eventMask: .exit, queue: queue)
        source.setEventHandler { [weak self] in self?.reap() }
        source.resume()
        self.processSource = source
    }

    deinit {
        processSource?.cancel()
        timeoutTimer?.cancel()
    }

    func wait(onEvent: @escaping @Sendable (ProcessEvent) -> Void) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            queue.async {
                self.onEvent = onEvent
                self.continuation = continuation
                onEvent(.started(pid: self.pid))
                if self.finished {
                    continuation.resume(returning: self.makeResult())
                    return
                }
                self.startReadingIfNeeded()
                self.startTimeoutIfNeeded()
                if self.exited {
                    self.scheduleDrainFallback()
                }
            }
        }
    }

    /// Thread-safe cancellation entry point. Safe to call multiple times.
    /// Escalates SIGINT → 3s → SIGTERM → 累计 7s → SIGKILL against the whole
    /// process group. Timeout handling lives in `startTimeoutIfNeeded`, which
    /// uses the shorter SIGTERM → 2s → SIGKILL ladder.
    func terminate() {
        queue.async {
            guard !self.finished else { return }
            self.cancelled = true
            guard !self.exited else { return }
            self.signalGroup(SIGINT)
            self.queue.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, !self.finished, !self.exited else { return }
                self.signalGroup(SIGTERM)
            }
            self.queue.asyncAfter(deadline: .now() + 7) { [weak self] in
                guard let self, !self.finished, !self.exited else { return }
                self.signalGroup(SIGKILL)
            }
        }
    }

    // MARK: - Reading

    private func startReadingIfNeeded() {
        guard !didStartReading else { return }
        didStartReading = true
        for (descriptor, channel) in readerChannels {
            _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            source.setEventHandler { [weak self] in self?.drain(descriptor: descriptor, channel: channel) }
            source.setCancelHandler { close(descriptor) }
            readers[descriptor] = source
            openReaders += 1
            source.resume()
        }
    }

    private func drain(descriptor: Int32, channel: ProcessChannel) {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count > 0 {
                let data = Data(buffer[0..<count])
                var lineBuffer = buffers[channel] ?? LineBuffer()
                let lines = lineBuffer.append(data)
                buffers[channel] = lineBuffer
                for line in lines { emit(line, channel: channel) }
            } else if count == 0 {
                closeReader(descriptor)
                return
            } else {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                closeReader(descriptor)
                return
            }
        }
    }

    private func closeReader(_ descriptor: Int32) {
        guard let source = readers.removeValue(forKey: descriptor) else { return }
        source.cancel()
        openReaders -= 1
        readerChannels.removeValue(forKey: descriptor)
        if exited && openReaders == 0 { finish() }
    }

    private func emit(_ rawLine: String, channel: ProcessChannel) {
        let text = ANSIStripper.strip(rawLine)
        switch channel {
        case .merged:
            combinedAccum += text + "\n"
        case .stdout:
            stdoutAccum += text + "\n"
            combinedAccum += text + "\n"
        case .stderr:
            stderrAccum += text + "\n"
            combinedAccum += text + "\n"
        }
        onEvent?(.line(ProcessLine(text: text, channel: channel)))
    }

    // MARK: - Exit & timeout

    private func reap() {
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        if result == 0 || (result == -1 && errno == EINTR) {
            queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, !self.exited else { return }
                self.reap()
            }
            return
        }
        if result == -1 {
            // ECHILD 等：退出状态不可恢复。保持 -1，不要把零值 status 误读为成功。
            exitCode = -1
        } else if (status & 0x7F) == 0 {
            exitCode = (status >> 8) & 0xFF
        } else if (status & 0x7F) == 0x7F {
            exitCode = (status >> 8) & 0xFF
        } else {
            exitCode = 128 + (status & 0x7F)
        }
        exited = true
        processSource?.cancel()
        processSource = nil
        timeoutTimer?.cancel()
        timeoutTimer = nil
        finishIfReady()
        scheduleDrainFallback()
    }

    private func scheduleDrainFallback() {
        guard !finished else { return }
        // Grandchildren can hold the pipe open after the child exits; give the
        // tail of the output 0.6s to drain, then force-close so a hung
        // subprocess cannot keep the task alive forever.
        queue.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.finished else { return }
            for descriptor in Array(self.readers.keys) {
                self.closeReader(descriptor)
            }
            self.finishIfReady()
        }
    }

    private func finishIfReady() {
        guard !finished else { return }
        if exited && openReaders == 0 { finish() }
    }

    private func startTimeoutIfNeeded() {
        guard let timeout = request.timeout, timeout > 0, timeoutTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in
            guard let self, !self.finished, !self.exited else { return }
            self.timedOut = true
            self.cancelled = true
            self.signalGroup(SIGTERM)
            self.queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, !self.finished, !self.exited else { return }
                self.signalGroup(SIGKILL)
            }
        }
        timer.resume()
        timeoutTimer = timer
    }

    private func signalGroup(_ signal: Int32) {
        if kill(-pid, signal) != 0 {
            _ = kill(pid, signal)
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        timeoutTimer?.cancel()
        timeoutTimer = nil
        processSource?.cancel()
        processSource = nil

        for (channel, var buffer) in buffers {
            if let last = buffer.flush() {
                emit(last, channel: channel)
            }
        }
        buffers.removeAll()
        for descriptor in Array(readers.keys) {
            if let source = readers.removeValue(forKey: descriptor) { source.cancel() }
        }
        openReaders = 0

        let result = makeResult()
        onEvent?(.finished(result))
        continuation?.resume(returning: result)
        continuation = nil
    }

    private func makeResult() -> ProcessResult {
        ProcessResult(
            exitCode: exitCode,
            stdout: stdoutAccum,
            stderr: stderrAccum,
            combinedOutput: combinedAccum,
            duration: Date().timeIntervalSince(startedAt),
            cancelled: cancelled,
            timedOut: timedOut
        )
    }
}

struct LineBuffer {
    private var data = Data()
    /// Number of already-scanned bytes at the head of `data`. Rescanning the
    /// whole buffer per 64KB chunk made multi-megabyte single-line JSON O(n²).
    private var scannedByteCount = 0

    mutating func append(_ chunk: Data) -> [String] {
        data.append(chunk)
        var lines: [String] = []
        var start = data.startIndex
        var index = data.startIndex + scannedByteCount
        while index < data.endIndex {
            let byte = data[index]
            if byte == 0x0A || byte == 0x0D {
                let lineData = data[start..<index]
                lines.append(String(decoding: lineData, as: UTF8.self))
                if byte == 0x0D, index + 1 < data.endIndex, data[index + 1] == 0x0A {
                    index += 1
                }
                start = index + 1
            }
            index += 1
        }
        scannedByteCount = data.endIndex - start
        if start > data.startIndex {
            data.removeSubrange(data.startIndex..<start)
        }
        return lines
    }

    mutating func flush() -> String? {
        guard !data.isEmpty else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        data.removeAll()
        scannedByteCount = 0
        return text
    }
}
