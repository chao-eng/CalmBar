import Foundation
import UserNotifications

// MARK: - 计划通知

/// 录制计划的通知分类、授权与投递。
/// 非 .app 运行时通知中心不可用，沿用监控模块的降级判断，由窗口内状态兜底。
@MainActor
public final class RecorderScheduleNotifier: ObservableObject {
    public static let shared = RecorderScheduleNotifier()

    public static let categoryIdentifier = "calmbar.recorder.schedule"
    public static let skipActionIdentifier = "calmbar.recorder.schedule.skip"
    public static let identifierPrefix = "calmbar.recorder."

    @Published public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    public static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private init() {}

    // MARK: 分类与授权

    public func registerCategories() {
        guard Self.isAvailable else { return }
        let skip = UNNotificationAction(
            identifier: Self.skipActionIdentifier,
            title: "跳过本次",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [skip],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    public func refreshAuthorization() async {
        guard Self.isAvailable else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// 创建第一个计划时请求授权；已决定过则直接返回当前状态。
    @discardableResult
    public func requestAuthorizationIfNeeded() async -> UNAuthorizationStatus {
        guard Self.isAvailable else {
            authorizationStatus = .denied
            return .denied
        }
        await refreshAuthorization()
        switch authorizationStatus {
        case .notDetermined:
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
        default:
            break
        }
        return authorizationStatus
    }

    public var isDegraded: Bool {
        if !Self.isAvailable { return true }
        switch authorizationStatus {
        case .denied: return true
        default: return false
        }
    }

    // MARK: 投递

    public func postReminder(for schedule: RecorderSchedule, window: DateInterval) {
        let range = "\(Self.clock(window.start))–\(Self.clock(window.end))"
        let body = "录制计划将在 5 分钟后开始（\(range)，\(schedule.source.kindTitle)）。"
            + "为保证录制不中断，期间系统将保持唤醒。"
        post(identifier: "\(Self.identifierPrefix)reminder.\(schedule.id.uuidString).\(Int(window.start.timeIntervalSince1970))",
             title: "录制计划即将开始",
             body: body,
             scheduleID: schedule.id,
             category: Self.categoryIdentifier,
             userInfo: [
                "action": "reminder",
                "windowStart": String(window.start.timeIntervalSince1970),
             ])
    }

    public func postStarted(for schedule: RecorderSchedule, window: DateInterval) {
        let body = "\(schedule.trimmedName)：计划录制已开始，\(Self.clock(window.end)) 自动停止。期间系统将保持唤醒。"
        post(identifier: "\(Self.identifierPrefix)started.\(schedule.id.uuidString).\(Int(window.start.timeIntervalSince1970))",
             title: "计划录制已开始",
             body: body,
             scheduleID: schedule.id,
             category: nil,
             userInfo: [:])
    }

    public func postFinished(for schedule: RecorderSchedule, recording: RecorderRecording?) {
        let body: String
        if let recording {
            body = "计划录制已结束，已保存 \(recording.fileName)（时长 \(recording.formattedDuration)）。"
        } else {
            body = "计划录制已结束，但未能生成可播放文件，可在录制设置中检查临时文件。"
        }
        post(identifier: "\(Self.identifierPrefix)finished.\(schedule.id.uuidString).\(Int(Date().timeIntervalSince1970))",
             title: "计划录制已结束",
             body: body,
             scheduleID: schedule.id,
             category: nil,
             userInfo: [:])
    }

    public func postSkipped(for schedule: RecorderSchedule, reason: RecorderScheduleSkipReason) {
        postSkipped(for: schedule, message: reason.message)
    }

    public func postSkipped(for schedule: RecorderSchedule, message: String) {
        post(identifier: "\(Self.identifierPrefix)skipped.\(schedule.id.uuidString).\(Int(Date().timeIntervalSince1970))",
             title: "录制计划已跳过",
             body: "\(schedule.trimmedName)：\(message)",
             scheduleID: schedule.id,
             category: nil,
             userInfo: [:])
    }

    public func postResumed(for schedule: RecorderSchedule, window: DateInterval) {
        let body = "\(schedule.trimmedName)：已从睡眠恢复，计划录制继续（新文件）。\(Self.clock(window.end)) 自动停止。"
        post(identifier: "\(Self.identifierPrefix)resumed.\(schedule.id.uuidString).\(Int(Date().timeIntervalSince1970))",
             title: "计划录制继续",
             body: body,
             scheduleID: schedule.id,
             category: nil,
             userInfo: [:])
    }

    /// 手动录制时磁盘巡检触发，没有计划上下文。
    public func postDiskSpaceWarningForManualRecording() {
        post(identifier: "\(Self.identifierPrefix)disk.manual.\(Int(Date().timeIntervalSince1970))",
             title: "录制已停止",
             body: "磁盘可用空间不足 500MB，录制已停止并保存已有内容。",
             scheduleID: UUID(),
             category: nil,
             userInfo: [:])
    }

    private func post(identifier: String,
                      title: String,
                      body: String,
                      scheduleID: UUID,
                      category: String?,
                      userInfo: [String: String]) {
        guard Self.isAvailable else { return }
        guard !isDegraded else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var info = userInfo
        info["scheduleID"] = scheduleID.uuidString
        content.userInfo = info
        if let category {
            content.categoryIdentifier = category
        }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: 文案工具

    private static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
