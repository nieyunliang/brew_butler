import AppKit
import Foundation
import Observation
import SwiftUI
import UserNotifications

// MARK: - Navigation

/// 一级导航（ui-design.md v2.0.2 §3.2）。
///
/// 5 项：概览 / 更新 / 资料库 / 服务 / 维护。v1 的「发现」不是一级页面——它是
/// 工具栏搜索的结果页，覆盖在当前分区之上（`AppState.isDiscoverPresented`）；
/// 「设置」回到系统 `Settings` 窗口（⌘,）。
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case updates
    case library
    case services
    case maintenance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .updates: return "更新"
        case .library: return "资料库"
        case .services: return "服务"
        case .maintenance: return "维护"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "rectangle.grid.2x2"
        case .updates: return "arrow.down.circle"
        case .library: return "shippingbox"
        case .services: return "gearshape.2"
        case .maintenance: return "wrench.and.screwdriver"
        }
    }

    var shortcut: String {
        switch self {
        case .overview: return "⌘1"
        case .updates: return "⌘2"
        case .library: return "⌘3"
        case .services: return "⌘4"
        case .maintenance: return "⌘5"
        }
    }
}

enum DetailTab: String, CaseIterable, Identifiable {
    case overview
    case security
    case dependencies
    case dependents
    case files
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .security: return "安全"
        case .dependencies: return "依赖"
        case .dependents: return "被依赖"
        case .files: return "文件"
        case .history: return "历史"
        }
    }
}

enum InstalledFilter: String, CaseIterable, Identifiable {
    case all
    case formula
    case cask
    case outdated
    case pinned
    case vulnerable
    case manual
    case kegOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .formula: return "formula"
        case .cask: return "cask"
        case .outdated: return "可更新"
        case .pinned: return "已锁定"
        case .vulnerable: return "有漏洞"
        case .manual: return "手动安装"
        case .kegOnly: return "keg-only"
        }
    }
}

enum PackageSort: String, CaseIterable, Identifiable {
    case name
    case size
    case installedAt
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "按名称"
        case .size: return "按体积"
        case .installedAt: return "按安装时间"
        case .status: return "按状态"
        }
    }
}

enum UpdateFilter: String, CaseIterable, Identifiable {
    case all
    case security
    case formula
    case cask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .security: return "安全"
        case .formula: return "formula"
        case .cask: return "cask"
        }
    }
}

// MARK: - Small state containers

struct DiskUsage: Equatable {
    var cellarBytes: Int64?
    var cacheBytes: Int64?
    var caskroomBytes: Int64?
    var computedAt: Date?
    var isComputing = false
}

struct MaintenanceState {
    var cleanupPreview: CleanupPreview?
    var cleanupError: String?
    var cleanupLoading = false
    /// `brew cleanup -n` 的原始输出与退出码；解析失败时 UI 必须展示原文并禁用执行。
    var cleanupRawText: String?
    var cleanupExitCode: Int32?
    var cleanupPreviewFailed = false

    var doctorReport: DoctorReport?
    var doctorExitCode: Int32?
    var doctorError: String?
    var doctorLoading = false

    var missingReport: MissingReport?
    var missingError: String?
    var missingExitCode: Int32?
    var missingLoading = false

    var autoremovePreview: AutoremovePreview?
    var autoremoveError: String?
    var autoremoveLoading = false

    var loadedAt: Date?
}

struct PackageDetailState {
    var packageID: String
    var path: String?
    var sizeBytes: Int64?
    var files: [String] = []
    var changeLog: String?
    var isLoading = true
    var error: String?
}

struct DiscoverState {
    var query = ""
    var kind: PackageSnapshot.Kind?
    var results: [BrewSearchResult] = []
    var isSearching = false
    var error: String?
    var usingCache = false
    var cacheDate: Date?
    /// 缓存超过 24h TTL 仍会展示，但必须标注「可能过期」并给强制刷新。
    var cacheIsStale = false
    /// 网络失败后回落到本地已安装索引（没有缓存时间戳）。
    var cacheIsLocalOnly = false
    var hasSearched = false
}

struct CleanupRequest: Identifiable {
    let id = UUID()
    var preview: CleanupPreview
}

struct AutoremoveRequest: Identifiable {
    let id = UUID()
    var preview: AutoremovePreview
}

/// 资料库的组合筛选（O-06）：scope 单选 + 「筛选」菜单的附加条件。
/// tap 为 nil 表示不限制 tap；`activeCount` 用于按钮上的「筛选 2」。
struct LibraryFilterOptions: Equatable {
    var scope: InstalledFilter = .all
    var pinnedOnly = false
    var manualOnly = false
    var kegOnlyOnly = false
    var tap: String?

    var activeCount: Int {
        var count = 0
        if pinnedOnly { count += 1 }
        if manualOnly { count += 1 }
        if kegOnlyOnly { count += 1 }
        if tap != nil { count += 1 }
        return count
    }

    var hasExtraFilters: Bool { activeCount > 0 }
}

struct InstallTarget: Identifiable {
    var name: String
    var kind: PackageSnapshot.Kind

    var id: String { "\(kind.rawValue):\(name)" }
}

/// 逐包体积的后台计算状态。InstalledView 用它渲染「数字 / 计算中 / —」三态。
enum PackageDiskUsageState: Equatable {
    case idle
    case computing(done: Int, total: Int)
    case finished
}

/// Brewfile 导入前的静态预览：将安装 / 已安装 / tap / 不支持项。
/// 只解析文本，不执行任何 brew 命令；执行仍走 `performBrewfileImport(url:)`。
struct BrewfileImportPreview: Identifiable, Equatable {
    struct Item: Identifiable, Equatable {
        enum Kind: String, Equatable {
            case formula, cask, tap, unsupported
        }

        var kind: Kind
        var name: String
        /// formula/cask 依据当前索引判断；tap 与不支持项恒为 false。
        var isInstalled: Bool

        var id: String { "\(kind.rawValue):\(name)" }
    }

    var url: URL
    var items: [Item]
    var duplicates: [String]
    var parseError: String?

    var id: String { url.path }
    var installable: [Item] { items.filter { $0.kind == .formula || $0.kind == .cask }.filter { !$0.isInstalled } }
    var alreadyInstalled: [Item] { items.filter { ($0.kind == .formula || $0.kind == .cask) && $0.isInstalled } }
    var taps: [Item] { items.filter { $0.kind == .tap } }
    var unsupported: [Item] { items.filter { $0.kind == .unsupported } }
    var isEmpty: Bool { items.isEmpty }
}

/// launchd plist 中声明的日志路径；两者都没有时 UI 必须明确说明。
struct ServiceLogPaths: Equatable {
    var standardOut: String?
    var standardError: String?
    var hasAny: Bool { standardOut != nil || standardError != nil }
}

/// Pre-flight description of a batch update. Built by
/// `AppState.requestBatchUpdate(_:)`, presented by `BatchUpdateSheet`, and
/// executed by `AppState.confirmBatchUpdate()` so the confirmation always shows
/// the same package set the queue will receive.
struct BatchUpdatePlan: Identifiable {
    enum Scope: Hashable, Sendable {
        case all
        case selected([String])   // PackageSnapshot.id
        case vulnerable
    }

    let id = UUID()
    let scope: Scope
    let title: String
    let packageIDs: [String]
    let packageNames: [String]
    let formulaCount: Int
    let caskCount: Int
    let skippedPinned: [String]
    let skippedActive: [String]
    /// Non-nil disables the confirm button (e.g. read-only mode). Callers
    /// normally surface this as a toast instead of presenting the sheet.
    let emptyReason: String?
}

/// User choices for the diagnostics export. Both flags default to the privacy
/// preserving value; `AppState.diagnosticsText(_:)` is the single source of
/// truth for what the file contains.
struct DiagnosticsExportPlan: Identifiable {
    let id = UUID()
    var includePackages = false
    var includePaths = false
}

/// A-12：漏洞扫描进度。`total` 只统计可被 OSV 映射的 formula（A-11 口径），
/// 扫描结束后 UI 用它替换「已用时间」，避免显示 0/0。
struct ScanProgress: Equatable {
    var checked: Int
    var total: Int
}

/// C-11：只读升级预览（`brew upgrade --dry-run`）。旧实现把它塞进串行变更
/// 队列，预览会挡住真正的安装/升级；现在直接以只读 scope 执行。
struct UpgradePreview: Equatable {
    var name: String
    var kind: PackageSnapshot.Kind
    var output: String
    var error: String?
    var isRunning: Bool
}

// MARK: - App state

@MainActor
@Observable
final class AppState {
    let settings: SettingsStore
    let tasks: TaskQueueStore

    // Navigation
    var section: AppSection = .overview
    var selectedPackageID: String?
    var detailTab: DetailTab = .overview
    /// O-08：检查器开关写进 SettingsStore，打开另一个包时保持用户上次的选择。
    var showInspector: Bool {
        get { settings.showInspector }
        set { settings.showInspector = newValue }
    }
    var showCommandPalette = false
    /// 工具栏全局搜索（⌘F）。输入只驱动「在 Homebrew 中搜索」，回车进入发现页；
    /// 逐页过滤在页面迁移时接到同一份文本上（ui-design §3.3）。
    var searchText = ""
    /// 让工具栏搜索框取焦点的递增请求（命令层无法直接持有 `@FocusState`）。
    var searchFocusRequest = 0
    /// 发现页当前是否覆盖在分区之上（规范 §3.2：发现不是一级导航）。
    var isDiscoverPresented = false
    var showOnboarding: Bool
    var onboardingStep = 0
    /// 跨页意图：概览指标环等入口预置资料库的 scope；InstalledView 读取后置 nil。
    var pendingLibraryScope: InstalledFilter?

    // Environment
    var installation: BrewInstallation?
    var isLocatingBrew = false
    var brewError: String?
    /// 设置页 brew 路径的「就地错误」：失败时保留输入并说明原因，而不是静默回滚。
    var brewPathError: String?
    var isReadOnly: Bool { installation?.isReadOnly ?? false }

    /// 只读 / 降级原因，供全局横幅（A-06）展示；nil 表示没有额外限制。
    var capabilityNotice: String? {
        guard let installation else { return nil }
        if installation.isReadOnly {
            return "只读模式：Homebrew \(installation.version?.raw ?? "版本未知") 低于 7.0 支持范围，变更操作已禁用。"
        }
        if installation.capabilities.isDegraded {
            return "部分能力不可用：\(installation.capabilities.degradedReasons.joined(separator: "；"))"
        }
        return nil
    }

    // Package index
    var index = PackageIndex(packages: [])
    var isRefreshing = false
    var lastRefreshAt: Date?
    var refreshError: String?

    /// O-01：最近一次成功同步上游索引的时间（持久化，跨启动保留）。
    var lastUpstreamSyncAt: Date? { settings.lastUpstreamSyncAt }
    var usesCachedIndex = false
    var indexSourceNote: String?
    /// Non-nil when the last `brew outdated` read failed; the UI shows a
    /// "showing last known data" banner instead of "all up to date".
    var outdatedRefreshError: String?
    var outdatedIsCached = false
    var outdatedFetchedAt: Date?
    /// C-12：最近一次自动检查完成时间（SettingsStore 持久化），供更新页展示。
    var lastAutoCheckAt: Date? { settings.lastAutoCheckAt }
    /// P1-10：最近一次自动检查失败的时间；与成功时间分开，UI 不再混为一谈。
    var lastAutoCheckFailedAt: Date? { settings.lastAutoCheckFailedAt }
    /// Aggregated result of the last batch update; presented as a sheet.
    var batchSummary: TaskBatchSummary?

