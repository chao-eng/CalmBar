import Foundation
import Combine

@MainActor
public final class LaunchManager: ObservableObject {
    public static let shared = LaunchManager()

    @Published public private(set) var items: [LaunchItem] = []
    @Published public private(set) var listeningServices: [ListeningServiceItem] = []
    @Published public private(set) var backups: [LaunchBackupItem] = []
    @Published public private(set) var cronJobs: [CronJob] = []

    @Published public var isLoading: Bool = false
    @Published public var isScanningPorts: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public private(set) var crashLoopingItems: [LaunchItem] = []

    // 内存中的崩溃追踪字典 [Label: (count: Int, lastFailedAt: Date)]
    private var crashHistory: [String: (count: Int, lastFailedAt: Date)] = [:]
    // 崩溃统计窗口（秒）：窗口外的旧失败记录作废，重新开始计数
    private static let crashWindow: TimeInterval = 600
    // 崩溃计数去抖间隔（秒）：同一失败状态在该间隔内被重复轮询时不重复计数，避免刷新导致误报
    private static let crashDebounceInterval: TimeInterval = 60
    // 在途操作锁集合 (防止异步操作期间重复触发，操作结束后立即释放)
    @Published public private(set) var activeMutatingIds: Set<String> = []
    // 乐观状态保留覆盖 [Item.id: (isLoaded: Bool, isDisabled: Bool, expire: Date)] (BR-LM-01: 3秒内防止外部扫描覆盖乐观状态)
    private var optimisticOverrides: [String: (isLoaded: Bool, isDisabled: Bool, expire: Date)] = [:]

    private init() {}

    /// 统一全量刷新所有自启项与运行状态
    public func refreshAll() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let settings = AppSettings.shared

        // 1. 并发抓取各 Scope 目录下的 Plist 文件
        async let userItemsTask = LaunchPlistService.shared.scanScope(.userAgent)
        async let globalItemsTask = settings.launchManagerShowSystemDaemons
            ? LaunchPlistService.shared.scanScope(.systemAgent) : []
        async let daemonItemsTask = settings.launchManagerShowSystemDaemons
            ? LaunchPlistService.shared.scanScope(.systemDaemon) : []
        async let appleItemsTask = settings.launchManagerShowAppleProtected
            ? LaunchPlistService.shared.scanScope(.appleSystem) : []

        // 2. 抓取运行态与禁用态 (包括 GUI 用户域与 System 系统守护域)
        async let runningUserTask = (try? LaunchctlService.shared.listAll()) ?? [:]
        async let runningSystemTask = LaunchctlService.shared.listSystemServices()
        async let disabledUserTask = (try? LaunchctlService.shared.fetchDisabledLabels(domain: LaunchScope.userAgent.launchdDomain)) ?? []
        async let disabledSysTask = (try? LaunchctlService.shared.fetchDisabledLabels(domain: "system")) ?? []

        let (userItems, globalItems, daemonItems, appleItems) = await (userItemsTask, globalItemsTask, daemonItemsTask, appleItemsTask)
        let (runningUserMap, runningSystemMap, disabledUser, disabledSys) = await (runningListTask: runningUserTask, runningSystemTask, disabledUserTask, disabledSysTask)

        var combined = userItems + globalItems + daemonItems + appleItems
        let now = Date()
        let threshold = settings.launchManagerCrashLoopAlertThreshold

        // 3. 聚合运行状态并应用 BR-LM-01 (锁定中的状态不被旧快照覆盖)
        for i in 0..<combined.count {
            let label = combined[i].label
            let itemId = combined[i].id
            let isSystemDomain = combined[i].scope.launchdDomain == "system"

            // 检查在途异步操作
            combined[i].isMutating = activeMutatingIds.contains(itemId)

            // 检查乐观状态覆盖 (BR-LM-01: 3秒内防止外部扫描覆盖乐观状态)
            if let override = optimisticOverrides[itemId] {
                if override.expire > now {
                    combined[i].isLoaded = override.isLoaded
                    combined[i].isDisabledByOverride = override.isDisabled
                    continue
                } else {
                    optimisticOverrides.removeValue(forKey: itemId)
                }
            }

            // 系统守护项从 system 域检索，用户项从 gui 域检索 (同时做兜底回退)
            let runtime = isSystemDomain
                ? (runningSystemMap[label] ?? runningUserMap[label])
                : (runningUserMap[label] ?? runningSystemMap[label])

            if let runtime {
                combined[i].isLoaded = true
                combined[i].pid = runtime.pid
                combined[i].lastExitCode = runtime.exitCode

                // 统计崩溃记录 (按时间窗 + 去抖累计，避免每次轮询刷新都重复自增造成误报)
                if let exitCode = runtime.exitCode, exitCode != 0, runtime.pid == nil {
                    let prev = crashHistory[label]
                    var count = prev?.count ?? 0
                    // 超出统计窗口的旧记录作废，重新开始计数
                    if let lastFailedAt = prev?.lastFailedAt,
                       now.timeIntervalSince(lastFailedAt) > Self.crashWindow {
                        count = 0
                    }
                    // 去抖：同一失败状态在去抖间隔内被重复轮询时不重复计数
                    let shouldCount = prev == nil
                        || now.timeIntervalSince(prev!.lastFailedAt) >= Self.crashDebounceInterval
                    if shouldCount { count += 1 }
                    crashHistory[label] = (count, now)
                    combined[i].crashCountWithinWindow = count
                } else if runtime.pid != nil {
                    // 恢复运行，清空崩溃记录
                    crashHistory.removeValue(forKey: label)
                    combined[i].crashCountWithinWindow = 0
                }
            } else {
                combined[i].isLoaded = false
                combined[i].pid = nil
            }

            let isDisabled = (isSystemDomain ? disabledSys : disabledUser).contains(label)
            combined[i].isDisabledByOverride = isDisabled
        }

