import AppKit
import Foundation
import UserNotifications

// MARK: - 统一通知路由

/// App 内唯一的 `UNUserNotificationCenterDelegate`。
/// 必须在启动早期设置一次，按 identifier 前缀把点击路由回各功能，
/// 避免监控告警引擎与录制计划互相抢占 delegate。
public final class AppNotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = AppNotificationRouter()

    private var installed = false

    private override init() {
        super.init()
    }

    @MainActor
    public func install() {
        guard !installed else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        installed = true
        UNUserNotificationCenter.current().delegate = self
        RecorderScheduleNotifier.shared.registerCategories()
    }

    // MARK: 前台展示

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 采样端与计划端都已按系统状态抑制投递，这里只负责展示样式
        completionHandler([.banner, .sound])
    }

    // MARK: 点击与动作

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let actionIdentifier = response.actionIdentifier
        let scheduleIDString = response.notification.request.content.userInfo["scheduleID"] as? String
        let windowStartString = response.notification.request.content.userInfo["windowStart"] as? String
        completionHandler()

        Task { @MainActor in
            if identifier.hasPrefix(RecorderScheduleNotifier.identifierPrefix) {
                self.handleRecorderNotification(scheduleIDString: scheduleIDString,
                                                windowStartString: windowStartString,
                                                actionIdentifier: actionIdentifier)
            } else if identifier.hasPrefix("calmbar.monitor.") {
                self.openMonitorSection()
            }
        }
    }

    @MainActor
    private func openMonitorSection() {
        StatusBarManager.shared.showPopover()
        _ = StatusBarManager.shared.selectPopoverTab(.monitor)
    }

    @MainActor
    private func handleRecorderNotification(scheduleIDString: String?,
                                            windowStartString: String?,
                                            actionIdentifier: String) {
        let scheduleID = scheduleIDString.flatMap(UUID.init(uuidString:))
        let windowStart = windowStartString.flatMap(Double.init).map(Date.init(timeIntervalSince1970:))

        if actionIdentifier == RecorderScheduleNotifier.skipActionIdentifier {
            if let scheduleID {
                RecorderScheduleCoordinator.shared.skipUpcoming(scheduleID: scheduleID,
                                                                windowStart: windowStart)
            }
            return
        }
        // 点击通知默认打开计划窗口，方便查看本次结果与后续安排
        RecorderScheduleWindowController.shared.show()
    }
}
