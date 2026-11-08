import XCTest
@testable import BrewbutlerCore

// MARK: - Mock process runner

/// Captures every ProcessRequest and returns scripted ProcessResults.
/// Used to exercise production BrewClient without launching brew.
final class MockProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var scripted: [ProcessResult]
    private(set) var requests: [ProcessRequest] = []

    init(_ scripted: [ProcessResult]) {
        self.scripted = scripted
    }

    convenience init(_ scripted: ProcessResult) {
        self.init([scripted])
    }

    func run(
        _ request: ProcessRequest,
        onEvent: @escaping @Sendable (ProcessEvent) -> Void
    ) async throws -> ProcessResult {
        lock.lock()
        requests.append(request)
        let result: ProcessResult
        if scripted.isEmpty {
            result = ProcessResult(exitCode: -1, stderr: "mock runner: no scripted result")
        } else {
            result = scripted.removeFirst()
        }
        lock.unlock()
        return result
    }

    var lastRequest: ProcessRequest? {
        lock.lock(); defer { lock.unlock() }
        return requests.last
    }
}

// MARK: - Shared helpers

private let validOutdatedJSON = #"""
{"formulae":[{"name":"aom","installed_versions":["3.14.1"],"current_version":"3.15.2","pinned":false,"pinned_version":null}],"casks":[]}
"""#

private let emptyOutdatedJSON = #"{"formulae":[],"casks":[]}"#

private func makeInstallation() -> BrewInstallation {
    BrewInstallation(
        executablePath: "/opt/homebrew/bin/brew",
        prefix: "/opt/homebrew",
        cellar: "/opt/homebrew/Cellar",
        cache: "/tmp/brewbutler-test-cache",
        repository: "/opt/homebrew/Repository",
        capabilities: BrewCapabilities(versionText: "Homebrew 7.0.10", outdatedJSONv2: true, dryRun: true)
    )
}

private func makeClient(_ runner: MockProcessRunner) -> BrewClient {
    BrewClient(installation: makeInstallation(), runner: runner)
}

private func processResult(
    _ exitCode: Int32,
    stdout: String = "",
    stderr: String = "",
    cancelled: Bool = false,
    timedOut: Bool = false
) -> ProcessResult {
    ProcessResult(
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
        combinedOutput: stdout + stderr,
        duration: 0.01,
        cancelled: cancelled,
        timedOut: timedOut
    )
}

private func infoResponse(_ json: String) -> BrewInfoResponse {
    // swiftlint:disable:next force_try
    try! JSONDecoder().decode(BrewInfoResponse.self, from: Data(json.utf8))
}

private func outdatedResponse(_ json: String) -> BrewOutdatedResponse {
    // swiftlint:disable:next force_try
    try! JSONDecoder().decode(BrewOutdatedResponse.self, from: Data(json.utf8))
}

private func assertKind(
    _ error: Error,
    _ expected: BrewFailureKind,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let brewError = error as? BrewCommandError else {
        XCTFail("expected BrewCommandError, got \(type(of: error)): \(error)", file: file, line: line)
        return
    }
    XCTAssertEqual(brewError.kind, expected, "unexpected kind for \(brewError.command)", file: file, line: line)
}

// MARK: - Command construction

final class UpdatePipelineCommandTests: XCTestCase {
    func testOutdatedGreedyArguments() async throws {
        let runner = MockProcessRunner(processResult(0, stdout: validOutdatedJSON))
        let client = makeClient(runner)

        let response = try await client.outdated(greedy: true)

        XCTAssertEqual(response.formulae.count, 1)
        XCTAssertEqual(runner.lastRequest?.arguments, ["outdated", "--json=v2", "--greedy"])
        XCTAssertEqual(runner.lastRequest?.captureMode, .separated)
    }

    func testOutdatedDefaultArgumentsHaveNoGreedyFlag() async throws {
        let runner = MockProcessRunner(processResult(0, stdout: validOutdatedJSON))
        let client = makeClient(runner)

        _ = try await client.outdated()

        XCTAssertEqual(runner.lastRequest?.arguments, ["outdated", "--json=v2"])
    }

    func testUpgradeAllGreedyAndVulnerableArguments() async throws {
        let runner = MockProcessRunner(processResult(0))
        let client = makeClient(runner)

        _ = try await client.upgradeAll(greedy: true, vulnerable: true)

        XCTAssertEqual(runner.lastRequest?.arguments, ["upgrade", "--greedy", "--vulnerable"])
        XCTAssertEqual(runner.lastRequest?.captureMode, .merged)
    }

    func testUpgradeAllDefaultArguments() async throws {
        let runner = MockProcessRunner(processResult(0))
        let client = makeClient(runner)

        _ = try await client.upgradeAll()

        XCTAssertEqual(runner.lastRequest?.arguments, ["upgrade"])
    }

    func testUpgradeFormulaArguments() async throws {
        let runner = MockProcessRunner(processResult(0))
        let client = makeClient(runner)

        _ = try await client.upgrade("aom", kind: .formula)

        XCTAssertEqual(runner.lastRequest?.arguments, ["upgrade", "aom"])
    }

    func testUpgradeCaskArguments() async throws {
        let runner = MockProcessRunner(processResult(0))
        let client = makeClient(runner)

        _ = try await client.upgrade("raycast", kind: .cask)

        XCTAssertEqual(runner.lastRequest?.arguments, ["upgrade", "--cask", "raycast"])
    }

    /// O-01：「检查更新」先同步上游索引；这是变更类命令，必须精确 argv、
    /// 变更 scope（不能注入只读的 HOMEBREW_NO_AUTO_UPDATE）且非 0 退出按失败处理。
    func testUpdateIfNeededArgumentsAndMutatingScope() async throws {
        let runner = MockProcessRunner(processResult(0))
        let client = makeClient(runner)

        _ = try await client.updateIfNeeded()

        XCTAssertEqual(runner.lastRequest?.arguments, ["update-if-needed"])
        XCTAssertEqual(runner.lastRequest?.timeout, 300)
        XCTAssertEqual(runner.lastRequest?.captureMode, .merged)
        XCTAssertNil(runner.lastRequest?.environment["HOMEBREW_NO_AUTO_UPDATE"])
    }

    func testUpdateIfNeededNonZeroExitThrowsBrewFailure() async throws {
        let runner = MockProcessRunner(processResult(1, stderr: "Error: Failed to update tap"))
        let client = makeClient(runner)

        do {
            _ = try await client.updateIfNeeded()
            XCTFail("expected updateIfNeeded to throw on exit 1")
        } catch {
            assertKind(error, .brewFailure)
        }
    }

    func testUpgradeDryRunArguments() async throws {
        let runner = MockProcessRunner([
            processResult(0, stdout: "Would upgrade 1 package"),
            processResult(0, stdout: "Would upgrade 1 package")
        ])
        let client = makeClient(runner)

        let formulaResult = try await client.upgradeDryRun("aom", kind: .formula)
        let caskResult = try await client.upgradeDryRun("raycast", kind: .cask)

        XCTAssertEqual(formulaResult.exitCode, 0)
        XCTAssertEqual(caskResult.exitCode, 0)
        XCTAssertEqual(runner.requests.count, 2)
        XCTAssertEqual(runner.requests[0].arguments, ["upgrade", "--dry-run", "aom"])
        XCTAssertEqual(runner.requests[1].arguments, ["upgrade", "--dry-run", "--cask", "raycast"])
    }

    func testUpgradeDryRunThrowsOnNonZeroExit() async throws {
        let runner = MockProcessRunner(
            processResult(1, stdout: "Error: something went wrong", stderr: "Error: something went wrong")
        )
        let client = makeClient(runner)

        do {
            _ = try await client.upgradeDryRun("aom", kind: .formula)
            XCTFail("expected upgradeDryRun to throw on non-zero exit")
        } catch let error as BrewCommandError {
            XCTAssertEqual(error.kind, .brewFailure)
            XCTAssertEqual(error.exitCode, 1)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testUpgradeDryRunThrowsOnTimeout() async throws {
        let runner = MockProcessRunner(processResult(0, stdout: "", timedOut: true))
        let client = makeClient(runner)

        do {
            _ = try await client.upgradeDryRun("aom", kind: .formula)
            XCTFail("expected upgradeDryRun to throw on timeout")
        } catch let error as BrewCommandError {
            XCTAssertEqual(error.kind, .timedOut)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testInjectionTokenThrowsBeforeAnySpawn() async throws {
        let runner = MockProcessRunner(processResult(0))
        let client = makeClient(runner)

        do {
            _ = try await client.upgrade("aom; rm -rf /", kind: .formula)
            XCTFail("expected injection token to be rejected")
        } catch is BrewArgumentValidator.ValidationError {
            XCTAssertTrue(runner.requests.isEmpty, "validator must reject before launching a process")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFullyQualifiedTokenIsPassedThrough() async throws {
        let runner = MockProcessRunner(processResult(0))
        let client = makeClient(runner)

        _ = try await client.upgrade("user/tap/foo", kind: .formula)

        XCTAssertEqual(runner.lastRequest?.arguments, ["upgrade", "user/tap/foo"])
    }
}

// MARK: - makeError / decodeJSON semantics

final class UpdatePipelineFailureSemanticsTests: XCTestCase {
    func testMakeErrorTimeoutWinsOverCancelled() async throws {
        // A mutating call reports both flags; timeout must take precedence.
        let runner = MockProcessRunner(
            processResult(130, stdout: "", cancelled: true, timedOut: true)
        )
        let client = makeClient(runner)

        do {
            _ = try await client.upgrade("aom", kind: .formula)
            XCTFail("expected cancelled/timeout mutating call to throw")
        } catch let error as BrewCommandError {
            XCTAssertEqual(error.kind, .timedOut)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDecodeJSONExitZeroWithValidPayloadReturnsValue() async throws {
        let runner = MockProcessRunner(processResult(0, stdout: validOutdatedJSON))
        let client = makeClient(runner)

        let response = try await client.outdated()

        XCTAssertEqual(response.formulae.first?.name, "aom")
        XCTAssertEqual(response.formulae.first?.currentVersion, "3.15.2")
    }

    func testDecodeJSONOutdatedAcceptsExitOneWithValidPayload() async throws {
        let runner = MockProcessRunner(
            processResult(1, stdout: validOutdatedJSON, stderr: "Warning: using cached API data")
        )
        let client = makeClient(runner)

        let response = try await client.outdated()

        XCTAssertEqual(response.formulae.count, 1)
    }

    func testDecodeJSONRejectsUnacceptedExitCodeWithClassifiedKind() async throws {
        // Exit 2 is not in outdated's acceptedExitCodes: [0, 1].
        let runner = MockProcessRunner(
            processResult(2, stdout: validOutdatedJSON, stderr: "Error: unexpected brew failure")
        )
        let client = makeClient(runner)

        do {
            _ = try await client.outdated()
            XCTFail("expected non-accepted exit code to throw")
        } catch {
            assertKind(error, .brewFailure)
        }
    }

    func testDecodeJSONExitZeroGarbageIsParseFailure() async throws {
        let runner = MockProcessRunner(processResult(0, stdout: "not json at all"))
        let client = makeClient(runner)

        do {
            _ = try await client.outdated()
            XCTFail("expected malformed JSON to throw")
        } catch {
            assertKind(error, .parseFailure)
        }
    }

    func testDecodeJSONNonZeroGarbageUsesClassifiedKind() async throws {
        let runner = MockProcessRunner(
            processResult(1, stdout: "", stderr: "Error: Could not resolve host: github.com")
        )
        let client = makeClient(runner)

        do {
            _ = try await client.outdated()
            XCTFail("expected failed command to throw")
        } catch {
            assertKind(error, .networkFailure)
        }
    }

    func testDecodeJSONTimedOutWinsOverValidPayload() async throws {
        let runner = MockProcessRunner(processResult(0, stdout: validOutdatedJSON, timedOut: true))
        let client = makeClient(runner)

        do {
            _ = try await client.outdated()
            XCTFail("expected timeout to throw even with parseable stdout")
        } catch {
            assertKind(error, .timedOut)
        }
    }

    func testDecodeJSONCancelledWinsOverValidPayload() async throws {
        let runner = MockProcessRunner(processResult(0, stdout: validOutdatedJSON, cancelled: true))
        let client = makeClient(runner)

        do {
            _ = try await client.outdated()
            XCTFail("expected cancellation to throw even with parseable stdout")
        } catch {
            assertKind(error, .cancelled)
        }
    }
}

// MARK: - PackageIndex outdated merge

final class UpdatePipelineIndexTests: XCTestCase {
    func testTapFormulaMergesByFullName() throws {
        let info = infoResponse(#"""
        {"formulae":[{"name":"foo","full_name":"user/tap/foo","outdated":false,"pinned":false,
          "versions":{"stable":"2.0"},"installed":[{"version":"1.0"}]}],"casks":[]}
        """#)
        // brew outdated --json=v2 reports formula rows by full_name.
        let outdated = outdatedResponse(#"""
        {"formulae":[{"name":"user/tap/foo","installed_versions":["1.0"],"current_version":"2.0","pinned":false,"pinned_version":null}],"casks":[]}
        """#)

        let index = PackageIndex.build(info: info, outdated: outdated, vulnReport: nil)

        XCTAssertEqual(index.packages.count, 1)
        XCTAssertEqual(index.packages.first?.name, "foo")
        XCTAssertEqual(index.packages.first?.fullName, "user/tap/foo")
        XCTAssertTrue(index.packages.first?.outdated ?? false)
        XCTAssertEqual(index.outdated.count, 1)
        XCTAssertEqual(index.outdated.first?.name, "user/tap/foo")
        XCTAssertEqual(index.outdated.first?.kind, .formula)
        XCTAssertEqual(index.outdated.first?.currentVersion, "2.0")
        // UpdatesView opens details with the outdated row name (full_name).
        XCTAssertNotNil(index.package(named: "user/tap/foo"))
        XCTAssertNotNil(index.package(named: "user/tap/foo", kind: .formula))
        XCTAssertNotNil(index.package(named: "foo"))
        XCTAssertEqual(index.package(named: "user/tap/foo")?.id, "formula:foo")
    }

    func testTapFormulaPinnedStateComesFromMergedRow() throws {
        let info = infoResponse(#"""
        {"formulae":[{"name":"foo","full_name":"user/tap/foo","outdated":false,"pinned":false,
          "versions":{"stable":"2.0"},"installed":[{"version":"1.0"}]}],"casks":[]}
        """#)
        let outdated = outdatedResponse(#"""
        {"formulae":[{"name":"user/tap/foo","installed_versions":["1.0"],"current_version":"2.0","pinned":true,"pinned_version":"1.0"}],"casks":[]}
        """#)

        let index = PackageIndex.build(info: info, outdated: outdated, vulnReport: nil)

        XCTAssertTrue(index.packages.first?.pinned ?? false)
        XCTAssertTrue(index.outdated.first?.pinned ?? false)
    }

    func testDuplicateOutdatedNamesDoNotCrashAndFirstWins() throws {
        let outdated = outdatedResponse(#"""
        {"formulae":[
          {"name":"aom","installed_versions":["1.0"],"current_version":"2.0","pinned":false,"pinned_version":null},
          {"name":"aom","installed_versions":["1.0"],"current_version":"3.0","pinned":false,"pinned_version":null}
        ],"casks":[]}
        """#)

        // Previously Dictionary(uniqueKeysWithValues:) trapped here.
        let index = PackageIndex.build(info: BrewInfoResponse(), outdated: outdated, vulnReport: nil)

        XCTAssertEqual(index.outdated.count, 1)
        XCTAssertEqual(index.outdated.first?.currentVersion, "2.0")
    }

    func testDuplicateOutdatedCaskTokensDoNotCrashAndFirstWins() throws {
        let info = infoResponse(#"""
        {"formulae":[],"casks":[{"token":"raycast","full_token":"raycast","version":"1.0","installed":"0.9","outdated":false}]}
        """#)
        let outdated = outdatedResponse(#"""
        {"formulae":[],"casks":[
          {"token":"raycast","installed_versions":["0.9"],"current_version":"1.0","pinned":false},
          {"token":"raycast","installed_versions":["0.9"],"current_version":"1.1","pinned":false}
        ]}
        """#)

        let index = PackageIndex.build(info: info, outdated: outdated, vulnReport: nil)

        XCTAssertEqual(index.outdated.count, 1)
        XCTAssertEqual(index.outdated.first?.currentVersion, "1.0")
        XCTAssertTrue(index.packages.first?.outdated ?? false)
    }

    func testEmptyNameOutdatedRowsAreSkipped() throws {
        let outdated = outdatedResponse(#"""
        {"formulae":[{"name":"","installed_versions":[],"current_version":"9.9","pinned":false,"pinned_version":null}],"casks":[]}
        """#)

        let index = PackageIndex.build(info: BrewInfoResponse(), outdated: outdated, vulnReport: nil)

        XCTAssertTrue(index.outdated.isEmpty)
        XCTAssertTrue(index.packages.isEmpty)
        XCTAssertNil(index.package(named: ""))
    }

    func testOutdatedRowStillMergesWithoutInfoOutdatedFlag() throws {
        let info = infoResponse(#"""
        {"formulae":[{"name":"aom","full_name":"aom","installed":[{"version":"3.14.1"}],"versions":{"stable":"3.15.2"}}],"casks":[]}
        """#)
        let outdated = outdatedResponse(#"""
        {"formulae":[{"name":"aom","installed_versions":["3.14.1"],"current_version":"3.15.2","pinned":false,"pinned_version":null}],"casks":[]}
        """#)

        let index = PackageIndex.build(info: info, outdated: outdated, vulnReport: nil)

        XCTAssertTrue(index.packages.first?.outdated ?? false)
        XCTAssertEqual(index.outdated.first?.name, "aom")
    }
}
