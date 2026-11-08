import XCTest
@testable import BrewbutlerCore

final class ProcessIntegrationTests: XCTestCase {
    func testMergedOutputAndExitCode() async throws {
        let runner = BrewProcessRunner()
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello", "brewbutler"],
            environment: ProcessInfo.processInfo.environment,
            timeout: 5,
            captureMode: .merged
        )
        let result = try await runner.run(request, onEvent: { _ in })
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.combinedOutput.contains("hello brewbutler"))
        XCTAssertFalse(result.timedOut)
    }

    func testSeparatedChannelsKeepStdoutCleanForJSON() async throws {
        let runner = BrewProcessRunner()
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/bin/ls"),
            arguments: ["/definitely/not/a/real/path"],
            environment: ProcessInfo.processInfo.environment,
            timeout: 5,
            captureMode: .separated
        )
        let result = try await runner.run(request, onEvent: { _ in })
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(result.stderr.isEmpty)
        XCTAssertFalse(result.stdout.contains("No such file"))
    }

    func testTimeoutEscalatesAndFinishes() async throws {
        let runner = BrewProcessRunner()
        let started = Date()
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["10"],
            environment: ProcessInfo.processInfo.environment,
            timeout: 0.5,
            captureMode: .merged
        )
        let result = try await runner.run(request, onEvent: { _ in })
        XCTAssertTrue(result.timedOut)
        XCTAssertTrue(result.cancelled)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testTaskCancellationTerminatesChild() async throws {
        let runner = BrewProcessRunner()
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["10"],
            environment: ProcessInfo.processInfo.environment,
            timeout: nil,
            captureMode: .merged
        )
        let task = Task { () -> ProcessResult in
            try await runner.run(request, onEvent: { _ in })
        }
        try await Task.sleep(nanoseconds: 250_000_000)
        task.cancel()
        let result = try await task.value
        XCTAssertTrue(result.cancelled)
        XCTAssertLessThan(result.duration, 5)
    }

    func testRealBrewDetection() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew") else {
            throw XCTSkip("Homebrew not installed on this machine")
        }
        let locator = BrewLocator()
        switch await locator.locate() {
        case .success(let installation):
            XCTAssertEqual(installation.executablePath, "/opt/homebrew/bin/brew")
            XCTAssertNotNil(installation.version)
            XCTAssertEqual(installation.prefix, "/opt/homebrew")
            XCTAssertFalse(installation.capabilities.degradedReasons.contains { $0.contains("低于") })
            XCTAssertTrue(installation.capabilities.vulns)
            XCTAssertTrue(installation.capabilities.listVersionsJSON)
            XCTAssertEqual(installation.capabilities.jqPath, "/usr/bin/jq")
        case .failure(let error):
            XCTFail("brew should be found: \(error)")
        }
    }

    func testRealInfoInstalledJSON() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew") else {
            throw XCTSkip("Homebrew not installed on this machine")
        }
        let locator = BrewLocator()
        guard case .success(let installation) = await locator.locate() else {
            return XCTFail("brew should be found")
        }
        let client = BrewClient(installation: installation)
        let info = try await client.infoInstalled()
        XCTAssertGreaterThan(info.formulae.count, 0)
        let outdated = try await client.outdated()
        XCTAssertGreaterThanOrEqual(outdated.formulae.count, 0)
        let services = try await client.services()
        XCTAssertTrue(services is [BrewService])
    }
}
