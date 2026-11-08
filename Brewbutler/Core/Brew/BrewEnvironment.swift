import Foundation

public struct BrewEnvironmentSettings: Codable, Hashable, Sendable {
    public var injectNoAutoUpdateForReads: Bool
    public var noInstallCleanup: Bool
    /// Suppress brew's "next steps" hints (HOMEBREW_NO_ENV_HINTS). UI-toggleable;
    /// on by default because the app renders its own guidance.
    public var suppressEnvHints: Bool
    public var proxyURL: String?
    public var apiDomain: String?
    public var bottleDomain: String?
    public var allowNoSudo: Bool
    public var allowNoSandboxCask: Bool
    public var allowNoAppManagementPrompt: Bool

    public init(
        injectNoAutoUpdateForReads: Bool = true,
        noInstallCleanup: Bool = true,
        suppressEnvHints: Bool = true,
        proxyURL: String? = nil,
        apiDomain: String? = nil,
        bottleDomain: String? = nil,
        allowNoSudo: Bool = false,
        allowNoSandboxCask: Bool = false,
        allowNoAppManagementPrompt: Bool = false
    ) {
        self.injectNoAutoUpdateForReads = injectNoAutoUpdateForReads
        self.noInstallCleanup = noInstallCleanup
        self.suppressEnvHints = suppressEnvHints
        self.proxyURL = proxyURL
        self.apiDomain = apiDomain
        self.bottleDomain = bottleDomain
        self.allowNoSudo = allowNoSudo
        self.allowNoSandboxCask = allowNoSandboxCask
        self.allowNoAppManagementPrompt = allowNoAppManagementPrompt
    }
}

public enum BrewEnvironmentScope: Sendable {
    case readOnly
    case mutating
}

public struct BrewEnvironment: Sendable {
    public let installation: BrewInstallation
    public let settings: BrewEnvironmentSettings

    public init(installation: BrewInstallation, settings: BrewEnvironmentSettings = BrewEnvironmentSettings()) {
        self.installation = installation
        self.settings = settings
    }

    public var executable: URL { installation.executableURL }

    public var injectedVariables: [String: String] {
        var values: [String: String] = [
            "HOMEBREW_NO_COLOR": "1",
            "HOMEBREW_NO_EMOJI": "1",
            "HOMEBREW_NO_ANALYTICS": "1"
        ]
        if settings.suppressEnvHints {
            values["HOMEBREW_NO_ENV_HINTS"] = "1"
        }
        if settings.injectNoAutoUpdateForReads {
            values["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        }
        if settings.noInstallCleanup {
            values["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        }
        if let proxy = settings.proxyURL, !proxy.isEmpty {
            values["HTTPS_PROXY"] = proxy
            values["HTTP_PROXY"] = proxy
            values["ALL_PROXY"] = proxy
        }
        if let api = settings.apiDomain, BrewArgumentValidator.isSafeWebURL(api) {
            values["HOMEBREW_API_DOMAIN"] = api
        }
        if let bottle = settings.bottleDomain, BrewArgumentValidator.isSafeWebURL(bottle) {
            values["HOMEBREW_BOTTLE_DOMAIN"] = bottle
        }
        if settings.allowNoSudo { values["HOMEBREW_NO_SUDO"] = "1" }
        if settings.allowNoSandboxCask { values["HOMEBREW_NO_SANDBOX_CASK"] = "1" }
        if settings.allowNoAppManagementPrompt { values["HOMEBREW_NO_APP_MANAGEMENT_PERMISSIONS_PROMPT"] = "1" }
        return values
    }

    public func environment(for scope: BrewEnvironmentScope) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        // Drop inherited HOMEBREW_* so a shell wrapper cannot silently change
        // behaviour behind the app's back; the app injects its own deterministic set.
        for key in environment.keys where key.hasPrefix("HOMEBREW_") {
            environment.removeValue(forKey: key)
        }
        for (key, value) in injectedVariables { environment[key] = value }
        if scope == .mutating {
            environment.removeValue(forKey: "HOMEBREW_NO_AUTO_UPDATE")
        } else if settings.injectNoAutoUpdateForReads {
            environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        }
        environment["PATH"] = installation.binPaths.joined(separator: ":")
        environment["TERM"] = "xterm-256color"
        environment["HOMEBREW_PREFIX"] = installation.prefix
        return environment
    }

    /// Human-readable injection list for the diagnostics pane / export.
    public func diagnosticsInjectionList() -> [String] {
        injectedVariables
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
    }
}