    // Vulnerabilities
    var vulnReport: VulnReport?
    /// 漏洞报告对应的已安装快照哈希；用于 O-07「扫描可能已过时」判定。
    private(set) var vulnReportSnapshotHash: String?
    /// O-01：正在等待 `brew update-if-needed` 完成（任务岛显示「正在同步 Homebrew 索引」）。
    var isSyncingUpstream = false
    /// O-01：最近一次同步上游失败/被取消的原因；成功后清空。
    var upstreamSyncError: String?
    var isScanning = false
    var scanStartedAt: Date?
    var scanError: String?
    var vulnReportIsCached = false
    /// A-12：扫描进度；nil 表示没有可展示的进度（未扫描/已清理）。
    var scanProgress: ScanProgress?

    // Disk & maintenance
    var diskUsage = DiskUsage()
    var maintenance = MaintenanceState()

    // Services
    var services: [BrewService] = []
    var servicesLoaded = false
    var servicesLoading = false
    var servicesError: String?

    // Detail
    var detail = PackageDetailState(packageID: "")

    // Discover
    var discover = DiscoverState()

    // UI feedback & sheets
    var toast: ToastMessage?
    /// E-14：FIFO toast 队列（同时最多显示 1 条，错误停留 5s）。
    private(set) var toastQueueCount = 0
    /// C-11：当前/最近一次升级预览。
    var upgradePreview: UpgradePreview?
    /// D-18：系统通知授权状态；通知开关据此启用/禁用。
    var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    /// A-19：探测到的多个 brew 安装（设置页单选）。
    var brewCandidates: [BrewCandidate] = []
    var isLoadingBrewCandidates = false
    var uninstallTarget: PackageSnapshot?
    var installTarget: InstallTarget?
    var cleanupRequest: CleanupRequest?
    var autoremoveRequest: AutoremoveRequest?
    var brewfileImportURL: URL?
    /// 导入前的静态预览；由 `chooseBrewfileToImport()` 填充，供 Brewfile 导入确认页使用。
    var brewfileImportPreview: BrewfileImportPreview?
    /// Brewfile 导出失败详情（退出码 + 首行错误），维护页就地展示。
    var brewfileExportError: String?
    /// 逐包体积（PackageSnapshot.id → 字节）。后台计算，UI 不应在主线程自行遍历磁盘。
    private(set) var packageDiskUsage: [String: Int64] = [:]
    private(set) var packageDiskUsageState: PackageDiskUsageState = .idle
    /// Non-nil presents the batch-update confirmation sheet (see §2.1 of the
    /// M1 fix plan). Confirm/cancel both clear it.
    var pendingBatchUpdate: BatchUpdatePlan?
    /// Non-nil presents the diagnostics export sheet (P0-08).
    var pendingDiagnosticsExport: DiagnosticsExportPlan?

    @ObservationIgnored private var client: BrewClient?
    @ObservationIgnored private let cache = DiskCache()
    @ObservationIgnored private var lastPayload: IndexCachePayload?
    @ObservationIgnored private var detailCache: [String: PackageDetailState] = [:]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var hasBootstrapped = false
    @ObservationIgnored private var searchGeneration = 0
    @ObservationIgnored private var isLoadingMaintenance = false
    @ObservationIgnored private var refreshQueued = false
    @ObservationIgnored private var lastNotifiedOutdatedCount: Int?
    @ObservationIgnored private var packageSizeTask: Task<Void, Never>?
    @ObservationIgnored private var upgradePreviewTask: Task<Void, Never>?
    @ObservationIgnored private var autoCheckTask: Task<Void, Never>?
    @ObservationIgnored private var toastQueue: [ToastMessage] = []

    private static let vulnTTL: TimeInterval = 24 * 60 * 60
    private static let searchTTL: TimeInterval = 24 * 60 * 60

