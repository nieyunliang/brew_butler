import AppKit

/// P0-10 退出守卫：变更类任务运行期间退出前必须确认。
///
/// 直接退出会让 brew 子进程随进程树被系统杀掉，可能留下「升级到一半」这类
/// 部分完成状态。这里在退出前显式确认；用户选择「停止任务并退出」时复用
/// 任务队列既有的取消链路（SIGINT → SIGTERM → SIGKILL），等任务真正结束
/// 后再放行退出；超时则取消本次退出，避免假装成功、留下孤儿进程。
@MainActor
final class QuitGuard: NSObject, NSApplicationDelegate {
    /// 由 MyApp 在 WindowGroup / MenuBarExtra 内容出现时注入。弱引用：AppState
    /// 的生命周期由 SwiftUI 的 @State 持有，守卫只读状态，不应延长它。
    weak var appState: AppState?

    /// 已进入「取消任务后等待退出」流程。AppKit 可能再次调用
    /// applicationShouldTerminate（例如用户再按一次 ⌘Q），此时必须直接返回
    /// .terminateLater，不能弹出第二个确认框。
    private var isTerminatingAfterCancel = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState else { return .terminateNow }
        // P1-3：队列被暂停/取消后 isRunning 很快就为 false，但 pending 任务仍在
        // 队列里——只看 isRunning 会让 ⌘Q 静默丢弃排队任务。
        let hasRunning = appState.tasks.isRunning
        let pending = appState.tasks.pendingCount
        guard hasRunning || pending > 0 else { return .terminateNow }
        if isTerminatingAfterCancel { return .terminateLater }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = hasRunning ? "有任务正在运行" : "有任务在排队"
        alert.informativeText = hasRunning
            ? "退出会中断当前变更，系统可能处于部分完成状态。brew 子进程会随任务取消结束。"
                + (pending > 0 ? "另有 \(pending) 个任务在排队，也会一并丢弃。" : "")
            : "队列中还有 \(pending) 个任务尚未开始；退出会丢弃这些任务。"
        // 默认按钮（回车）是「继续运行」，与危险确认默认焦点在取消保持一致。
        alert.addButton(withTitle: "继续运行")
        alert.addButton(withTitle: "停止任务并退出")

        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }

        isTerminatingAfterCancel = true
        // 先暂停队列：否则取消当前任务后，排队中的下一个任务会立刻顶上来，
        // isRunning 一直为真，退出被拖到超时。应用真正退出后队列状态不再重要。
        appState.tasks.pauseQueue()
        appState.tasks.cancelCurrent()

        Task { @MainActor [self] in
            // 取消链路最长约 7s（SIGINT 3s + SIGTERM 累计 7s + SIGKILL），留 3s 余量。
            for _ in 0..<100 {
                if !appState.tasks.isRunning {
                    sender.reply(toApplicationShouldTerminate: true)
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            // 超时：任务还没结束，不能放行退出（可能留下孤儿 brew 进程）。
            appState.tasks.resumeQueue()
            isTerminatingAfterCancel = false
            sender.reply(toApplicationShouldTerminate: false)

            let notice = NSAlert()
            notice.alertStyle = .warning
            notice.messageText = "任务仍在结束中，已取消退出"
            notice.informativeText = "brew 进程尚未退出。请稍后重试；任务日志中可查看当前状态。"
            notice.addButton(withTitle: "好")
            notice.runModal()
        }
        return .terminateLater
    }
}