        self.items = combined.sorted { $0.label.lowercased() < $1.label.lowercased() }
        self.crashLoopingItems = self.items.filter { $0.isCrashLooping(alertThreshold: threshold) }
        refreshBackups()
        refreshCrontab()
    }

    /// 刷新 Crontab 定时任务
    public func refreshCrontab() {
        self.cronJobs = CrontabService.shared.fetchAllJobs()
    }

    /// 切换 Crontab 任务状态 (启用 / 停用)
    public func toggleCronJob(_ job: CronJob) async {
        do {
            try await CrontabService.shared.toggleJob(job)
            refreshCrontab()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// 删除 Crontab 任务
    public func deleteCronJob(_ job: CronJob) async {
        do {
            try await CrontabService.shared.deleteJob(job)
            refreshCrontab()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// 新增 Crontab 任务
    public func addCronJob(_ job: CronJob) async {
        do {
            try await CrontabService.shared.addJob(job)
            refreshCrontab()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// 刷新本地监听端口列表
    public func refreshListeningPorts() async {
        isScanningPorts = true
        defer { isScanningPorts = false }
        do {
            self.listeningServices = try await PortDiscoveryService.shared.scanListeningPorts()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    /// 刷新快照列表
    public func refreshBackups() {
        self.backups = LaunchBackupService.shared.listBackups()
    }

    /// 切换启动项状态（启用 / 禁用）
    public func toggleItem(_ item: LaunchItem) async {
        guard !item.scope.isReadOnly else {
            errorMessage = LaunchServiceError.systemProtected.localizedDescription
            return
        }

        guard !activeMutatingIds.contains(item.id) else { return }
        activeMutatingIds.insert(item.id)
        updateItemLocally(id: item.id) { $0.isMutating = true }
        defer {
            activeMutatingIds.remove(item.id)
            updateItemLocally(id: item.id) { $0.isMutating = false }
        }

        let targetIsLoaded = !item.isLoaded
        // 设置 3 秒乐观状态覆盖，防止外部 launchctl 瞬态未同步时状态跳变
        optimisticOverrides[item.id] = (isLoaded: targetIsLoaded, isDisabled: !targetIsLoaded, expire: Date().addingTimeInterval(3.0))

        do {
            let domain = item.scope.launchdDomain
            let path = item.plistURL.path
            let escapedPath = LaunchPrivilegeService.escapeShellArg(path)
            let escapedTarget = LaunchPrivilegeService.escapeShellArg("\(domain)/\(item.label)")

            if item.isLoaded {
                // 卸载 (系统域合并为单条特权脚本，避免重复授权弹窗)
                if item.scope.requiresPrivilegeForService {
                    let cmd = "/bin/launchctl bootout \(domain) \(escapedPath) 2>/dev/null || /bin/launchctl bootout \(escapedTarget) 2>/dev/null || true ; /bin/launchctl disable \(escapedTarget) 2>/dev/null || true"
                    try await LaunchPrivilegeService.shared.runPrivileged(cmd)
                } else {
                    do {
                        try await LaunchctlService.shared.bootout(item.plistURL, scope: item.scope)
                    } catch {
                        try? await LaunchctlService.shared.bootout(label: item.label, scope: item.scope)
                    }
                    try? await LaunchctlService.shared.disable(label: item.label, scope: item.scope)
                }
                updateItemLocally(id: item.id) {
                    $0.isLoaded = false
                    $0.pid = nil
                    $0.isDisabledByOverride = true
                }
            } else {
                // 重新装载 (系统域合并为单条特权脚本，避免重复授权弹窗)
                if item.scope.requiresPrivilegeForService {
                    let cmd = "/bin/launchctl enable \(escapedTarget) 2>/dev/null || true ; /bin/launchctl bootstrap \(domain) \(escapedPath)"
                    try await LaunchPrivilegeService.shared.runPrivileged(cmd)
                } else {
                    try? await LaunchctlService.shared.enable(label: item.label, scope: item.scope)
                    try await LaunchctlService.shared.bootstrap(item.plistURL, scope: item.scope)
                }
                updateItemLocally(id: item.id) {
                    $0.isLoaded = true
                    $0.isDisabledByOverride = false
                }
            }
            await refreshAll()
        } catch {
            errorMessage = error.localizedDescription
            optimisticOverrides.removeValue(forKey: item.id)
        }
    }

    /// 原子重载服务
    public func reloadItem(_ item: LaunchItem) async {
        guard !item.scope.isReadOnly else {
            errorMessage = LaunchServiceError.systemProtected.localizedDescription
            return
        }

        guard !activeMutatingIds.contains(item.id) else { return }
        activeMutatingIds.insert(item.id)
        updateItemLocally(id: item.id) { $0.isMutating = true }
        defer {
            activeMutatingIds.remove(item.id)
            updateItemLocally(id: item.id) { $0.isMutating = false }
        }

        do {
            try await LaunchctlService.shared.reloadAtomic(item: item)
            await refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 优雅终结进程
    public func killProcess(of item: LaunchItem) async {
        guard !item.scope.isReadOnly else { return }
        do {
            try await LaunchctlService.shared.killGracefully(item: item)
            await refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 删除启动项 (操作前自动快照归档，合并特权事务杜绝二次密码弹窗)
    public func deleteItem(_ item: LaunchItem) async {
        guard !item.scope.isReadOnly else {
            errorMessage = LaunchServiceError.systemProtected.localizedDescription
            return
        }

        guard !activeMutatingIds.contains(item.id) else { return }
        activeMutatingIds.insert(item.id)
        updateItemLocally(id: item.id) { $0.isMutating = true }
        defer {
            activeMutatingIds.remove(item.id)
            updateItemLocally(id: item.id) { $0.isMutating = false }
        }

        do {
            // 1. 自动备份 (本地临时目录复制，无需特权)
            if AppSettings.shared.launchManagerAutoBackupEnabled {
                _ = try LaunchBackupService.shared.createBackup(of: item.plistURL, label: item.label, scope: item.scope)
                refreshBackups()
            }

            let domain = item.scope.launchdDomain
            let path = item.plistURL.path
            let escapedPath = LaunchPrivilegeService.escapeShellArg(path)
            let escapedTarget = LaunchPrivilegeService.escapeShellArg("\(domain)/\(item.label)")

            // 2. 卸载与删除文件 (若需特权，合并为单条事务执行，只弹一次密码框)
            if item.scope.requiresPrivilegeForService || item.scope.requiresPrivilegeForFile {
                var scriptCommands: [String] = []
                if item.isLoaded {
                    scriptCommands.append("/bin/launchctl bootout \(domain) \(escapedPath) 2>/dev/null || /bin/launchctl bootout \(escapedTarget) 2>/dev/null || true")
                    scriptCommands.append("/bin/launchctl disable \(escapedTarget) 2>/dev/null || true")
                }
                scriptCommands.append("rm -f \(escapedPath)")

                let singleScript = scriptCommands.joined(separator: " ; ")
                try await LaunchPrivilegeService.shared.runPrivileged(singleScript)
            } else {
                if item.isLoaded {
                    _ = try? ShellRunner.run("/bin/launchctl", arguments: ["bootout", domain, path])
                    _ = try? ShellRunner.run("/bin/launchctl", arguments: ["disable", "\(domain)/\(item.label)"])
                }
                if FileManager.default.fileExists(atPath: path) {
                    try FileManager.default.removeItem(at: item.plistURL)
                }
            }

            await refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 将本地监听服务转为自启 Agent
    public func createAgent(from service: ListeningServiceItem) async {
        let (destURL, dict) = LaunchPlistService.shared.generateAgentDict(from: service)
        do {
            try LaunchPlistService.shared.writeDictionary(dict, to: destURL)
            try await LaunchctlService.shared.bootstrap(destURL, scope: .userAgent)
            await refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 还原指定历史快照
    public func restoreBackup(_ backup: LaunchBackupItem, targetScope: LaunchScope) async {
        let targetURL = targetScope.directoryURL!.appendingPathComponent("\(backup.label).plist")
        do {
            // 1. 恢复文件到目标目录
            try await LaunchBackupService.shared.restoreBackup(backup.fileURL, to: targetURL, scope: targetScope)

            // 2. 还原成功后，立即删除快照并刷新快照列表
            try? LaunchBackupService.shared.deleteBackup(backup.fileURL)
            refreshBackups()

            // 3. 优雅重新装载服务到 launchd (先 bootout 避免 error 5，再 bootstrap)
            if !targetScope.isReadOnly {
                _ = try? await LaunchctlService.shared.bootout(targetURL, scope: targetScope)
                _ = try? await LaunchctlService.shared.bootout(label: backup.label, scope: targetScope)
                _ = try? await LaunchctlService.shared.bootstrap(targetURL, scope: targetScope)
            }

            await refreshAll()
        } catch {
            errorMessage = error.localizedDescription
            refreshBackups()
        }
    }

    // MARK: - State Helpers

    private func updateItemLocally(id: String, update: (inout LaunchItem) -> Void) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            update(&items[idx])
        }
    }
}
