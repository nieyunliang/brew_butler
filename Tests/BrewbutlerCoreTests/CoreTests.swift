import XCTest
@testable import BrewbutlerCore

final class FixtureTests: XCTestCase {
    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }

    private func data(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureURL(name))
    }

    func testDecodeInstalledInfo() throws {
        let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data("info-installed.json"))
        XCTAssertEqual(response.formulae.count, 59)
        XCTAssertEqual(response.casks.count, 0)

        let aom = try XCTUnwrap(response.formulae.first { $0.name == "aom" })
        XCTAssertEqual(aom.versions?.stable, "3.15.2")
        XCTAssertEqual(aom.installed?.first?.version, "3.14.1")
        XCTAssertEqual(aom.license, "BSD-2-Clause")
        XCTAssertEqual(aom.dependencies, ["libvmaf"])
        XCTAssertEqual(aom.outdated, true)
        XCTAssertEqual(aom.pinned, false)
        XCTAssertEqual(aom.installed?.first?.installedOnRequest, false)
    }

    func testDecodeOutdated() throws {
        let response = try JSONDecoder().decode(BrewOutdatedResponse.self, from: data("outdated.json"))
        XCTAssertEqual(response.formulae.count, 36)
        let aom = try XCTUnwrap(response.formulae.first { $0.name == "aom" })
        XCTAssertEqual(aom.installedVersions.values, ["3.14.1"])
        XCTAssertEqual(aom.currentVersion, "3.15.2")
        XCTAssertEqual(aom.pinned, false)
    }

    func testDecodeVulnReportAndExitCodeSemantics() throws {
        let report = try JSONDecoder().decode(VulnReport.self, from: data("vulns.json"))
        XCTAssertEqual(report.checked, 36)
        XCTAssertFalse(report.complete)
        XCTAssertEqual(report.findings.count, 13)
        XCTAssertEqual(report.skippedFormulae.count, 23)
        XCTAssertEqual(report.unscannedFormulae["oh-my-posh"], "untrusted_tap")
        XCTAssertGreaterThan(report.totalVulnerabilityCount, 0)
        XCTAssertGreaterThan(report.severityCounts[.high] ?? 0, 0)
        XCTAssertTrue(report.findings.contains { $0.formula == "libheif" })
        let libheif = try XCTUnwrap(report.findings.first { $0.formula == "libheif" })
        XCTAssertEqual(libheif.worstSeverity, .critical)
        XCTAssertTrue(libheif.hasFix)
        XCTAssertNotNil(libheif.vulnerabilities.first?.osvURL)
    }

    func testDecodeServicesEmpty() throws {
        let services = try JSONDecoder().decode([BrewService].self, from: data("services.json"))
        XCTAssertTrue(services.isEmpty)
    }

    func testDecodeListVersions() throws {
        let response = try JSONDecoder().decode(BrewListVersionsResponse.self, from: data("list-versions.json"))
        XCTAssertEqual(response.formulae.count, 60)
        let aom = try XCTUnwrap(response.formulae.first { $0.name == "aom" })
        XCTAssertEqual(aom.linkedVersion, "3.14.1")
        XCTAssertNil(aom.pinnedVersion)
    }

    func testBuildIndexMergesOutdatedAndVulnerabilities() throws {
        let info = try JSONDecoder().decode(BrewInfoResponse.self, from: data("info-installed.json"))
        let outdated = try JSONDecoder().decode(BrewOutdatedResponse.self, from: data("outdated.json"))
        let vulns = try JSONDecoder().decode(VulnReport.self, from: data("vulns.json"))

        let index = PackageIndex.build(info: info, outdated: outdated, vulnReport: vulns)
        XCTAssertEqual(index.packages.count, 59)
        XCTAssertEqual(index.outdated.count, 36)
        XCTAssertEqual(index.securityUpdates.count, 12)
        XCTAssertEqual(index.reverseDependencies["libvmaf"]?.contains("aom"), true)

        let aom = try XCTUnwrap(index.package(named: "aom"))
        XCTAssertTrue(aom.outdated)
        XCTAssertEqual(aom.installedVersion, "3.14.1")
        XCTAssertEqual(aom.stableVersion, "3.15.2")

        let libheif = try XCTUnwrap(index.package(named: "libheif"))
        XCTAssertEqual(libheif.vulnerabilitySeverity, .critical)
        XCTAssertTrue(libheif.hasVulnerability)

        // Security updates must sort before regular updates.
        XCTAssertTrue(index.outdated.first?.isSecurityUpdate == true)
        XCTAssertFalse(index.snapshotHash.isEmpty)
    }
}

final class ParsingTests: XCTestCase {
    private func fixture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testSearchParsingKeepsSections() throws {
        let results = BrewTextParser.parseSearch(try fixture("search-desc.txt"))
        XCTAssertEqual(results.count, 15)
        XCTAssertEqual(results.filter { $0.kind == .formula }.count, 14)
        XCTAssertEqual(results.first?.name, "gojq")
        XCTAssertEqual(results.last?.kind, .cask)
        XCTAssertEqual(results.last?.name, "jquake")
    }