    static var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (v?, b?) where b != v: return "\(v) (\(b))"
        case let (v?, _): return v
        default: return "未知"
        }
    }

    init(settings: SettingsStore, tasks: TaskQueueStore) {
        self.settings = settings
        self.tasks = tasks
        self.showOnboarding = !settings.onboardingCompleted
        tasks.onMutationFinished = { [weak self] in
            await self?.refreshIndex()
            await self?.loadServices()
            await self?.computeDiskUsage()
            self?.invalidateDetailCachesAfterMutation()
            self?.resetPackageDiskUsage()
        }
        tasks.onTaskFinished = { [weak self] record in
            self?.handleTaskFinished(record)
        }
        tasks.onBatchFinished = { [weak self] summary in
            guard let self else { return }
            self.batchSummary = summary
            Task { await self.refreshIndex() }
        }
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        // 日志保留策略不依赖 brew，先清理一次；之后设置页改动天数时会再次清理。
        pruneTaskLogs()
        await locateBrew(override: settings.brewPathOverride.nilIfEmpty)
        guard installation != nil else { return }
        loadCachedIndex()
        await refreshIndex()
        await refreshNotificationAuthorization()
        startAutoCheckTimer()
        await computeDiskUsage()
    }

    var selectedPackage: PackageSnapshot? {
        guard let selectedPackageID else { return nil }
        return index.packages.first { $0.id == selectedPackageID }
    }

    var windowTitle: String {
        if let selectedPackage {
            return "Brewbutler — \(selectedPackage.displayName)"
        }
        if isDiscoverPresented {
            return "Brewbutler — 发现"
        }
        return "Brewbutler — \(section.title)"
    }

    /// 从其它页面跳到资料库并预置 scope（例如概览「有已知漏洞」指标环）。
    /// 消费方（InstalledView）负责在 onAppear/task 中读取后置 nil。
    func openLibrary(scope: InstalledFilter) {
        pendingLibraryScope = scope
        openSection(.library)
    }

    func openSection(_ section: AppSection) {
        self.section = section
        selectedPackageID = nil
        isDiscoverPresented = false
        if section == .maintenance {
            Task { await loadMaintenanceIfNeeded() }
        } else if section == .services {
            Task { await loadServices() }
        }
    }

    /// ⌘[ 返回：先退二级（包详情 / 发现结果页），没有二级视图时什么都不做。
    var canNavigateBack: Bool {
        selectedPackageID != nil || isDiscoverPresented
    }

    func navigateBack() {
        if selectedPackageID != nil {
            closeDetail()
        } else if isDiscoverPresented {
            closeDiscover()
        }
    }

    /// ⌘F：命令层无法直接持有工具栏搜索框的 `@FocusState`，用递增请求通知视图取焦。
    func focusToolbarSearch() {
        searchFocusRequest += 1
    }

    /// 进入发现页（全局搜索结果）。`query` 非空时立即发起搜索。
    /// 发现页覆盖在分区之上，⌘[ / Esc 关闭后回到原分区。
    func openDiscover(query: String? = nil, kind: PackageSnapshot.Kind? = nil, search: Bool = true) {
        if let query {
            discover.query = query
            searchText = query
        }
        if let kind { discover.kind = kind }
        isDiscoverPresented = true
        selectedPackageID = nil
        if search, !discover.query.trimmed.isEmpty {
            searchDiscover()
        }
    }

    func closeDiscover() {
        isDiscoverPresented = false
        searchText = ""
    }

    func selectPackage(_ package: PackageSnapshot) {
        selectedPackageID = package.id
        detailTab = .overview
        // O-08：不再强制打开检查器；开关状态由 SettingsStore 记忆。
        loadDetail(for: package)
    }

    func closeDetail() {
        selectedPackageID = nil
    }

    // MARK: - Homebrew location

    @discardableResult
    func locateBrew(override: String?) async -> Bool {
        isLocatingBrew = true
        brewError = nil
        defer { isLocatingBrew = false }

        let result = await BrewLocator().locate(override: override)
        switch result {
        case .success(let found):
            installation = found
            rebuildClient()
            if found.isReadOnly {
                showToast("Homebrew \(found.version?.raw ?? "") 低于 v1.0 支持范围，已进入只读模式", kind: .info)
            }
            return true
        case .failure(let error):
            brewError = error.localizedDescription
            return false
        }
    }

    func applyBrewPath(_ path: String) async -> Bool {
        let trimmed = path.trimmed
        let previousOverride = settings.brewPathOverride
        let previousInstallation = installation
        brewPathError = nil
        settings.brewPathOverride = trimmed

        let success = await locateBrew(override: trimmed.nilIfEmpty)
        if !success {
            settings.brewPathOverride = previousOverride
            installation = previousInstallation
            rebuildClient()
            let message = "无法使用该路径：\(brewError ?? "未找到可用的 Homebrew")"
            brewError = message
            brewPathError = message
            return false
        }
        // P1-12：用户显式填写的路径必须真的被采用。locate 在 override 失败后会
        // 继续回退到固定路径；不校验的话，坏路径会被静默持久化，界面显示成功
        // 但实际仍用旧的 brew。
        if let desired = trimmed.nilIfEmpty,
           let foundPath = installation?.executablePath {
            let desiredURL = URL(fileURLWithPath: desired).standardizedFileURL
            let foundURL = URL(fileURLWithPath: foundPath).standardizedFileURL
            if foundURL != desiredURL {
                settings.brewPathOverride = previousOverride
                installation = previousInstallation
                rebuildClient()
                let message = "该路径不可用：实际可用的 Homebrew 位于 \(foundPath)。请修正路径或修复该安装。"
                brewError = message
                brewPathError = message
                return false
            }
        }
        brewPathError = nil
        cache.removeAll()
        detailCache.removeAll()
        index = PackageIndex(packages: [])
        lastPayload = nil
        vulnReport = nil
        usesCachedIndex = false
        resetPackageDiskUsage()
        await refreshIndex()
        return true
    }

    private func rebuildClient() {
        guard let installation else {
            client = nil
            tasks.client = nil
            return
        }
        let newClient = BrewClient(installation: installation, settings: settings.environmentSettings)
        client = newClient
        tasks.client = newClient
    }

    func applyEnvironmentSettings() {
        rebuildClient()
    }

    // MARK: - Index refresh

    private var indexCacheKey: String {
        "index-\(installation?.executablePath ?? "unresolved")"
    }

    private struct IndexCachePayload: Codable {
        var info: BrewInfoResponse
        var outdated: BrewOutdatedResponse?
        var listVersions: BrewListVersionsResponse?
        var fetchedAt: Date
        var outdatedFetchedAt: Date?
    }

    private struct VulnCachePayload: Codable {
        var report: VulnReport
        var snapshotHash: String
        var savedAt: Date
    }

    private struct SearchCachePayload: Codable {
        var results: [CachedSearchResult]
        var savedAt: Date
    }

    private struct CachedSearchResult: Codable {
        var name: String
        var summary: String
        var kind: String
    }

    func refreshIndex() async {
        guard let client else { return }
        // Coalesce overlapping refresh requests (mutation completion + manual
        // refresh) instead of silently dropping the later one.
        guard !isRefreshing else {
            refreshQueued = true
            return
        }
        isRefreshing = true
        refreshError = nil
        defer {
            isRefreshing = false
            if refreshQueued {
                refreshQueued = false
                Task { await self.refreshIndex() }
            }
        }

        do {
            let info = try await client.infoInstalled()
            var outdated: BrewOutdatedResponse?
            var outdatedError: String?
            var fetchedAt = Date()
            do {
                outdated = try await client.outdated(greedy: settings.greedyUpgrades)
                outdatedFetchedAt = fetchedAt
                outdatedIsCached = false
                outdatedRefreshError = nil
            } catch {
                // A failed outdated read must never look like "0 updates".
                // Reuse the last known payload (memory first, then disk) and
                // surface the failure so the UI can label it as cached.
                let previousPayload = lastPayload
                    ?? cache.load(IndexCachePayload.self, key: indexCacheKey)?.value
                let fallback = previousPayload?.outdated
                outdated = fallback
                outdatedError = (error as? BrewCommandError)?.diagnosticText ?? error.localizedDescription
                outdatedRefreshError = outdatedError
                outdatedIsCached = fallback != nil
                if let previous = previousPayload?.outdatedFetchedAt ?? previousPayload?.fetchedAt {
                    fetchedAt = previous
                }
                outdatedFetchedAt = fallback == nil ? nil : fetchedAt
            }
            let listVersions = installation?.capabilities.listVersionsJSON == true
                ? try? await client.listVersions()
                : nil

            let payload = IndexCachePayload(
                info: info,
                outdated: outdated,
                listVersions: listVersions,
                fetchedAt: Date(),
                outdatedFetchedAt: outdatedFetchedAt
            )
            lastPayload = payload
            cache.save(payload, key: indexCacheKey, savedAt: payload.fetchedAt)

            let preliminary = PackageIndex.build(
                info: info,
                outdated: outdated,
                vulnReport: nil,
                listVersions: listVersions
            )
            let report = cachedVulnerabilityReport(snapshotHash: preliminary.snapshotHash)
            vulnReport = report
            vulnReportSnapshotHash = report == nil ? nil : preliminary.snapshotHash
            vulnReportIsCached = report != nil
            index = PackageIndex.build(
                info: info,
                outdated: outdated,
                vulnReport: report,
                listVersions: listVersions,
                fetchedAt: payload.fetchedAt
            )
            lastRefreshAt = payload.fetchedAt
            usesCachedIndex = false
            resetPackageDiskUsage()
            if outdatedError == nil {
                indexSourceNote = nil
                // P1-10：手动「检查更新」不写自动检查时间戳——那个字段的语义
                // 是「上一次自动检查」，混写会让失败/手动都显示成「刚刚检查」。
                notifyIfNewUpdates()
            }
        } catch {
            usesCachedIndex = true
            indexSourceNote = "无法刷新索引：\(error.localizedDescription)"
            refreshError = (error as? BrewCommandError)?.diagnosticText ?? error.localizedDescription
            if index.packages.isEmpty {
                loadCachedIndex()
            }
        }
    }

    /// O-01：用户按一次「检查更新」（⌘R / 页头 / 菜单栏 / 命令面板）：
    /// 先 `brew update-if-needed`（变更队列，排在任何正在执行的变更之后），
    /// 完成后再跑只读的 `outdated`；离线或失败时不阻断，照常刷新并给出提示。
    /// 自动检查不走这里（保持只读，不在用户无感知时写 tap/缓存）。
    func checkUpdates() async {
        guard installation != nil else {
            await refreshIndex()
            return
        }
        let canSync = installation?.capabilities.updateIfNeeded == true && !isReadOnly
        guard canSync else {
            await refreshIndex()
            return
        }
        guard !tasks.hasActiveDedupKey("updateIndex") else { return }
        isSyncingUpstream = true
        upstreamSyncError = nil
        updateHomebrewIndex()
    }

    private func loadCachedIndex() {
        guard let cached = cache.load(IndexCachePayload.self, key: indexCacheKey) else { return }
        lastPayload = cached.value
        let preliminary = PackageIndex.build(
            info: cached.value.info,
            outdated: cached.value.outdated,
            vulnReport: nil,
            listVersions: cached.value.listVersions
        )
        let report = cachedVulnerabilityReport(snapshotHash: preliminary.snapshotHash)
        vulnReport = report
        vulnReportSnapshotHash = report == nil ? nil : preliminary.snapshotHash
        vulnReportIsCached = report != nil
        index = PackageIndex.build(
            info: cached.value.info,
            outdated: cached.value.outdated,
            vulnReport: report,
            listVersions: cached.value.listVersions,
            fetchedAt: cached.value.fetchedAt
        )
        lastRefreshAt = cached.value.fetchedAt
        usesCachedIndex = true
        indexSourceNote = "显示 \(cached.value.fetchedAt.relativeText)的缓存"
        outdatedIsCached = cached.value.outdated != nil
        outdatedFetchedAt = cached.value.outdatedFetchedAt
    }

    private func notifyIfNewUpdates() {
        let count = index.outdated.count
        defer { lastNotifiedOutdatedCount = count }
        guard settings.notifyOnUpdates else { return }
        guard let previous = lastNotifiedOutdatedCount, count > previous else { return }
        let security = index.securityUpdates.count
        Task {
            await NotificationService.post(
                title: "有 \(count) 个可用更新",
                body: security > 0 ? "其中 \(security) 个与已知漏洞相关。" : "打开更新页查看。"
            )
        }
    }

    // MARK: - Vulnerability scan

    /// A-11：分母只算可扫描的 formula；cask / 第三方 tap 单列说明，不出现
    /// 「覆盖 36/0」这类误导性比例。
    var scannableFormulaCount: Int {
        index.packages.filter { $0.kind == .formula }.count
    }

    var caskCount: Int {
        index.packages.filter { $0.kind == .cask }.count
    }

    var vulnerabilityCoverageText: String {
        guard let vulnReport else { return "扫描未知" }
        let total = scannableFormulaCount
        var parts: [String] = []
        if total == 0 {
            parts.append("未安装可扫描的 formula")
        } else {
            let checked = min(max(vulnReport.checked, 0), total)
            parts.append("覆盖 \(checked)/\(total) 个 formula")
            let uncovered = total - checked
            if uncovered > 0 { parts.append("\(uncovered) 个未覆盖") }
        }
        if caskCount > 0 {
            parts.append("\(caskCount) 个 cask 不在 OSV 映射范围")
        }
        if !vulnReport.skippedFormulae.isEmpty {
            parts.append("跳过 \(vulnReport.skippedFormulae.count) 个")
        }
        return parts.joined(separator: " · ")
    }

    /// D-20：最近一次扫描中因 untrusted tap 被跳过的包名。
    var untrustedTapNames: [String] {
        guard let vulnReport else { return [] }
        return vulnReport.unscannedFormulae
            .filter { $0.value.localizedCaseInsensitiveContains("untrusted") }
            .map(\.key)
            .sorted()
    }

    /// O-07：上次扫描之后已安装快照发生变化 → 结果可能已过时。
    /// 只给提示，不自动扫描（ui-design §8：扫描只手动触发）。
    var scanIsStale: Bool {
        guard vulnReport != nil, let vulnReportSnapshotHash else { return false }
        return vulnReportSnapshotHash != index.snapshotHash
    }

    var vulnerabilityAffectedCount: Int {
        vulnReport?.affectedFormulaCount ?? 0
    }

    var vulnerabilityFixableCount: Int {
        vulnReport?.fixableFindingCount ?? 0
    }

    func scanVulnerabilities() {
        guard !isScanning else { return }
        guard let client else {
            showToast("Homebrew 尚未就绪，无法扫描", kind: .failure)
            return
        }
        guard installation?.capabilities.vulns == true else {
            showToast("当前 Homebrew 不支持 brew vulns，无法运行安全扫描", kind: .failure)
            return
        }
        guard !index.packages.isEmpty else {
            showToast("请先刷新已安装包列表", kind: .info)
            return
        }

        isScanning = true
        scanStartedAt = Date()
        scanError = nil
        let total = scannableFormulaCount
        scanProgress = ScanProgress(checked: 0, total: total)
        let snapshotHash = index.snapshotHash

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let report = try await client.vulns()
                self.apply(report: report, snapshotHash: snapshotHash)
                self.scanProgress = ScanProgress(
                    checked: min(report.checked, self.scannableFormulaCount),
                    total: self.scannableFormulaCount
                )
                self.settings.recordScan(at: report.scannedAt)
                self.vulnReportIsCached = false
                self.showToast("安全扫描完成：\(report.affectedFormulaCount) 个受影响包", kind: .info)
                if self.settings.notifyOnVulnerabilities, report.affectedFormulaCount > 0 {
                    Task {
                        await NotificationService.post(
                            title: "发现 \(report.affectedFormulaCount) 个有已知漏洞的包",
                            body: "\(report.fixableFindingCount) 个已有修复版本。打开安全页查看。"
                        )
                    }
                }
            } catch let error as BrewCommandError {
                if error.kind == .cancelled {
                    self.scanError = self.vulnReport == nil
                        ? "首次扫描已取消，暂无扫描结果。"
                        : "扫描已取消；保留了上次结果。"
                } else {
                    self.scanError = "\(error.kind.label)：\(error.firstErrorLine ?? error.localizedDescription)"
                }
            } catch is CancellationError {
                self.scanError = self.vulnReport == nil
                    ? "首次扫描已取消，暂无扫描结果。"
                    : "扫描已取消；保留了上次结果。"
            } catch {
                self.scanError = error.localizedDescription
            }
            if self.scanProgress?.checked == 0, self.vulnReport == nil {
                self.scanProgress = nil
            }
            self.isScanning = false
            self.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    private func apply(report: VulnReport, snapshotHash: String) {
        vulnReport = report
        vulnReportSnapshotHash = snapshotHash
        if let payload = lastPayload {
            index = PackageIndex.build(
                info: payload.info,
                outdated: payload.outdated,
                vulnReport: report,
                listVersions: payload.listVersions,
                fetchedAt: payload.fetchedAt
            )
        }
        let cachePayload = VulnCachePayload(report: report, snapshotHash: snapshotHash, savedAt: Date())
        cache.save(cachePayload, key: "vulns-\(snapshotHash)")
    }

    private func cachedVulnerabilityReport(snapshotHash: String) -> VulnReport? {
        guard let cached = cache.load(VulnCachePayload.self, key: "vulns-\(snapshotHash)") else { return nil }
        guard cached.value.snapshotHash == snapshotHash,
              Date().timeIntervalSince(cached.value.savedAt) < Self.vulnTTL else { return nil }
        return cached.value.report
    }

    // MARK: - Disk usage

    func computeDiskUsage() async {
        guard let client, let installation, !diskUsage.isComputing else { return }
        diskUsage.isComputing = true
        defer { diskUsage.isComputing = false }

        let cellar = try? await client.directorySize(path: installation.cellar)
        let cacheSize = installation.cache.isEmpty ? nil : try? await client.directorySize(path: installation.cache)
        let caskroom = FileManager.default.fileExists(atPath: client.caskroomPath)
            ? try? await client.directorySize(path: client.caskroomPath)
            : nil

        diskUsage = DiskUsage(
            cellarBytes: cellar,
            cacheBytes: cacheSize,
            caskroomBytes: caskroom,
            computedAt: Date(),
            isComputing: false
        )
    }

    // MARK: - Package disk usage

    /// 索引或安装状态变化后丢弃逐包体积，等待 InstalledView 再次触发计算。
    func resetPackageDiskUsage() {
        packageSizeTask?.cancel()
        packageSizeTask = nil
        packageDiskUsage = [:]
        packageDiskUsageState = .idle
    }

    /// 逐包体积：后台串行 `du`，不阻塞主线程，供 InstalledView 三态展示。
    func computePackageDiskUsage(force: Bool = false) {
        guard let client else { return }
        if !force, packageDiskUsageState == .finished { return }
        guard packageSizeTask == nil else { return }
        let packages = index.packages
        guard !packages.isEmpty else { return }
        let cellar = installation?.cellar
        let caskroom = client.caskroomPath
        packageDiskUsageState = .computing(done: 0, total: packages.count)
        packageSizeTask = Task { [weak self] in
            guard let self else { return }
            var results: [String: Int64] = [:]
            for (offset, package) in packages.enumerated() {
                if Task.isCancelled { break }
                var path: String?
                if package.kind == .cask {
                    path = "\(caskroom)/\(package.name)"
                } else if let cellar {
                    path = "\(cellar)/\(package.name)"
                }
                if let path, let size = try? await client.directorySize(path: path) {
                    results[package.id] = size
                }
                self.packageDiskUsage = results
                self.packageDiskUsageState = .computing(done: offset + 1, total: packages.count)
            }
            if !Task.isCancelled {
                self.packageDiskUsageState = .finished
            }
            self.packageSizeTask = nil
        }
    }

    func diskUsage(for package: PackageSnapshot) -> Int64? {
        packageDiskUsage[package.id]
    }

    // MARK: - Log retention

    /// 按设置的天数清理 `Library/Application Support/Brewbutler/Logs` 下的旧日志。
    /// 文件名格式 `yyyyMMdd-HHmmss-<id>.log`；只删除能解析出日期的文件。
    @discardableResult
    func pruneTaskLogs(announce: Bool = false) -> Int {
        let retention = max(1, settings.logRetentionDays)
        let cutoff = Date().addingTimeInterval(-Double(retention) * 24 * 60 * 60)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent("Brewbutler/Logs", isDirectory: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        var removed = 0
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for file in files where file.pathExtension == "log" {
            let name = file.deletingPathExtension().lastPathComponent
            guard let date = formatter.date(from: String(name.prefix(15))) else { continue }
            guard date < cutoff else { continue }
            if (try? FileManager.default.removeItem(at: file)) != nil {
                removed += 1
            }
        }
        if announce {
            self.showToast(
                removed > 0 ? "已清理 \(removed) 个旧日志文件" : "没有需要清理的旧日志",
                kind: .info
            )
        }
        return removed
    }

    // MARK: - Detail

    /// A successful mutation (卸载 / 升级 / 重装…) can change the files, size and
    /// path behind any package detail; drop the cache and reload the visible one.
    func invalidateDetailCachesAfterMutation() {
        detailCache.removeAll()
        if let selected = selectedPackage {
            loadDetail(for: selected, force: true)
        }
    }

    func loadDetail(for package: PackageSnapshot, force: Bool = false) {
        if !force, let cached = detailCache[package.id], !cached.isLoading {
            detail = cached
            return
        }
        guard let client else { return }

        var state = detailCache[package.id] ?? PackageDetailState(packageID: package.id)
        state.isLoading = true
        state.error = nil
        detail = state

        Task { [weak self] in
            guard let self else { return }
            let path = await client.packageInstallPath(for: package.name, kind: package.kind)
            let size: Int64?
            if FileManager.default.fileExists(atPath: path) {
                size = try? await client.directorySize(path: path)
            } else {
                size = nil
            }
            let files: [String]
            if package.kind == .formula {
                files = (try? await client.listFiles(for: package.name)) ?? []
            } else {
                files = []
            }
            let log: String?
            if package.kind == .formula, self.installation?.capabilities.log == true {
                log = try? await client.changeLog(for: package.name)
            } else {
                log = nil
            }

            var updated = PackageDetailState(
                packageID: package.id,
                path: path,
                sizeBytes: size,
                files: files,
                changeLog: log,
                isLoading: false,
                error: nil
            )
            if files.isEmpty, package.kind == .formula {
                updated.error = "无法读取文件列表（brew list 失败或没有可见文件）。"
            }
            self.detailCache[package.id] = updated
            if self.selectedPackageID == package.id {
                self.detail = updated
            }
        }
    }

    /// 资料库「在 Finder 中显示」的统一入口：先解析 brew 记录的包安装路径，
    /// 不在视图里推导 Cellar/Caskroom 规则（tap、版本前缀都可能不同）。
    /// 解析失败只提示，不猜路径。
    func revealPackageInstallPath(_ package: PackageSnapshot) async {
        if let cached = detailCache[package.id]?.path, !cached.isEmpty {
            revealInFinder(path: cached)
            return
        }
        guard let client else {
            showToast("Homebrew 尚未就绪，请稍后再试", kind: .failure)
            return
        }
        let path = await client.packageInstallPath(for: package.name, kind: package.kind)
        guard !path.isEmpty else {
            showToast("找不到 \(package.name) 的安装路径", kind: .info)
            return
        }
        revealInFinder(path: path)
    }

    func revealInFinder(path: String) {
        guard BrewArgumentValidator.isValidPath(path) else { return }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            showToast("路径不存在：\(path)", kind: .failure)
        }
    }

    func openHomepage(_ homepage: String?) {
        guard let homepage, BrewArgumentValidator.isSafeWebURL(homepage), let url = URL(string: homepage) else {
            showToast("主页地址无效，已阻止打开", kind: .failure)
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openOSV(_ vulnerability: Vulnerability) {
        guard let url = vulnerability.osvURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Task builders

    func enqueue(_ task: ChangeTask) {
        guard installation != nil, client != nil else {
            showToast("Homebrew 尚未就绪，请稍后再试", kind: .failure)
            return
        }
        guard !isReadOnly else {
            showToast("Homebrew 版本过低，当前为只读模式", kind: .failure)
            return
        }
        if let key = task.dedupKey, tasks.hasActiveDedupKey(key) {
            showToast("\(task.title) 已在队列中", kind: .info)
            return
        }
        if let id = task.packageID,
           tasks.records.contains(where: { $0.packageID == id && !$0.status.isTerminal }) {
            showToast("\(task.packageName ?? task.title) 已有任务在运行或排队中", kind: .info)
            return
        }
        tasks.enqueue(task)
        settings.recordTask()
    }

    func requestInstall(name: String, kind: PackageSnapshot.Kind) {
        guard BrewArgumentValidator.isValidPackageToken(name) else {
            showToast("包名不合法，已阻止执行", kind: .failure)
            return
        }
        if kind == .cask {
            installTarget = InstallTarget(name: name, kind: kind)
        } else {
            performInstall(name: name, kind: kind)
        }
    }

    func performInstall(name: String, kind: PackageSnapshot.Kind) {
        let task = ChangeTask(
            kind: .install,
            title: "安装 \(name)",
            commandText: kind == .cask ? "brew install --cask \(name)" : "brew install \(name)",
            packageID: "\(kind.rawValue):\(name)",
            packageName: name,
            packageKind: kind,
            run: { client, onEvent in
                try await client.install(name, kind: kind, onEvent: onEvent)
            }
        )
        enqueue(task)
    }

    func requestUninstall(_ package: PackageSnapshot) {
        uninstallTarget = package
    }

    func performUninstall(_ package: PackageSnapshot, zap: Bool) {
        let task = ChangeTask(
            kind: .uninstall,
            title: zap ? "卸载 \(package.name) 并删除关联文件" : "卸载 \(package.name)",
            commandText: "brew uninstall \(package.kind == .cask ? "--cask" : "--formula") \(zap ? "--zap " : "")\(package.name)",
            packageID: package.id,
            packageName: package.name,
            packageKind: package.kind,
            isDangerous: true,
            run: { client, onEvent in
                try await client.uninstall(package.name, kind: package.kind, zap: zap, onEvent: onEvent)
            }
        )
        enqueue(task)
    }

    func upgrade(_ entry: OutdatedEntry) {
        guard !entry.pinned else {
            showToast("\(entry.name) 已锁定，请先解锁", kind: .info)
            return
        }
        enqueue(makeUpgradeTask(entry, batchID: nil))
    }

    func upgrade(package: PackageSnapshot) {
        guard package.outdated else { return }
        upgrade(entry(from: package))
    }

    private func entry(from package: PackageSnapshot) -> OutdatedEntry {
        OutdatedEntry(
            id: package.id,
            name: package.name,
            kind: package.kind,
            installedVersions: package.installedVersion.map { [$0] } ?? [],
            currentVersion: package.stableVersion ?? "—",
            pinned: package.pinned,
            severity: package.vulnerabilitySeverity,
            finding: package.vulnerabilityFinding
        )
    }

    private func makeUpgradeTask(_ entry: OutdatedEntry, batchID: UUID?) -> ChangeTask {
        ChangeTask(
            kind: .upgrade,
            title: "更新 \(entry.name)",
            commandText: "brew upgrade \(entry.kind == .cask ? "--cask " : "")\(entry.name)",
            packageID: entry.id,
            packageName: entry.name,
            packageKind: entry.kind,
            verifyOutdated: true,
            batchID: batchID,
            fromVersionText: entry.installedText.isEmpty ? nil : entry.installedText,
            toVersionText: entry.currentVersion,
            run: { client, onEvent in
                try await client.upgrade(entry.name, kind: entry.kind, onEvent: onEvent)
            }
        )
    }

    func upgradeAll() {
        guard !isReadOnly else {
            showToast("Homebrew 版本过低，当前为只读模式", kind: .failure)
            return
        }
        guard !tasks.hasActiveDedupKey("upgradeAll") else {
            showToast("全部更新已在队列中", kind: .info)
            return
        }
        let pinnedSkipped = index.outdated.filter(\.pinned).count
        let batchID = tasks.beginBatch(title: "更新全部包", skipped: pinnedSkipped)
        let greedy = settings.greedyUpgrades
        var command = "brew upgrade"
        if greedy { command += " --greedy" }
        // Pinned packages are skipped by brew and would never advance, so they
        // are excluded from the progress rows (counted as skipped instead).
        let progressTargets = index.outdated.filter { !$0.pinned }.map { entry in
            ChangeTask.ProgressTarget(
                name: entry.name,
                kind: entry.kind.rawValue,
                fromVersion: entry.installedText.isEmpty ? nil : entry.installedText,
                toVersion: entry.currentVersion
            )
        }
        let task = ChangeTask(
            kind: .upgradeAll,
            title: "更新全部包",
            commandText: command,
            verifyOutdated: true,
            batchID: batchID,
            dedupKey: "upgradeAll",
            progressTargets: progressTargets,
            run: { client, onEvent in
                try await client.upgradeAll(greedy: greedy, onEvent: onEvent)
            }
        )
        enqueue(task)
    }

    /// Security-only quick path (PRD F4.8): `brew upgrade --vulnerable`.
    func upgradeVulnerable() {
        guard !isReadOnly else {
            showToast("Homebrew 版本过低，当前为只读模式", kind: .failure)
            return
        }
        guard !index.securityUpdates.isEmpty else {
            showToast("当前没有可更新的安全项", kind: .info)
            return
        }
        guard !tasks.hasActiveDedupKey("upgradeVulnerable") else {
            showToast("安全更新已在队列中", kind: .info)
            return
        }
        let batchID = tasks.beginBatch(title: "更新安全项")
        let greedy = settings.greedyUpgrades
        var command = "brew upgrade --vulnerable"
        if greedy { command += " --greedy" }
        let progressTargets = index.securityUpdates.filter { !$0.pinned }.map { entry in
            ChangeTask.ProgressTarget(
                name: entry.name,
                kind: entry.kind.rawValue,
                fromVersion: entry.installedText.isEmpty ? nil : entry.installedText,
                toVersion: entry.currentVersion
            )
        }
        let task = ChangeTask(
            kind: .upgradeAll,
            title: "更新安全项",
            commandText: command,
            verifyOutdated: true,
            batchID: batchID,
            dedupKey: "upgradeVulnerable",
            verifyNames: index.securityUpdates.map(\.name),
            progressTargets: progressTargets,
            run: { client, onEvent in
                try await client.upgradeAll(greedy: greedy, vulnerable: true, onEvent: onEvent)
            }
        )
        enqueue(task)
    }

    func bulkUpgrade(_ packages: [PackageSnapshot]) {
        bulkUpgrade(entries: packages.filter(\.outdated).map { entry(from: $0) })
    }

    /// Batch entry used by the Updates page. Pinned packages are skipped up
    /// front and reported in the batch summary instead of silently dropped.
    func bulkUpgrade(entries: [OutdatedEntry]) {
        guard !isReadOnly else {
            showToast("Homebrew 版本过低，当前为只读模式", kind: .failure)
            return
        }
        let skippedPinned = entries.filter(\.pinned).count
        let unpinned = entries.filter { !$0.pinned }
        let active = unpinned.filter { tasks.hasActivePackage(packageID: $0.id) }.count
        let targets = unpinned.filter { !tasks.hasActivePackage(packageID: $0.id) }
        guard !targets.isEmpty else {
            if skippedPinned > 0 {
                showToast("所选包均已锁定，请先解锁", kind: .info)
            } else if active > 0 {
                showToast("所选包均已有任务在运行或排队中", kind: .info)
            } else {
                showToast("所选包中没有可更新项", kind: .info)
            }
            return
        }
        let batchID = tasks.beginBatch(
            title: targets.count == 1 ? "更新 \(targets[0].name)" : "批量更新 \(targets.count) 个包",
            skipped: skippedPinned + active
        )
        for entry in targets {
            enqueue(makeUpgradeTask(entry, batchID: batchID))
        }
        var message = "已加入 \(targets.count) 个更新任务，串行执行"
        let skipped = skippedPinned + active
        if skipped > 0 { message += "（跳过 \(skipped) 个已锁定或进行中）" }
        showToast(message, kind: .info)
    }

    // MARK: - Batch update confirmation (P0-07)

    /// Builds the confirmation plan for a batch entry point. Returns without
    /// presenting a sheet when there is nothing to run: an empty confirmation
    /// page is worse than a toast, and 0 targets would make the primary button
    /// misleading.
    func requestBatchUpdate(_ scope: BatchUpdatePlan.Scope) {
        let plan = makeBatchUpdatePlan(scope)
        if let reason = plan.emptyReason {
            let skipped = plan.skippedPinned.count + plan.skippedActive.count
            if skipped > 0 {
                showToast("没有可更新的包（已跳过 \(skipped) 个锁定/进行中）", kind: .info)
            } else {
                showToast(reason, kind: .info)
            }
            pendingBatchUpdate = nil
            return
        }
        pendingBatchUpdate = plan
    }

    /// Executes the plan that was visible in the confirmation sheet. Re-resolve
    /// packages from the current index by id so an index refresh between open
    /// and confirm cannot resurrect a stale snapshot.
    func confirmBatchUpdate() {
        guard let plan = pendingBatchUpdate else { return }
        pendingBatchUpdate = nil
        guard plan.emptyReason == nil else { return }

        switch plan.scope {
        case .all:
            upgradeAll()
        case .vulnerable:
            upgradeVulnerable()
        case .selected:
            let entries = plan.packageIDs.compactMap { id in
                index.outdated.first { $0.id == id }
            }
            guard !entries.isEmpty else {
                showToast("所选包已不在可更新列表，请刷新后重试", kind: .info)
                return
            }
            bulkUpgrade(entries: entries)
        }
    }

    func cancelBatchUpdate() {
        pendingBatchUpdate = nil
    }

    private func makeBatchUpdatePlan(_ scope: BatchUpdatePlan.Scope) -> BatchUpdatePlan {
        var candidates: [OutdatedEntry] = []
        var title = "更新所选"
        var scopeEmptyReason: String?

        switch scope {
        case .all:
            title = "更新全部包"
            candidates = index.outdated
            if tasks.hasActiveDedupKey("upgradeAll") {
                scopeEmptyReason = "全部更新已在队列中"
            }
        case .vulnerable:
            title = "更新安全项"
            candidates = index.securityUpdates
            if tasks.hasActiveDedupKey("upgradeVulnerable") {
                scopeEmptyReason = "安全更新已在队列中"
            }
        case .selected(let ids):
            var seen = Set<String>()
            for id in ids where seen.insert(id).inserted {
                if let entry = index.outdated.first(where: { $0.id == id }) {
                    candidates.append(entry)
                }
            }
            if candidates.count == 1 {
                title = "更新 \(candidates[0].name)"
            } else if candidates.count > 1 {
                title = "更新 \(candidates.count) 个包"
            }
            if candidates.isEmpty {
                scopeEmptyReason = ids.isEmpty ? "未选择要更新的包" : "所选包已不在可更新列表"
            }
        }

        let pinned = candidates.filter(\.pinned)
        let unpinned = candidates.filter { !$0.pinned }
        let active = unpinned.filter { tasks.hasActivePackage(packageID: $0.id) }
        let targets = unpinned.filter { !tasks.hasActivePackage(packageID: $0.id) }

        let emptyReason: String?
        if isReadOnly {
            emptyReason = "Homebrew 版本过低，当前为只读模式，无法执行更新"
        } else if let scopeEmptyReason {
            emptyReason = scopeEmptyReason
        } else if candidates.isEmpty {
            emptyReason = "当前没有可更新项"
        } else if targets.isEmpty {
            if !pinned.isEmpty && !active.isEmpty {
                emptyReason = "可更新的包均已锁定或已有任务在运行"
            } else if !pinned.isEmpty {
                emptyReason = "可更新的包均已锁定，请先解锁"
            } else {
                emptyReason = "可更新的包均已有任务在运行或排队中"
            }
        } else {
            emptyReason = nil
        }

        return BatchUpdatePlan(
            scope: scope,
            title: title,
            packageIDs: targets.map(\.id),
            packageNames: targets.map(\.name),
            formulaCount: targets.filter { $0.kind == .formula }.count,
            caskCount: targets.filter { $0.kind == .cask }.count,
            skippedPinned: pinned.map(\.name),
            skippedActive: active.map(\.name),
            emptyReason: emptyReason
        )
    }

    /// C-11：只读预览。直接走只读 scope，不占用变更队列（旧实现把
    /// `--dry-run` 当变更任务入队，预览会挡住真正的安装/升级）。
    func previewUpgrade(_ entry: OutdatedEntry) {
        guard !isReadOnly else {
            showToast("Homebrew 版本过低，当前为只读模式", kind: .failure)
            return
        }
        guard !entry.pinned else {
            showToast("\(entry.name) 已锁定，请先解锁", kind: .info)
            return
        }
        guard let client else {
            showToast("Homebrew 尚未就绪，请稍后再试", kind: .failure)
            return
        }
        guard installation?.capabilities.dryRun != false else {
            showToast("当前 Homebrew 不支持 --dry-run，无法预览", kind: .failure)
            return
        }

        upgradePreviewTask?.cancel()
        upgradePreview = UpgradePreview(name: entry.name, kind: entry.kind, output: "", error: nil, isRunning: true)
        upgradePreviewTask = Task { [weak self] in
            do {
                let result = try await client.upgradeDryRun(entry.name, kind: entry.kind)
                guard !Task.isCancelled else { return }
                let output = (result.stdout + "\n" + result.stderr)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self?.upgradePreview = UpgradePreview(
                    name: entry.name, kind: entry.kind,
                    output: output, error: nil, isRunning: false
                )
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? BrewCommandError)?.diagnosticText ?? error.localizedDescription
                self?.upgradePreview = UpgradePreview(
                    name: entry.name, kind: entry.kind,
                    output: "", error: message, isRunning: false
                )
            }
            self?.upgradePreviewTask = nil
        }
    }

    func cancelUpgradePreview() {
        upgradePreviewTask?.cancel()
        upgradePreviewTask = nil
        upgradePreview = nil
    }

    func previewUpgrade(_ package: PackageSnapshot) {
        guard package.outdated else { return }
        previewUpgrade(entry(from: package))
    }

    var greedyUpgrades: Bool {
        get { settings.greedyUpgrades }
        set {
            settings.greedyUpgrades = newValue
            Task { await refreshIndex() }
        }
    }

    var isUpgradeAllActive: Bool {
        tasks.hasActiveDedupKey("upgradeAll") || tasks.hasActiveDedupKey("upgradeVulnerable")
    }

    /// Dangerous task awaiting its second confirmation before a retry is
    /// re-enqueued. Non-nil presents a confirmation sheet in the log drawer.
    var pendingRetry: TaskRecord?
    @ObservationIgnored private var discoverSearchTask: Task<Void, Never>?

    func retryTask(recordID: UUID) {
        guard !isReadOnly else {
            showToast("Homebrew 版本过低，当前为只读模式", kind: .failure)
            return
        }
        switch tasks.retry(recordID: recordID) {
        case .started:
            break
        case .duplicate:
            showToast("该包已有任务在运行或排队中", kind: .info)
        case .needsConfirmation:
            pendingRetry = tasks.records.first { $0.id == recordID }
        case .unavailable:
            showToast("该任务来自上次会话，无法直接重试；请在终端重新执行", kind: .info)
        }
    }

    func confirmPendingRetry(packageNameConfirmation: String? = nil) {
        guard let record = pendingRetry else { return }
        // P1-6：重试必须重新经过原提交的闸门。失败的重试曾直接复制命令，
        // 绕过依赖检查与 `--zap` 的包名输入。这里做两道校验：
        // 1) 卸载类任务重新检查依赖方；2) 强删要求再次输入包名。
        if record.commandText.contains("uninstall"), let name = record.packageName {
            let dependents = index.dependents(of: name)
            if !dependents.isEmpty {
                showToast("有 \(dependents.count) 个包依赖 \(name)，不能重试卸载", kind: .failure)
                return
            }
        }
        if record.commandText.contains("--zap") {
            guard let name = record.packageName,
                  packageNameConfirmation?.trimmed == name else {
                showToast("请重新输入包名以确认删除关联文件", kind: .failure)
                return
            }
        }
        pendingRetry = nil
        switch tasks.retry(recordID: record.id, confirmDangerous: true) {
        case .started:
            break
        case .duplicate:
            showToast("该包已有任务在运行或排队中", kind: .info)
        default:
            showToast("该任务无法重试；请在终端重新执行", kind: .info)
        }
    }

    func cancelPendingRetry() {
        pendingRetry = nil
    }

    func clearBatchSummary() {
        batchSummary = nil
    }

    func setPinned(_ package: PackageSnapshot, pinned: Bool) {
        let task = ChangeTask(
            kind: pinned ? .pin : .unpin,
            title: "\(pinned ? "锁定" : "解锁") \(package.name)",
            commandText: "brew \(pinned ? "pin" : "unpin") \(package.kind == .cask ? "--cask" : "--formula") \(package.name)",
            packageID: package.id,
            packageName: package.name,
            packageKind: package.kind,
            run: { client, onEvent in
                if pinned {
                    return try await client.pin(package.name, kind: package.kind, onEvent: onEvent)
                }
                return try await client.unpin(package.name, kind: package.kind, onEvent: onEvent)
            }
        )
        enqueue(task)
    }

    /// O-03：带「…」的「重新安装」必须先确认，不直接入队。
    var reinstallTarget: PackageSnapshot?

    func requestReinstall(_ package: PackageSnapshot) {
        reinstallTarget = package
    }

    func confirmReinstall() {
        guard let target = reinstallTarget else { return }
        reinstallTarget = nil
        reinstall(target)
    }

    func cancelReinstall() {
        reinstallTarget = nil
    }

    func reinstall(_ package: PackageSnapshot) {
        let task = ChangeTask(
            kind: .reinstall,
            title: "重新安装 \(package.name)",
            commandText: "brew reinstall \(package.kind == .cask ? "--cask " : "")\(package.name)",
            packageID: package.id,
            packageName: package.name,
            packageKind: package.kind,
            isDangerous: true,
            run: { client, onEvent in
                try await client.reinstall(package.name, kind: package.kind, onEvent: onEvent)
            }
        )
        enqueue(task)
    }

    func serviceAction(_ action: ServiceAction, service: BrewService) {
        let task = ChangeTask(
            kind: .service,
            title: "\(action.label)服务 \(service.name)",
            commandText: "brew services \(action.rawValue) \(service.name)",
            packageName: service.name,
            // 启动/停止/重启/仅运行一次都会改变系统服务的运行状态，与 PRD F9
            // 的「服务启停必须二次确认」口径一致。
            isDangerous: true,
            run: { client, onEvent in
                try await client.service(action, name: service.name, onEvent: onEvent)
            }
        )
        enqueue(task)
    }

    func performCleanup(scrub: Bool, prune: String?) {
        let task = ChangeTask(
            kind: .cleanup,
            title: "清理缓存与旧版本",
            commandText: "brew cleanup\(scrub ? " --scrub" : "")\(prune.map { " --prune=\($0)" } ?? "")",
            isDangerous: true,
            run: { client, onEvent in
                try await client.cleanup(scrub: scrub, prune: prune, onEvent: onEvent)
            }
        )
        enqueue(task)
    }

    func performAutoremove() {
        let task = ChangeTask(
            kind: .autoremove,
            title: "移除未使用依赖",
            commandText: "brew autoremove",
            isDangerous: true,
            run: { client, onEvent in
                try await client.autoremove(onEvent: onEvent)
            }
        )
        enqueue(task)
    }

    func performBrewfileImport(url: URL) {
        // 预览只服务于确认弹层；任务入队后清掉，避免下次打开残留旧内容。
        brewfileImportPreview = nil
        let task = ChangeTask(
            kind: .bundleInstall,
            title: "导入 Brewfile",
            commandText: "brew bundle install --file=\(url.path)",
            isDangerous: true,
            run: { client, onEvent in
                try await client.bundleInstall(from: url.path, onEvent: onEvent)
            }
        )
        enqueue(task)
    }

    func updateHomebrewIndex() {
        guard !tasks.hasActiveDedupKey("updateIndex") else {
            showToast("索引更新已在队列中", kind: .info)
            return
        }
        let task = ChangeTask(
            kind: .updateIndex,
            title: "更新 Homebrew 索引",
            commandText: "brew update-if-needed",
            dedupKey: "updateIndex",
            run: { client, onEvent in
                try await client.updateIfNeeded(onEvent: onEvent)
            }
        )
        enqueue(task)
    }

    // MARK: - Task result handling

    private func handleTaskFinished(_ record: TaskRecord) {
        // O-01：同步上游索引是「检查更新」的第一步，完成（或失败）后自动跑
        // 只读的 outdated 刷新；失败不阻断，页头会显示「未能同步上游」提示。
        if record.action == ChangeTask.Kind.updateIndex.rawValue {
            isSyncingUpstream = false
            switch record.status {
            case .succeeded:
                settings.lastUpstreamSyncAt = Date()
                upstreamSyncError = nil
            case .cancelled:
                upstreamSyncError = "已取消同步上游索引"
            default:
                upstreamSyncError = record.message ?? "未能同步上游索引"
            }
            Task { await self.refreshIndex() }
            return
        }

        // O-02：任务结果统一由任务岛承载（成功 / 失败 / 未确认 / 取消），
        // 不再用 toast 重复播报；失败也不会 2.6s 后消失。

        // O-02：系统通知只在 App 不在前台时发送。
        guard settings.notifyOnTaskCompletion, !NSApp.isActive else { return }
        let body: String
        switch record.status {
        case .succeeded:
            body = record.verificationNote ?? "任务已完成。"
        case .unverified:
            body = record.verificationNote ?? "任务结束，但版本未确认。"
        case .failed:
            body = record.message ?? "任务失败，请查看日志。"
        case .cancelled:
            body = "任务已取消。"
        default:
            body = record.status.label
        }
        Task {
            await NotificationService.post(title: record.title, body: body)
        }
    }

    // MARK: - Services

    func loadServices() async {
        guard let client, !servicesLoading else { return }
        servicesLoading = true
        servicesError = nil
        defer {
            servicesLoading = false
            servicesLoaded = true
        }
        do {
            services = try await client.services()
        } catch {
            servicesError = (error as? BrewCommandError)?.diagnosticText ?? error.localizedDescription
        }
    }

    /// 系统级服务：root 用户或 /Library/LaunchDaemons 下的 plist。
    /// 这类服务需要管理员权限，Brewbutler 不代理 sudo（PRD F8.2）。
    func isSystemLevelService(_ service: BrewService) -> Bool {
        if (service.user ?? "").lowercased() == "root" { return true }
        if let file = service.file, file.hasPrefix("/Library/LaunchDaemons") { return true }
        return false
    }

    /// 读取 launchd plist 的 StandardOutPath / StandardErrorPath；纯读取，不执行命令。
    func serviceLogPaths(for service: BrewService) -> ServiceLogPaths {
        guard let file = service.file, !file.isEmpty,
              let data = FileManager.default.contents(atPath: file),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
        else { return ServiceLogPaths() }
        func expand(_ value: Any?) -> String? {
            guard let raw = value as? String, !raw.isEmpty else { return nil }
            let expanded = (raw as NSString).expandingTildeInPath
            return expanded.hasPrefix("/") ? expanded : nil
        }
        return ServiceLogPaths(
            standardOut: expand(plist["StandardOutPath"]),
            standardError: expand(plist["StandardErrorPath"])
        )
    }

    func openServiceLog(path: String) {
        guard path.hasPrefix("/") else { return }
        guard FileManager.default.fileExists(atPath: path) else {
            showToast("日志文件不存在：\(path)", kind: .failure)
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// 系统级服务的等价命令（只复制，不执行）。
    func systemServiceCommand(for service: BrewService) -> String {
        let action = (service.lifecycle == .running || service.lifecycle == .scheduled) ? "stop" : "start"
        return "sudo brew services \(action) \(service.name)"
    }

    // MARK: - Maintenance

    func loadMaintenanceIfNeeded(force: Bool = false) async {
        if !force, maintenance.loadedAt != nil { return }
        // Re-entrant calls (页面切换 + 手动刷新) must not mark the section as
        // loaded while the first run is still in flight.
        guard !isLoadingMaintenance else { return }
        isLoadingMaintenance = true
        defer { isLoadingMaintenance = false }
        await computeDiskUsage()
        await runDoctor()
        await checkMissing()
        await previewCleanup(presentSheet: false)
        await previewAutoremove(presentSheet: false)
        maintenance.loadedAt = Date()
    }

    func runDoctor() async {
        guard let client, !maintenance.doctorLoading else { return }
        maintenance.doctorLoading = true
        maintenance.doctorError = nil
        defer { maintenance.doctorLoading = false }
        do {
            let result = try await client.doctor()
            let text = result.combinedOutput.isEmpty
                ? result.stdout + "\n" + result.stderr
                : result.combinedOutput
            maintenance.doctorExitCode = result.exitCode
            maintenance.doctorReport = BrewTextParser.parseDoctor(text)
        } catch {
            // P1-4：诊断失败必须清掉上一次的结论与退出码，否则健康卡会继续
            // 展示旧报告并显示「环境健康」，把失败当成本次结果。
            maintenance.doctorReport = nil
            maintenance.doctorExitCode = nil
            maintenance.doctorError = (error as? BrewCommandError)?.diagnosticText ?? error.localizedDescription
        }
    }

    func checkMissing() async {
        guard let client, !maintenance.missingLoading else { return }
        maintenance.missingLoading = true
        maintenance.missingError = nil
        maintenance.missingExitCode = nil
        defer { maintenance.missingLoading = false }
        do {
            let result = try await client.missing()
            let text = result.stdout.trimmed.isEmpty ? result.combinedOutput : result.stdout
            maintenance.missingExitCode = result.exitCode
            maintenance.missingReport = BrewTextParser.parseMissing(text)
            if result.exitCode != 0 && maintenance.missingReport?.entries.isEmpty == true {
                maintenance.missingError = "brew missing 退出码 \(result.exitCode)，但未能解析出缺失项。"
            }
        } catch {
            maintenance.missingError = (error as? BrewCommandError)?.diagnosticText ?? error.localizedDescription
        }
    }

    func previewCleanup(presentSheet: Bool) async {
        guard let client, !maintenance.cleanupLoading else { return }
        maintenance.cleanupLoading = true
        maintenance.cleanupError = nil
        maintenance.cleanupPreviewFailed = false
        defer { maintenance.cleanupLoading = false }
        do {
            let result = try await client.cleanupPreview()
            let text = result.combinedOutput.isEmpty
                ? result.stdout + "\n" + result.stderr
                : result.combinedOutput
            maintenance.cleanupRawText = text
            maintenance.cleanupExitCode = result.exitCode
            let preview = BrewTextParser.parseCleanupPreview(text)
            // 解析失败与「真的没有可清理项」必须区分：退出码非 0、或输出含 error
            // 且解析不出任何条目时，不能显示「环境很干净」，更不能允许执行清理。
            let failed = result.exitCode != 0
                || (preview.isEmpty && text.lowercased().contains("error"))
            if failed {
                maintenance.cleanupPreviewFailed = true
                maintenance.cleanupPreview = nil
                maintenance.cleanupError = "清理预览失败（退出码 \(result.exitCode)），无法确认可清理内容。"
                if presentSheet {
                    showToast("清理预览失败，未执行任何清理", kind: .failure)
                }
                return
            }
            maintenance.cleanupPreview = preview
            if presentSheet {
                if preview.isEmpty {
                    showToast("没有可清理的内容，环境很干净", kind: .info)
                } else {
                    cleanupRequest = CleanupRequest(preview: preview)
                }
            }
        } catch {
            maintenance.cleanupPreviewFailed = true
            maintenance.cleanupPreview = nil
            maintenance.cleanupRawText = nil
            maintenance.cleanupError = (error as? BrewCommandError)?.diagnosticText ?? error.localizedDescription
            if presentSheet {
                showToast("无法预览清理：\(error.localizedDescription)", kind: .failure)
            }
        }
    }

    func previewAutoremove(presentSheet: Bool) async {
        guard let client, !maintenance.autoremoveLoading else { return }
        maintenance.autoremoveLoading = true
        maintenance.autoremoveError = nil
        defer { maintenance.autoremoveLoading = false }
        do {
            let result = try await client.autoremovePreview()
            let text = result.combinedOutput.isEmpty
                ? result.stdout + "\n" + result.stderr
                : result.combinedOutput
            let preview = BrewTextParser.parseAutoremovePreview(text)
            maintenance.autoremovePreview = preview
            if presentSheet {
                if preview.packages.isEmpty {
                    showToast("没有检测到可自动移除的孤立依赖", kind: .info)
                } else {
                    autoremoveRequest = AutoremoveRequest(preview: preview)
                }
            }
        } catch {
            maintenance.autoremoveError = (error as? BrewCommandError)?.diagnosticText ?? error.localizedDescription
            if presentSheet {
                showToast("无法预览孤立依赖：\(error.localizedDescription)", kind: .failure)
            }
        }
    }

    // MARK: - Brewfile

    func exportBrewfile() {
        guard let client else {
            showToast("Homebrew 尚未就绪", kind: .failure)
            return
        }
        brewfileExportError = nil
        let panel = NSSavePanel()
        panel.title = "导出 Brewfile"
        panel.nameFieldStringValue = "Brewfile"
        panel.canCreateDirectories = true
        panel.message = "Brewfile 会包含当前已安装的 formula、cask 与 tap。"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            do {
                let result = try await client.bundleDump(to: url.path)
                guard result.exitCode == 0 else {
                    let output = result.stderr.trimmed.isEmpty ? result.stdout : result.stderr
                    let firstLine = output.components(separatedBy: .newlines)
                        .first { !$0.trimmed.isEmpty }?.trimmed ?? "无错误输出"
                    brewfileExportError = "导出失败（退出码 \(result.exitCode)）：\(firstLine)"
                    showToast("Brewfile 导出失败（退出码 \(result.exitCode)）", kind: .failure)
                    return
                }
                settings.lastBrewfileExport = url.path
                brewfileExportError = nil
                showToast("已导出 Brewfile：\(url.lastPathComponent)", kind: .success)
            } catch {
                brewfileExportError = "导出 Brewfile 失败：\(error.localizedDescription)"
                showToast("导出 Brewfile 失败：\(error.localizedDescription)", kind: .failure)
            }
        }
    }

    func revealBrewfileExport() {
        let path = settings.lastBrewfileExport
        guard !path.isEmpty else { return }
        revealInFinder(path: path)
    }

    func chooseBrewfileToImport() {
        let panel = NSOpenPanel()
        panel.title = "选择 Brewfile"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "导入会安装文件中缺失的包，已安装的包不会重复安装。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        brewfileImportPreview = Self.makeBrewfilePreview(url: url, index: index)
        brewfileImportURL = url
    }

    /// 纯文本解析，不执行 brew；执行仍由 `performBrewfileImport(url:)` 负责。
    private static func makeBrewfilePreview(url: URL, index: PackageIndex) -> BrewfileImportPreview {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            var items: [BrewfileImportPreview.Item] = []
            var duplicates: [String] = []
            var seen = Set<String>()
            for rawLine in text.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#") else { continue }
                guard let name = firstQuotedName(in: line) else { continue }
                let directive = line.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
                let kind: BrewfileImportPreview.Item.Kind
                switch directive {
                case "brew": kind = .formula
                case "cask": kind = .cask
                case "tap": kind = .tap
                default: kind = .unsupported
                }
                let key = "\(kind.rawValue):\(name)"
                guard seen.insert(key).inserted else {
                    duplicates.append(name)
                    continue
                }
                let installed: Bool
                switch kind {
                case .formula: installed = index.package(named: name, kind: .formula) != nil
                case .cask: installed = index.package(named: name, kind: .cask) != nil
                default: installed = false
                }
                items.append(BrewfileImportPreview.Item(kind: kind, name: name, isInstalled: installed))
            }
            return BrewfileImportPreview(url: url, items: items, duplicates: duplicates, parseError: nil)
        } catch {
            return BrewfileImportPreview(
                url: url,
                items: [],
                duplicates: [],
                parseError: "无法读取 Brewfile：\(error.localizedDescription)"
            )
        }
    }

    private static func firstQuotedName(in line: String) -> String? {
        guard let start = line.firstIndex(of: "\"") else { return nil }
        let rest = line[line.index(after: start)...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let name = String(rest[..<end]).trimmed
        return name.isEmpty ? nil : name
    }

    // MARK: - Discover

    /// Cancels any in-flight search and starts a new one; the newest query
    /// always wins. Debouncing lives in the UI (onChange), but a fast typist
    /// must never be left looking at a stale result.
    func searchDiscover(forceRefresh: Bool = false) {
        discoverSearchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        discoverSearchTask = Task { [weak self] in
            await self?.performDiscoverSearch(generation: generation, forceRefresh: forceRefresh)
        }
    }

    private func performDiscoverSearch(generation: Int, forceRefresh: Bool = false) async {
        let query = discover.query.trimmed
        guard !query.isEmpty else {
            guard generation == searchGeneration else { return }
            discover.results = []
            discover.hasSearched = false
            discover.error = nil
            discover.usingCache = false
            discover.cacheIsStale = false
            discover.cacheIsLocalOnly = false
            return
        }
        discover.isSearching = true
        discover.error = nil
        discover.usingCache = false
        discover.cacheIsStale = false
        discover.cacheIsLocalOnly = false
        defer {
            if generation == searchGeneration {
                discover.isSearching = false
            }
        }

        let cacheKey = searchCacheKey(query: query, kind: discover.kind)
        if let client {
            do {
                let results = try await client.search(query, kind: discover.kind, descriptions: true)
                if generation != searchGeneration { return }
                discover.results = results
                discover.hasSearched = true
                saveSearchCache(results, key: cacheKey)
                return
            } catch is CancellationError {
                return
            } catch {
                if generation != searchGeneration { return }
                let prefix = forceRefresh ? "强制刷新失败：" : ""
                discover.error = (error as? BrewCommandError)?.kind == .networkFailure
                    ? "\(prefix)网络不可用，正在尝试离线缓存与本地索引。"
                    : "\(prefix)搜索失败：\(error.localizedDescription)"
            }
        }

        // 过期缓存不丢弃（PRD F7.2）：展示但标注「可能过期」，并提供强制刷新。
        if let cached = cache.load(SearchCachePayload.self, key: cacheKey),
           generation == searchGeneration {
            let age = Date().timeIntervalSince(cached.value.savedAt)
            discover.results = cached.value.results.map {
                BrewSearchResult(
                    name: $0.name,
                    summary: $0.summary,
                    kind: PackageSnapshot.Kind(rawValue: $0.kind) ?? .formula
                )
            }
            discover.usingCache = true
            discover.cacheDate = cached.value.savedAt
            discover.cacheIsStale = age >= Self.searchTTL
            discover.cacheIsLocalOnly = false
            discover.hasSearched = true
            if discover.error == nil {
                discover.error = discover.cacheIsStale
                    ? "网络不可用，显示可能过期的缓存。"
                    : "网络不可用，显示 \(cached.value.savedAt.relativeText)的缓存。"
            }
            return
        }

        // Final fallback: local installed index only. This keeps the app usable
        // offline instead of showing an empty screen.
        if generation == searchGeneration {
            let local = index.packages
                .filter {
                    $0.name.localizedCaseInsensitiveContains(query)
                        || ($0.desc?.localizedCaseInsensitiveContains(query) ?? false)
                }
                .prefix(60)
                .map { BrewSearchResult(name: $0.name, summary: $0.desc ?? "已安装", kind: $0.kind) }
            discover.results = Array(local)
            discover.usingCache = true
            discover.cacheDate = nil
            discover.cacheIsStale = false
            discover.cacheIsLocalOnly = true
            discover.hasSearched = true
            discover.error = "网络不可用，仅显示本地已安装包。"
        }
    }

    private func searchCacheKey(query: String, kind: PackageSnapshot.Kind?) -> String {
        "search-\(query.lowercased())-\(kind?.rawValue ?? "all")"
    }

    private func saveSearchCache(_ results: [BrewSearchResult], key: String) {
        let payload = SearchCachePayload(
            results: results.map { CachedSearchResult(name: $0.name, summary: $0.summary, kind: $0.kind.rawValue) },
            savedAt: Date()
        )
        cache.save(payload, key: key)
    }

    /// 工具栏搜索建议：只从已安装索引里取最多 5 个直接命中（规范 §3.3）。
    func installedSearchSuggestions(for query: String) -> [PackageSnapshot] {
        let needle = query.trimmed
        guard !needle.isEmpty else { return [] }
        return Array(
            index.packages
                .filter {
                    $0.name.localizedCaseInsensitiveContains(needle)
                        || $0.fullName.localizedCaseInsensitiveContains(needle)
                }
                .prefix(5)
        )
    }

    func isInstalled(_ result: BrewSearchResult) -> Bool {
        index.package(named: result.name, kind: result.kind) != nil
    }

    // MARK: - Local filtering helpers

    func installedPackages(filter: InstalledFilter, query: String, sort: PackageSort) -> [PackageSnapshot] {
        var packages = index.packages
        switch filter {
        case .all:
            break
        case .formula:
            packages = packages.filter { $0.kind == .formula }
        case .cask:
            packages = packages.filter { $0.kind == .cask }
        case .outdated:
            packages = packages.filter(\.outdated)
        case .pinned:
            packages = packages.filter(\.pinned)
        case .vulnerable:
            packages = packages.filter(\.hasVulnerability)
        case .manual:
            packages = packages.filter { $0.installedOnRequest == true }
        case .kegOnly:
            packages = packages.filter(\.kegOnly)
        }

        let needle = query.trimmed
        if !needle.isEmpty {
            packages = packages.filter {
                $0.name.localizedCaseInsensitiveContains(needle)
                    || $0.fullName.localizedCaseInsensitiveContains(needle)
                    || ($0.desc?.localizedCaseInsensitiveContains(needle) ?? false)
            }
        }

        switch sort {
        case .name:
            return packages
        case .size:
            return packages.sorted { ($0.diskUsageBytes ?? -1) > ($1.diskUsageBytes ?? -1) }
        case .installedAt:
            return packages.sorted { ($0.installedAt ?? .distantPast) > ($1.installedAt ?? .distantPast) }
        case .status:
            return packages.sorted { lhs, rhs in
                if lhs.outdated != rhs.outdated { return lhs.outdated }
                if lhs.hasVulnerability != rhs.hasVulnerability { return lhs.hasVulnerability }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    /// 资料库组合筛选（O-06）：scope 单选 + 「筛选」菜单里的附加条件取交集。
    func libraryPackages(options: LibraryFilterOptions, query: String) -> [PackageSnapshot] {
        var packages = index.packages
        switch options.scope {
        case .all, .pinned, .manual, .kegOnly:
            break
        case .formula:
            packages = packages.filter { $0.kind == .formula }
        case .cask:
            packages = packages.filter { $0.kind == .cask }
        case .outdated:
            packages = packages.filter(\.outdated)
        case .vulnerable:
            packages = packages.filter(\.hasVulnerability)
        }
        if options.pinnedOnly { packages = packages.filter(\.pinned) }
        if options.manualOnly { packages = packages.filter { $0.installedOnRequest == true } }
        if options.kegOnlyOnly { packages = packages.filter(\.kegOnly) }
        if let tap = options.tap { packages = packages.filter { $0.tap == tap } }

        let needle = query.trimmed
        if !needle.isEmpty {
            packages = packages.filter {
                $0.name.localizedCaseInsensitiveContains(needle)
                    || $0.fullName.localizedCaseInsensitiveContains(needle)
                    || ($0.desc?.localizedCaseInsensitiveContains(needle) ?? false)
            }
        }
        return packages
    }

    /// scope 栏计数只按 scope 本身统计，不受附加筛选影响（与原型一致）。
    func libraryScopeCount(_ filter: InstalledFilter) -> Int {
        switch filter {
        case .all: return index.packages.count
        case .formula: return index.formulae.count
        case .cask: return index.casks.count
        case .outdated: return index.packages.filter(\.outdated).count
        case .vulnerable: return index.packages.filter(\.hasVulnerability).count
        case .pinned: return index.packages.filter(\.pinned).count
        case .manual: return index.packages.filter { $0.installedOnRequest == true }.count
        case .kegOnly: return index.packages.filter(\.kegOnly).count
        }
    }

    /// 「筛选」菜单的 tap 子菜单数据（只列实际出现过的 tap，按名称排序）。
    var availableTapNames: [String] {
        Array(Set(index.packages.compactMap { $0.tap })).sorted()
    }

    func filteredUpdates(filter: UpdateFilter, query: String) -> [OutdatedEntry] {
        var entries = index.outdated
        switch filter {
        case .all:
            break
        case .security:
            entries = entries.filter(\.isSecurityUpdate)
        case .formula:
            entries = entries.filter { $0.kind == .formula }
        case .cask:
            entries = entries.filter { $0.kind == .cask }
        }
        let needle = query.trimmed
        if !needle.isEmpty {
            entries = entries.filter { $0.name.localizedCaseInsensitiveContains(needle) }
        }
        return entries
    }

    // MARK: - Feedback

    func showToast(_ text: String, kind: ToastMessage.Kind) {
        let message = ToastMessage(text: text, kind: kind)
        toastQueue.append(message)
        toastQueueCount = toastQueue.count
        advanceToastQueue()
    }

    /// 手动关闭当前 toast（点击 toast 或按 Esc），然后展示队列中的下一条。
    func dismissToast() {
        toastTask?.cancel()
        toast = nil
        advanceToastQueue()
    }

    /// 失败结果/日志入口：展开任务岛并定位到最近任务（任务岛折叠态点击时调用）。
    /// P1-1：先退出历史选择，回到最近任务——否则「查看」会打开用户上次浏览的
    /// 旧记录，而不是刚失败的任务。
    func openLogDrawerFromToast() {
        tasks.followLatestRecord()
        tasks.showDrawer = true
    }

    private func advanceToastQueue() {
        guard toast == nil, !toastQueue.isEmpty else {
            toastQueueCount = toastQueue.count
            return
        }
        let message = toastQueue.removeFirst()
        toastQueueCount = toastQueue.count
        toast = message
        toastTask?.cancel()
        // 错误停留更久，便于阅读；成功/信息 2.8s。
        let duration: TimeInterval = message.kind == .failure ? 5.0 : 2.8
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            guard let self, self.toast?.id == message.id else { return }
            self.toast = nil
            self.advanceToastQueue()
        }
    }

    func dismissOnboarding() {
        completeOnboarding(runScan: false)
    }

    /// O-11：引导完成；可选在关闭后开始一次安全扫描（默认不勾选）。
    func completeOnboarding(runScan: Bool) {
        settings.onboardingCompleted = true
        showOnboarding = false
        if runScan {
            scanVulnerabilities()
        }
    }

    // MARK: - O-05 快捷键调整提示

    /// 从 v1 升级后首次启动给一次性提示「快捷键已调整」。
    var shouldShowShortcutTip: Bool {
        settings.onboardingCompleted && !settings.hasSeenShortcutTip
    }

    func dismissShortcutTip() {
        settings.hasSeenShortcutTip = true
    }

    /// 设置 → 关于 → 「重新显示引导」。
    func restartOnboarding() {
        settings.onboardingCompleted = false
        onboardingStep = 0
        showOnboarding = true
    }

    // MARK: - Diagnostics export (P0-08)

    /// Entry point used by Settings → 隐私 → 导出诊断包. The sheet lets the user
    /// opt into package names / local paths; both default to redacted.
    func presentDiagnosticsExport() {
        pendingDiagnosticsExport = DiagnosticsExportPlan()
    }

    /// Single source of truth for the exported text. The privacy statement at
    /// the bottom is generated from the actual content, never hard-coded.
    func diagnosticsText(_ plan: DiagnosticsExportPlan) -> String {
        var lines: [String] = []
        lines.append("Brewbutler 诊断信息")
        lines.append("导出时间：\(Date().shortDateTimeText)")
        lines.append("应用版本：\(Self.appVersionText)")
        lines.append("macOS：\(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("隐私选项：包名\(plan.includePackages ? "包含" : "已隐藏") · 本机路径\(plan.includePaths ? "包含" : "已隐藏")")
        lines.append("")
        lines.append("## Homebrew")
        if let installation {
            lines.append("可执行文件：\(redactedPath(installation.executablePath, includePaths: plan.includePaths))")
            lines.append("版本：\(installation.versionText)")
            lines.append("prefix：\(redactedPath(installation.prefix, includePaths: plan.includePaths))")
            lines.append("cellar：\(redactedPath(installation.cellar, includePaths: plan.includePaths))")
            lines.append("cache：\(redactedPath(installation.cache, includePaths: plan.includePaths))")
            lines.append("repository：\(redactedPath(installation.repository, includePaths: plan.includePaths))")
            lines.append("jq：\(installation.capabilities.jqPath.map { redactedPath($0, includePaths: plan.includePaths) } ?? "未找到")")
            lines.append("能力：vulns=\(installation.capabilities.vulns), dry-run=\(installation.capabilities.dryRun), list-versions=\(installation.capabilities.listVersionsJSON)")
            if installation.capabilities.degradedReasons.isEmpty {
                lines.append("降级：无")
            } else {
                lines.append("降级：")
                for reason in installation.capabilities.degradedReasons {
                    lines.append("- \(reason)")
                }
            }
        } else {
            lines.append("状态：未检测到 Homebrew")
        }
        lines.append("")
        lines.append("## 注入的环境变量")
        if let installation {
            let environment = BrewEnvironment(installation: installation, settings: settings.environmentSettings)
            for line in environment.diagnosticsInjectionList() {
                lines.append(redactedEnvironmentLine(line, includePaths: plan.includePaths))
            }
        }
        lines.append("")
        lines.append("## 设置（不含个人路径与包列表）")
        lines.append("外观：\(settings.appearance.label)")
        lines.append("菜单栏图标：\(settings.showMenuBarExtra ? "启用" : "关闭")")
        lines.append("日志保留：\(settings.logRetentionDays) 天")
        lines.append("遥测：关闭（v1.0 固定）")
        lines.append("")
        lines.append("## 最近任务（仅元数据）")
        for record in tasks.records.prefix(10) {
            let title = plan.includePackages ? record.title : redactedTaskTitle(record)
            lines.append("\(record.createdAt.shortDateTimeText) · \(record.status.label) · \(title) · exit=\(record.exitCode.map(String.init) ?? "-")")
        }
        lines.append("")
        lines.append("## 隐私声明")
        lines.append(Self.diagnosticsPrivacyStatement(for: plan))
        return lines.joined(separator: "\n")
    }

    func saveDiagnostics(_ text: String) {
        let panel = NSSavePanel()
        panel.title = "导出诊断包"
        panel.nameFieldStringValue = "Brewbutler-Diagnostics.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            showToast("诊断包已导出", kind: .success)
        } catch {
            showToast("导出诊断包失败：\(error.localizedDescription)", kind: .failure)
        }
    }

    static func diagnosticsPrivacyStatement(for plan: DiagnosticsExportPlan) -> String {
        let packages = plan.includePackages ? "包含包名" : "不含包名"
        let paths = plan.includePaths ? "包含本机绝对路径（$HOME 已缩写为 ~）" : "不含绝对路径"
        return "本诊断包\(packages)，\(paths)；不包含命令输出、用户名或代理凭据。"
    }

    /// Default redaction: no package names, no absolute paths.
    private func redactedPath(_ path: String, includePaths: Bool) -> String {
        guard includePaths else { return "<已隐藏>" }
        return Self.abbreviatedHomePath(path)
    }

    private static func abbreviatedHomePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    private func redactedEnvironmentLine(_ line: String, includePaths: Bool) -> String {
        guard let separator = line.firstIndex(of: "=") else { return line }
        let key = String(line[..<separator])
        var value = String(line[line.index(after: separator)...])
        // Proxy values may embed credentials: https://user:pass@host:port
        if let scheme = value.range(of: "://"), let at = value.lastIndex(of: "@"), at > scheme.upperBound {
            value = value.replacingCharacters(in: scheme.upperBound..<at, with: "***")
        }
        if value.hasPrefix("/") || value.hasPrefix("~/") || value == "~" {
            value = redactedPath(value, includePaths: includePaths)
        }
        return "\(key)=\(value)"
    }

    private func redactedTaskTitle(_ record: TaskRecord) -> String {
        switch record.action {
        case "install": return "安装（包名已隐藏）"
        case "uninstall": return "卸载（包名已隐藏）"
        case "upgrade", "upgradeAll": return "更新（包名已隐藏）"
        case "upgradeDryRun": return "预览更新（包名已隐藏）"
        case "pin": return "锁定（包名已隐藏）"
        case "unpin": return "解锁（包名已隐藏）"
        case "reinstall": return "重装（包名已隐藏）"
        case "cleanup": return "清理缓存"
        case "autoremove": return "自动清理"
        case "service": return "服务操作"
        case "bundleInstall": return "Brewfile 安装"
        default: return "任务（包名已隐藏）"
        }
    }

    // MARK: - Task status (D-17)

    /// 发现页/详情页按钮用：同一包同类型的排队中/运行中任务。
    func activeTask(for name: String, kind: PackageSnapshot.Kind) -> TaskRecord? {
        tasks.records.first { record in
            guard !record.status.isTerminal, record.packageName == name else { return false }
            return record.packageKind == nil || record.packageKind == kind.rawValue
        }
    }

    // MARK: - Auto update check (C-12)

    /// 静默检查可更新项：离线失败不弹 toast、不改错误横幅，只记录尝试时间。
    func autoCheckUpdatesIfNeeded() async {
        guard settings.autoCheckUpdates, installation != nil, let client else { return }
        if let last = settings.lastAutoCheckAt,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        guard !isRefreshing else { return }
        do {
            let outdated = try await client.outdated(greedy: settings.greedyUpgrades)
            settings.lastAutoCheckAt = Date()
            settings.lastAutoCheckFailedAt = nil
            outdatedFetchedAt = Date()
            outdatedIsCached = false
            outdatedRefreshError = nil
            if let payload = lastPayload {
                index = PackageIndex.build(
                    info: payload.info,
                    outdated: outdated,
                    vulnReport: vulnReport,
                    listVersions: payload.listVersions,
                    fetchedAt: payload.fetchedAt
                )
            }
            notifyIfNewUpdates()
        } catch {
            // P1-10：静默失败只记录失败时间，不能写成功时间——否则离线用户
            // 也会看到「上次自动检查 刚刚」，把陈旧数据当成新鲜结果。
            settings.lastAutoCheckFailedAt = Date()
        }
    }

    func startAutoCheckTimer() {
        guard autoCheckTask == nil else { return }
        autoCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.autoCheckUpdatesIfNeeded()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func applyAutoCheckPreference() {
        if settings.autoCheckUpdates {
            startAutoCheckTimer()
            Task { await autoCheckUpdatesIfNeeded() }
        } else {
            autoCheckTask?.cancel()
            autoCheckTask = nil
        }
    }

    // MARK: - Brew candidates (A-19)

    func loadBrewCandidates() async {
        guard !isLoadingBrewCandidates else { return }
        isLoadingBrewCandidates = true
        defer { isLoadingBrewCandidates = false }
        brewCandidates = await BrewLocator().discoverCandidates(override: settings.brewPathOverride.nilIfEmpty)
    }

    // MARK: - Notifications (D-18)

    func refreshNotificationAuthorization() async {
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorization = notificationSettings.authorizationStatus
    }

    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func clearCaches() {
        cache.removeAll()
        detailCache.removeAll()
        vulnReport = nil
        lastPayload = nil
        usesCachedIndex = false
        indexSourceNote = nil
        showToast("本地缓存已清除", kind: .success)
    }

    func requestNotificationPermission() {
        Task {
            let granted = await NotificationService.requestAuthorization()
            await refreshNotificationAuthorization()
            if granted {
                showToast("已允许通知", kind: .success)
            } else if notificationAuthorization == .denied {
                showToast("通知已被系统拒绝，请在系统设置中开启", kind: .info)
            } else {
                showToast("通知未授权，可在系统设置中开启", kind: .info)
            }
        }
    }
}

// MARK: - Notifications

enum NotificationService {
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func post(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
