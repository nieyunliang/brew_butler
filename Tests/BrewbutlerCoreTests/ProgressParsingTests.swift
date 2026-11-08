import XCTest
@testable import BrewbutlerCore

/// BrewProgressParser is display-only: it must never invent progress, and it
/// must reject summary/aggregate lines instead of advancing the wrong row.
final class ProgressParsingTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: Stage verbs

    func testStageVerbMapping() {
        XCTAssertEqual(BrewProgressParser.event(forLine: "==> Downloading https://ghcr.io/v2/x"), .stage(.downloading))
        XCTAssertEqual(BrewProgressParser.event(forLine: "==> Fetching okhttp-4.12.jar"), .stage(.downloading))
        XCTAssertEqual(BrewProgressParser.event(forLine: "==> Pouring wget--1.24.9.arm64_sonoma.bottle.tar.gz"), .stage(.installing))
        XCTAssertEqual(BrewProgressParser.event(forLine: "==> Installing dependency"), .stage(.installing))
        XCTAssertEqual(BrewProgressParser.event(forLine: "==> Purging Cellar/wget/1.24.9"), .stage(.finishing))
        XCTAssertEqual(BrewProgressParser.event(forLine: "==> Cleaning up library leftovers"), .stage(.finishing))
        XCTAssertEqual(BrewProgressParser.event(forLine: "==> Auto-updating Homebrew..."), .stage(.preparing))
        XCTAssertEqual(BrewProgressParser.event(forLine: "==> Checking for dependents of upgraded formulae"), .stage(.preparing))
    }

    func testUnknownVerbIsIgnored() {
        XCTAssertNil(BrewProgressParser.event(forLine: "==> Totally-New-Verb something"))
    }

    func testNonStageLinesAreIgnored() {
        XCTAssertNil(BrewProgressParser.event(forLine: "wget 1.24.5 -> 1.24.9"))
        XCTAssertNil(BrewProgressParser.event(forLine: "Error: wget does not build"))
        XCTAssertNil(BrewProgressParser.event(forLine: ""))
        XCTAssertNil(BrewProgressParser.event(forLine: "==>"))
    }

    func testStageLabelsAreChineseAndStable() {
        XCTAssertEqual(BrewProgressStage.preparing.label, "准备中")
        XCTAssertEqual(BrewProgressStage.downloading.label, "下载中")
        XCTAssertEqual(BrewProgressStage.installing.label, "安装中")
        XCTAssertEqual(BrewProgressStage.finishing.label, "清理中")
    }

    // MARK: Per-package attribution

    func testPackageStartLines() {
        XCTAssertEqual(BrewProgressParser.event(forLine: "==> Upgrading wget"), .packageStarted("wget"))
        XCTAssertEqual(BrewProgressParser.event(forLine: "==> Installing Cask iterm2"), .packageStarted("iterm2"))
        XCTAssertEqual(BrewProgressParser.event(forLine: "==> Reinstalling openssl@3"), .packageStarted("openssl@3"))
        XCTAssertEqual(BrewProgressParser.event(forLine: "==> Upgrading anomalyco/tap/opencode-v2"), .packageStarted("anomalyco/tap/opencode-v2"))
    }

    func testSummaryAndAggregateLinesAreRejected() {
        XCTAssertNil(BrewProgressParser.packageName(fromLine: "==> Upgrading 2 outdated packages"))
        XCTAssertNil(BrewProgressParser.packageName(fromLine: "==> Installing dependency: cmake"))
        XCTAssertNil(BrewProgressParser.packageName(fromLine: "==> Would upgrade 2 outdated packages"))
        XCTAssertNil(BrewProgressParser.packageName(fromLine: "==> Upgrading"))
        XCTAssertNil(BrewProgressParser.packageName(fromLine: "==> Upgrading --cask"))
        XCTAssertNil(BrewProgressParser.packageName(fromLine: "==> Pouring wget--1.24.9.arm64_sonoma.bottle.tar.gz"))
    }

    // MARK: Real brew output (fixture captured via `brew upgrade --dry-run`)

    func testDryRunFixtureOnlyYieldsSafeEvents() throws {
        let text = try fixture("upgrade-dry-run.txt")
        let events = text.split(separator: "\n").map { BrewProgressParser.event(forLine: String($0)) }
        // The dry-run summary and version table must not produce package
        // attribution; nothing in this output may claim a package started.
        XCTAssertFalse(events.compactMap { $0 }.contains { $0.isPackageStarted })
    }
}

extension BrewProgressEvent {
    var isPackageStarted: Bool {
        if case .packageStarted = self { return true }
        return false
    }
}
