@preconcurrency import AppKit
import Foundation
import Combine

/// NoTunesManager 拦截 Apple Music / iTunes 的自动启动，并可选择性拉起替代音乐应用或网页
@MainActor
public final class NoTunesManager: ObservableObject {
    public static let shared = NoTunesManager()

    @Published public private(set) var isMonitoring: Bool = false
    @Published public private(set) var blockedCount: Int = 0
    @Published public private(set) var lastBlockedDate: Date? = nil

    private var observer: (any NSObjectProtocol)?
    private var cancellables = Set<AnyCancellable>()

    private let targetBundleIdentifiers: Set<String> = [
        "com.apple.Music",
        "com.apple.iTunes"
    ]

    private init() {
        startMonitoring()
        bindSettings()
    }

    private func bindSettings() {
        AppSettings.shared.$noTunesEnabled
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled && AppSettings.shared.noTunesTerminateOnEnable {
                    self.terminateRunningMusicApps()
                }
            }
            .store(in: &cancellables)
    }

    public func startMonitoring() {
        guard observer == nil else { return }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleId = app?.bundleIdentifier
            Task { @MainActor in
                self?.handleAppLaunch(bundleId: bundleId, app: app)
            }
        }

        isMonitoring = true

        if AppSettings.shared.noTunesEnabled && AppSettings.shared.noTunesTerminateOnEnable {
            terminateRunningMusicApps()
        }
    }

    public func stopMonitoring() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        isMonitoring = false
    }

    private func handleAppLaunch(bundleId: String?, app: NSRunningApplication?) {
        guard AppSettings.shared.noTunesEnabled else { return }
        guard let bundleId = bundleId, targetBundleIdentifiers.contains(bundleId) else { return }

        // 1. 强制终止 Apple Music / iTunes 启动
        app?.forceTerminate()
        blockedCount += 1
        lastBlockedDate = Date()

        // 2. 如果配置了替代应用或 URL，执行拉起
        launchReplacement()
    }

    /// 扫描当前运行的应用并强制关闭已启动的 Apple Music / iTunes
    @discardableResult
    public func terminateRunningMusicApps() -> Int {
        var count = 0
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            if let bundleId = app.bundleIdentifier, targetBundleIdentifiers.contains(bundleId) {
                app.forceTerminate()
                count += 1
            }
        }
        return count
    }

    /// 执行替代目标启动
    public func launchReplacement() {
        let settings = AppSettings.shared
        guard settings.noTunesReplacementType != .none else { return }

        let target = settings.noTunesReplacementTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }

        switch settings.noTunesReplacementType {
        case .none:
            break

        case .app:
            // 支持本地 .app 文件路径或通过 open 命令
            if FileManager.default.fileExists(atPath: target) {
                let appURL = URL(fileURLWithPath: target)
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            } else {
                // 尝试作为名称或 Bundle 打开
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments = ["-a", target]
                try? task.run()
            }

        case .url:
            var urlString = target
            if !urlString.lowercased().hasPrefix("http://") && !urlString.lowercased().hasPrefix("https://") {
                urlString = "https://" + urlString
            }
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
