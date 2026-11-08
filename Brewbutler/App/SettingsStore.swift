import Foundation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let brewPath = "brewbutler.brewPathOverride"
        static let appearance = "brewbutler.appearance"
        static let menuBar = "brewbutler.showMenuBar"
        static let onboarding = "brewbutler.onboardingCompleted"
        static let notifyTasks = "brewbutler.notifyTasks"
        static let notifyUpdates = "brewbutler.notifyUpdates"
        static let notifyVulnerabilities = "brewbutler.notifyVulnerabilities"
        static let noInstallCleanup = "brewbutler.noInstallCleanup"
        static let greedyUpgrades = "brewbutler.greedyUpgrades"
        static let autoCheckUpdates = "brewbutler.autoCheckUpdates"
        static let lastAutoCheckAt = "brewbutler.lastAutoCheckAt"
        static let lastAutoCheckFailedAt = "brewbutler.lastAutoCheckFailedAt"
        static let injectNoAutoUpdateForReads = "brewbutler.injectNoAutoUpdateForReads"
        static let suppressEnvHints = "brewbutler.suppressEnvHints"
        static let proxy = "brewbutler.proxy"
        static let apiDomain = "brewbutler.apiDomain"
        static let bottleDomain = "brewbutler.bottleDomain"
        static let allowNoSudo = "brewbutler.allowNoSudo"
        static let allowNoSandboxCask = "brewbutler.allowNoSandboxCask"
        static let allowNoAppManagementPrompt = "brewbutler.allowNoAppManagementPrompt"
        static let retention = "brewbutler.logRetentionDays"
        static let localTasks = "brewbutler.localTaskCount"
        static let localScans = "brewbutler.localScanCount"
        static let localLastScan = "brewbutler.localLastScan"
        static let lastExport = "brewbutler.lastBrewfileExport"
        static let lastUpstreamSyncAt = "brewbutler.lastUpstreamSyncAt"
        static let showInspector = "brewbutler.showInspector"
        static let hasSeenShortcutTip = "brewbutler.hasSeenShortcutTip"
        static let recentSearches = "brewbutler.recentSearches"
    }

    private let defaults: UserDefaults

    var brewPathOverride: String {
        didSet { defaults.set(brewPathOverride, forKey: Key.brewPath) }
    }

    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    var showMenuBarExtra: Bool {
        didSet { defaults.set(showMenuBarExtra, forKey: Key.menuBar) }
    }

    var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboarding) }
    }

    var notifyOnTaskCompletion: Bool {
        didSet { defaults.set(notifyOnTaskCompletion, forKey: Key.notifyTasks) }
    }

    var notifyOnUpdates: Bool {
        didSet { defaults.set(notifyOnUpdates, forKey: Key.notifyUpdates) }
    }

    var notifyOnVulnerabilities: Bool {
        didSet { defaults.set(notifyOnVulnerabilities, forKey: Key.notifyVulnerabilities) }
    }

    var noInstallCleanup: Bool {
        didSet { defaults.set(noInstallCleanup, forKey: Key.noInstallCleanup) }
    }

    /// Include auto_updates / :latest casks in outdated detection and upgrades.
    var greedyUpgrades: Bool {
        didSet { defaults.set(greedyUpgrades, forKey: Key.greedyUpgrades) }
    }

    /// 启动与每 24 小时静默检查一次可更新项；离线失败不打扰用户。
    var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: Key.autoCheckUpdates) }
    }

    /// 最近一次自动检查（含启动检查）完成时间；与手动「检查更新」分开记录。
    var lastAutoCheckAt: Date? {
        didSet {
            if let lastAutoCheckAt {
                defaults.set(lastAutoCheckAt, forKey: Key.lastAutoCheckAt)
            } else {
                defaults.removeObject(forKey: Key.lastAutoCheckAt)
            }
        }
    }

    /// 最近一次自动检查失败的时间（P1-10）。成功时清空，供更新页如实说明
    /// 「显示的是上次成功结果」；不与 lastAutoCheckAt 混写。
    var lastAutoCheckFailedAt: Date? {
        didSet {
            if let lastAutoCheckFailedAt {
                defaults.set(lastAutoCheckFailedAt, forKey: Key.lastAutoCheckFailedAt)
            } else {
                defaults.removeObject(forKey: Key.lastAutoCheckFailedAt)
            }
        }
    }

    /// 只读 scope 注入 HOMEBREW_NO_AUTO_UPDATE，避免查询偷偷触发 brew update。
    var injectNoAutoUpdateForReads: Bool {
        didSet { defaults.set(injectNoAutoUpdateForReads, forKey: Key.injectNoAutoUpdateForReads) }
    }

    /// 注入 HOMEBREW_NO_ENV_HINTS，隐藏 brew 的 "next steps" 提示。
    var suppressEnvHints: Bool {
        didSet { defaults.set(suppressEnvHints, forKey: Key.suppressEnvHints) }
    }

    var proxyURL: String {
        didSet { defaults.set(proxyURL, forKey: Key.proxy) }
    }

    var apiDomain: String {
        didSet { defaults.set(apiDomain, forKey: Key.apiDomain) }
    }

    var bottleDomain: String {
        didSet { defaults.set(bottleDomain, forKey: Key.bottleDomain) }
    }

    var allowNoSudo: Bool {
        didSet { defaults.set(allowNoSudo, forKey: Key.allowNoSudo) }
    }

    var allowNoSandboxCask: Bool {
        didSet { defaults.set(allowNoSandboxCask, forKey: Key.allowNoSandboxCask) }
    }

    var allowNoAppManagementPrompt: Bool {
        didSet { defaults.set(allowNoAppManagementPrompt, forKey: Key.allowNoAppManagementPrompt) }
    }

    var logRetentionDays: Int {
        didSet { defaults.set(logRetentionDays, forKey: Key.retention) }
    }

    var lastBrewfileExport: String {
        didSet { defaults.set(lastBrewfileExport, forKey: Key.lastExport) }
    }

    /// O-01：最近一次 `brew update-if-needed` 成功同步上游索引的时间。
    /// 与「本机检查于 X」分开记录（后者是 outdated 的读取时间）。
    var lastUpstreamSyncAt: Date? {
        didSet {
            if let lastUpstreamSyncAt {
                defaults.set(lastUpstreamSyncAt, forKey: Key.lastUpstreamSyncAt)
            } else {
                defaults.removeObject(forKey: Key.lastUpstreamSyncAt)
            }
        }
    }

    /// O-08：检查器开关偏好。打开包详情不再强制弹出检查器。
    var showInspector: Bool {
        didSet { defaults.set(showInspector, forKey: Key.showInspector) }
    }

    /// O-05：v2 快捷键调整的一次性提示是否已展示过。
    var hasSeenShortcutTip: Bool {
        didSet { defaults.set(hasSeenShortcutTip, forKey: Key.hasSeenShortcutTip) }
    }

    /// O-10：发现页最近搜索。只存本地、可清除、不进诊断包。
    private(set) var recentSearches: [String] {
        didSet { defaults.set(recentSearches, forKey: Key.recentSearches) }
    }

    static let maxRecentSearches = 6

    func recordRecentSearch(_ query: String) {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return }
        var next = recentSearches.filter { $0 != needle }
        next.insert(needle, at: 0)
        recentSearches = Array(next.prefix(Self.maxRecentSearches))
    }

    func clearRecentSearches() {
        recentSearches = []
    }

    private(set) var localTaskCount: Int
    private(set) var localScanCount: Int
    private(set) var localLastScanAt: Date?

    /// v1.0 is fixed off; there is deliberately no setter and no UI to enable it.
    let telemetryEnabled = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.brewPathOverride = defaults.string(forKey: Key.brewPath) ?? ""
        let appearanceRaw = defaults.string(forKey: Key.appearance) ?? AppearanceMode.system.rawValue
        self.appearance = AppearanceMode(rawValue: appearanceRaw) ?? .system
        self.showMenuBarExtra = defaults.object(forKey: Key.menuBar) as? Bool ?? true
        self.onboardingCompleted = defaults.bool(forKey: Key.onboarding)
        self.notifyOnTaskCompletion = defaults.object(forKey: Key.notifyTasks) as? Bool ?? true
        self.notifyOnUpdates = defaults.object(forKey: Key.notifyUpdates) as? Bool ?? true
        self.notifyOnVulnerabilities = defaults.object(forKey: Key.notifyVulnerabilities) as? Bool ?? true
        self.noInstallCleanup = defaults.object(forKey: Key.noInstallCleanup) as? Bool ?? true
        self.greedyUpgrades = defaults.object(forKey: Key.greedyUpgrades) as? Bool ?? false
        self.autoCheckUpdates = defaults.object(forKey: Key.autoCheckUpdates) as? Bool ?? true
        self.lastAutoCheckAt = defaults.object(forKey: Key.lastAutoCheckAt) as? Date
        self.lastAutoCheckFailedAt = defaults.object(forKey: Key.lastAutoCheckFailedAt) as? Date
        self.injectNoAutoUpdateForReads = defaults.object(forKey: Key.injectNoAutoUpdateForReads) as? Bool ?? true
        self.suppressEnvHints = defaults.object(forKey: Key.suppressEnvHints) as? Bool ?? true
        self.proxyURL = defaults.string(forKey: Key.proxy) ?? ""
        self.apiDomain = defaults.string(forKey: Key.apiDomain) ?? ""
        self.bottleDomain = defaults.string(forKey: Key.bottleDomain) ?? ""
        self.allowNoSudo = defaults.bool(forKey: Key.allowNoSudo)
        self.allowNoSandboxCask = defaults.bool(forKey: Key.allowNoSandboxCask)
        self.allowNoAppManagementPrompt = defaults.bool(forKey: Key.allowNoAppManagementPrompt)
        self.logRetentionDays = defaults.object(forKey: Key.retention) as? Int ?? 7
        self.localTaskCount = defaults.integer(forKey: Key.localTasks)
        self.localScanCount = defaults.integer(forKey: Key.localScans)
        self.localLastScanAt = defaults.object(forKey: Key.localLastScan) as? Date
        self.lastBrewfileExport = defaults.string(forKey: Key.lastExport) ?? ""
        self.lastUpstreamSyncAt = defaults.object(forKey: Key.lastUpstreamSyncAt) as? Date
        self.showInspector = defaults.object(forKey: Key.showInspector) as? Bool ?? true
        self.hasSeenShortcutTip = defaults.bool(forKey: Key.hasSeenShortcutTip)
        self.recentSearches = defaults.stringArray(forKey: Key.recentSearches) ?? []
    }

    var environmentSettings: BrewEnvironmentSettings {
        BrewEnvironmentSettings(
            injectNoAutoUpdateForReads: injectNoAutoUpdateForReads,
            noInstallCleanup: noInstallCleanup,
            suppressEnvHints: suppressEnvHints,
            proxyURL: proxyURL.nilIfEmpty,
            apiDomain: apiDomain.nilIfEmpty,
            bottleDomain: bottleDomain.nilIfEmpty,
            allowNoSudo: allowNoSudo,
            allowNoSandboxCask: allowNoSandboxCask,
            allowNoAppManagementPrompt: allowNoAppManagementPrompt
        )
    }

    func recordTask() {
        localTaskCount += 1
        defaults.set(localTaskCount, forKey: Key.localTasks)
    }

    func recordScan(at date: Date = Date()) {
        localScanCount += 1
        localLastScanAt = date
        defaults.set(localScanCount, forKey: Key.localScans)
        defaults.set(date, forKey: Key.localLastScan)
    }

    func clearLocalStatistics() {
        localTaskCount = 0
        localScanCount = 0
        localLastScanAt = nil
        defaults.set(0, forKey: Key.localTasks)
        defaults.set(0, forKey: Key.localScans)
        defaults.removeObject(forKey: Key.localLastScan)
    }

    func resetOnboarding() {
        onboardingCompleted = false
    }
}