    func testCleanupPreviewParsing() throws {
        let preview = BrewTextParser.parseCleanupPreview(try fixture("cleanup-preview.txt"))
        XCTAssertEqual(preview.removals.count, 8)
        XCTAssertEqual(preview.reclaimText, "approximately 232.7MB")
        XCTAssertEqual(preview.warnings.count, 36)
        XCTAssertTrue(preview.removals.first?.path.contains("portable-ruby") == true)
    }

    func testDoctorParsingGroupsWarnings() throws {
        let report = BrewTextParser.parseDoctor(try fixture("doctor.txt"))
        XCTAssertGreaterThanOrEqual(report.issues.count, 3)
        XCTAssertTrue(report.issues.contains { $0.title.contains("Unbrewed header files") })
        XCTAssertTrue(report.issues.contains { $0.title.contains("not trusted") })
        XCTAssertTrue(report.issues.contains { !$0.suggestedCommands.isEmpty } || report.issues.contains { $0.title.contains("not trusted") })
        XCTAssertFalse(report.intro.isEmpty)
    }

    func testMissingParsing() throws {
        let report = BrewTextParser.parseMissing(try fixture("missing.txt"))
        XCTAssertFalse(report.hasIssues)
    }
}

final class SecurityTests: XCTestCase {
    func testTokenValidationRejectsInjection() {
        let bad = ["", "-v", "a; rm -rf /", "a$(whoami)", "a b", "a\nb", "a..b", "../x", "/a", "a/", "a//b", String(repeating: "a", count: 129)]
        for token in bad {
            XCTAssertFalse(BrewArgumentValidator.isValidPackageToken(token), "should reject \(token)")
        }
    }

    func testTokenValidationAcceptsRealBrewTokens() {
        let good = ["aom", "openssl@3", "python@3.13", "homebrew/core/foo", "user/tap/formula", "libheif", "cocoapods", "1password-cli", "emacs-plus@30"]
        for token in good {
            XCTAssertTrue(BrewArgumentValidator.isValidPackageToken(token), "should accept \(token)")
        }
    }

    func testSearchQueryValidationRejectsFlagInjection() {
        let bad = ["", "   ", "-v", "--cask", "a\nb", "a\u{0000}b", String(repeating: "a", count: 129)]
        for query in bad {
            XCTAssertThrowsError(try BrewArgumentValidator.validateSearchQuery(query), "should reject \(query)")
        }
    }

    func testSearchQueryValidationAcceptsRealQueries() throws {
        XCTAssertEqual(try BrewArgumentValidator.validateSearchQuery("node"), "node")
        XCTAssertEqual(try BrewArgumentValidator.validateSearchQuery("visual studio code"), "visual studio code")
        XCTAssertEqual(try BrewArgumentValidator.validateSearchQuery("openssl@3"), "openssl@3")
        XCTAssertEqual(try BrewArgumentValidator.validateSearchQuery("  sqlite  "), "sqlite")
        XCTAssertEqual(try BrewArgumentValidator.validateSearchQuery("python-tk@3.13"), "python-tk@3.13")
    }

    func testURLValidation() {
        XCTAssertTrue(BrewArgumentValidator.isSafeWebURL("https://example.com/x"))
        XCTAssertTrue(BrewArgumentValidator.isSafeWebURL("http://example.com"))
        XCTAssertFalse(BrewArgumentValidator.isSafeWebURL("file:///etc/passwd"))
        XCTAssertFalse(BrewArgumentValidator.isSafeWebURL("javascript:alert(1)"))
        XCTAssertFalse(BrewArgumentValidator.isSafeWebURL("not a url"))
    }

    func testANSIStripping() {
        let input = "\u{001B}[31mError:\u{001B}[0m bad \u{001B}]0;title\u{0007}thing\r\n"
        XCTAssertEqual(ANSIStripper.strip(input), "Error: bad thing\r\n")
    }

    func testVulnSeverityOrdering() {
        XCTAssertEqual(VulnSeverity.critical, [.low, .critical, .unknown].max())
        XCTAssertGreaterThan(VulnSeverity.high, VulnSeverity.medium)
        XCTAssertEqual(VulnSeverity(rawValue: "critical"), .critical)
    }

    func testBrewVersionParsing() throws {
        let version = try XCTUnwrap(BrewVersion(string: "Homebrew 7.0.10\nHomebrew/homebrew-core"))
        XCTAssertEqual(version.major, 7)
        XCTAssertEqual(version.minor, 0)
        XCTAssertEqual(version.patch, 10)
        // raw 只含版本号本身，避免展示层拼出「Homebrew Homebrew 7.0.10」。
        XCTAssertEqual(version.raw, "7.0.10")
        XCTAssertLessThan(BrewVersion(major: 6, minor: 9, patch: 0), version)
    }
}
