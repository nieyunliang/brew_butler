import AppKit
import UserNotifications

/// 任务完成通知的点击路由（规范 §4.8）。
///
/// 通知只在 App 不在前台时发送（AppState.handleTaskFinished 判断）。点击通知
/// 回到主窗口并展开任务岛，让用户直接看到结果，而不是再去找入口。
@MainActor
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    weak var appState: AppState?

    /// 注册到 UNUserNotificationCenter；由 MyApp 在启动时调用一次。
    static func install(appState: AppState) {
        shared.appState = appState
        UNUserNotificationCenter.current().delegate = shared
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            NotificationRouter.shared.revealTaskIsland()
        }
    }

    /// App 在前台时不弹横幅（发送侧已经做了「不在前台才发」的门控，
    /// 这里只是双保险，避免系统把队列里的旧通知又弹出来打扰）。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }

    private func revealTaskIsland() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
        appState?.tasks.followLatestRecord()
        appState?.tasks.showDrawer = true
    }
}
