import AppKit
import Combine
import Foundation
import UserNotifications

// MARK: - 告警引擎（通知投递 / 权限降级 / 免打扰）

@MainActor
final class MonitorAlertEngine: ObservableObject {
    static let shared = MonitorAlertEngine()

    @Published private(set) var degradedAlert: MonitorAlertEvent?
    @Published private(set) var notificationAuthorization: UNAuthorizationStatus = .notDetermined

    private let settings = AppSettings.shared
    private var gate = MonitorAlertGate(rules: [])
    private let delegate = MonitorNotificationDelegate()

    /// 未打包为 .app 时（如直接运行 SwiftPM 产物）通知中心不可用，需要降级为面板内提示
    private static var isNotificationAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private init() {
        gate.updateRules(Self.rules(from: settings))
        guard Self.isNotificationAvailable else { return }
        UNUserNotificationCenter.current().delegate = delegate
        Task { await refreshAuthorization() }
    }

    /// 采样回调入口（仅由 SystemMonitorService 在主线程调用）
    func ingest(_ sample: MonitorSample, now: Date = Date()) {
        guard settings.systemMonitorEnabled, settings.monitorAlertsEnabled else {
            gate.resetTracking()
            return
        }
        // BR-29：睡眠、锁屏、熄屏期间丢弃确认进度，唤醒后不补发
        guard SystemEventCoordinator.shared.isOperational else {
            gate.resetTracking()
            return
        }

        gate.updateRules(Self.rules(from: settings))
        let events = gate.ingest(
            sample,
            now: now,
            isExternalPowerConnected: BatteryMonitor.shared.isACPowered
        )
        for event in events {
            deliver(event)
        }
    }

    func dismissDegradedAlert() {
        degradedAlert = nil
    }

    /// 睡眠 / 锁屏期间丢弃确认进度（冷却记录保留）
    func resetTracking() {
        gate.resetTracking()
    }

    func refreshAuthorization() async {
        guard Self.isNotificationAvailable else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorization = settings.authorizationStatus
    }

    func requestAuthorization() {
        guard Self.isNotificationAvailable else { return }
        Task { _ = await requestAuthorizationStatus() }
    }

    /// 请求权限并返回最新状态，供投递端按结果决定是否降级
    private func requestAuthorizationStatus() async -> UNAuthorizationStatus {
        guard Self.isNotificationAvailable else { return .denied }
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        await refreshAuthorization()
        return notificationAuthorization
    }

    // MARK: 规则构建

    static func rules(from settings: AppSettings) -> [MonitorAlertRule] {
        let cooldown = settings.monitorAlertCooldownMinutes * 60
        return [
            MonitorAlertRule(
                type: .cpu,
                isEnabled: settings.monitorAlertCPU,
                threshold: settings.monitorAlertCPUThreshold,
                sustainSeconds: settings.monitorAlertCPUDuration,
                cooldownSeconds: cooldown
            ),
            MonitorAlertRule(
                type: .memory,
                isEnabled: settings.monitorAlertMemory,
                threshold: 0,
                sustainSeconds: settings.monitorAlertMemoryDuration,
                cooldownSeconds: cooldown
            ),
            MonitorAlertRule(
                type: .disk,
                isEnabled: settings.monitorAlertDisk,
                threshold: settings.monitorAlertDiskFreeGB,
                sustainSeconds: 0,
                cooldownSeconds: cooldown
            ),
            MonitorAlertRule(
                type: .battery,
                isEnabled: settings.monitorAlertBattery,
                threshold: Double(settings.monitorAlertBatteryThreshold),
                sustainSeconds: 0,
                cooldownSeconds: cooldown
            ),
            MonitorAlertRule(
                type: .temperature,
                isEnabled: settings.monitorAlertTemperature,
                threshold: settings.monitorAlertTemperatureThreshold,
                sustainSeconds: 10,
                cooldownSeconds: cooldown
            )
        ]
    }

    // MARK: 通知投递

    private func deliver(_ event: MonitorAlertEvent) {
        // 未打包运行时无法投递系统通知，直接降级为面板内橙色胶囊
        guard Self.isNotificationAvailable else {
            degradedAlert = event
            return
        }
        switch notificationAuthorization {
        case .authorized, .provisional:
            post(event)
        case .denied:
            degradedAlert = event
        case .notDetermined:
            // 授权结果是异步返回的，必须等真实结果再决定投递或降级
            Task { [weak self] in
                guard let self else { return }
                let status = await self.requestAuthorizationStatus()
                switch status {
                case .authorized, .provisional:
                    self.post(event)
                default:
                    self.degradedAlert = event
                }
            }
        @unknown default:
            degradedAlert = event
        }
    }

    private func post(_ event: MonitorAlertEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.titleZH
        content.body = event.message
        content.sound = .default
        content.userInfo = ["monitorTab": event.type.rawValue]

        let request = UNNotificationRequest(
            identifier: "calmbar.monitor.\(event.type.rawValue).\(Int(event.firedAt.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - 通知点击跳转监控分区

final class MonitorNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 采样端已在睡眠 / 锁屏期间抑制投递，这里只负责展示样式
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
        Task { @MainActor in
            StatusBarManager.shared.showPopover()
            _ = StatusBarManager.shared.selectPopoverTab(.monitor)
        }
    }
}
