import AppKit
import Combine
import CoreAudio
import Foundation

// MARK: - 音频混音服务

/// 按应用音量/静音/输出路由的真实实现。
/// 因 macOS 的进程级音频必须在 `mutedWhenTapped` 的私有 tap 里重新渲染，
/// 这里为每个需要接管的应用建立一个 `AudioTapEngine`；100% 且跟随系统时
/// 完全不接管，应用保持系统原生播放路径。
@MainActor
final class AudioMixerService: ObservableObject {
    static let shared = AudioMixerService()

    /// 进程 tap 与聚合设备从 macOS 14.4 起才稳定可用。
    static var isSupported: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }

    static let maxVolume: Double = 2.0

    @Published private(set) var apps: [AudioAppInfo] = []
    @Published private(set) var outputDevices: [AudioOutputDeviceInfo] = []
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var systemOutputName: String = "未检测到输出设备"
    @Published private(set) var systemVolume: Double = 0
    @Published private(set) var systemMuted: Bool = false
    @Published var showsInactiveApps: Bool = false

    /// 14.4 才可用的 Tap 引擎容器，用类型擦除避免整个服务被标注可用性
    private var engineStoreObject: AnyObject?
    private var defaultOutputUID: String?
    private var refreshTimer: Timer?
    private var iconCache: [pid_t: NSImage] = [:]
    private var isRefreshing = false

    private let defaults = UserDefaults.standard
    private var storedVolumes: [String: Double] = [:]
    private var storedMutes: [String: Bool] = [:]
    private var storedRoutes: [String: String] = [:]
    /// 静音前的系统输出音量，用于取消静音时恢复
    private var systemVolumeBeforeMute: Double?

    /// 系统声音、电话等受保护音频不接管，避免影响系统提示音与通话。
    private static let protectedBundleIDs: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.SystemUIServer",
        "com.apple.audio.AudioComponentRegistrar",
        "com.apple.loginwindow",
        "com.apple.UserNotificationCenter",
        "com.apple.telephonyutilities.callservicesd",
        "com.apple.CallKit.CallCenter",
        "com.apple.avconferenced",
    ]

    private init() {
        loadPersistedState()
    }

    // MARK: - 生命周期

    func start() {
        guard AudioMixerService.isSupported else {
            lastError = "当前系统版本不支持按应用控制音频（需 macOS 14.4 及以上）"
            return
        }
        guard !isRunning else {
            refresh()
            return
        }
        isRunning = true
        lastError = nil
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        if let timer = refreshTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        isRunning = false
        if #available(macOS 14.4, *) {
            engineStore.removeAll()
        }
        apps = []
        systemMuted = false
    }

    // MARK: - 刷新

    func refresh() {
        guard isRunning, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let settings = AppSettings.shared
        let excluded = Set(settings.audioExcludedBundleIDs.map { $0.lowercased() })
            .union(Self.protectedBundleIDs.map { $0.lowercased() })
        let ownPid = NSRunningApplication.current.processIdentifier

        let devices = AudioCore.outputDevices()
        let deviceUID = devices.first(where: \.isDefault)?.uid
        defaultOutputUID = deviceUID
        outputDevices = devices
        let availableUIDs = Set(devices.map(\.uid))

        if let defaultDevice = AudioCore.defaultOutputDeviceID() {
            systemOutputName = AudioCore.deviceName(defaultDevice) ?? "输出设备"
            systemVolume = AudioCore.outputVolume(defaultDevice) ?? 0
            systemMuted = AudioCore.isOutputMuted(defaultDevice) ?? false
        } else {
            systemOutputName = "未检测到输出设备"
            systemVolume = 0
            systemMuted = false
        }

        var groups: [pid_t: (app: NSRunningApplication, objects: [AudioObjectID], playing: Bool,
                             bundleID: String?)] = [:]
        for object in AudioCore.processObjects() {
            guard let pid = AudioCore.pid(of: object), pid != ownPid,
                  let app = AudioProcessResolver.owner(of: pid) else { continue }
            let owner = app.processIdentifier
            let bundleID = app.bundleIdentifier ?? (pid == owner ? AudioCore.bundleIdentifier(of: object) : nil)
            if let bundleID, excluded.contains(bundleID.lowercased()) { continue }
            var entry = groups[owner] ?? (app, [], false, bundleID)
            entry.objects.append(object)
            entry.playing = entry.playing || AudioCore.isRunningOutput(object)
            if entry.bundleID == nil { entry.bundleID = bundleID }
            groups[owner] = entry
        }

        // 同一应用可能有多个 responsible PID（Chrome 主进程 + helper），必须按应用 id 合并，
        // 否则同一 id 会对应多行、多个引擎互相顶替，造成每秒重建与音频卡顿。
        var merged: [String: (app: NSRunningApplication, objects: [AudioObjectID], playing: Bool,
                              bundleID: String?, pid: pid_t)] = [:]
        for (owner, entry) in groups {
            let id = entry.bundleID ?? "pid:\(owner)"
            if var existing = merged[id] {
                existing.objects.append(contentsOf: entry.objects)
                existing.playing = existing.playing || entry.playing
                merged[id] = existing
            } else {
                merged[id] = (entry.app, entry.objects, entry.playing, entry.bundleID, owner)
            }
        }

        var stateChanged = false
        var next: [AudioAppInfo] = merged.map { id, entry in
            let bundleID = entry.bundleID
            let name = entry.app.localizedName ?? "进程 \(entry.pid)"
            let protected = bundleID.map { excluded.contains($0.lowercased()) } ?? false
            let volume = storedVolumes[id] ?? 1
            var muted = storedMutes[id] ?? false
            var route = settings.audioRoutingEnabled ? storedRoutes[id] : nil

            // BR-13：路由设备已断开时按用户策略回退
            if let uid = route, !availableUIDs.contains(uid) {
                switch settings.audioRoutingFallback {
                case .followDefault:
                    route = nil
                    storedRoutes.removeValue(forKey: id)
                    stateChanged = true
                case .pauseApp:
                    muted = true
                    storedMutes[id] = true
                    stateChanged = true
                case .alertOnly:
                    // 保留原路由，由引擎构建失败的错误文案提示用户
                    break
                }
            }

            return AudioAppInfo(
                id: id,
                bundleID: bundleID,
                pid: entry.pid,
                name: name,
                audioObjectIDs: entry.objects.sorted(),
                isPlaying: entry.playing,
                isProtected: protected,
                volume: min(max(volume, 0), boostUpperBoundGain),
                isMuted: muted,
                outputDeviceUID: route,
                icon: icon(for: entry.pid)
            )
        }
        if stateChanged { persistState() }
        next.sort { lhs, rhs in
            if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        apps = next

        reconcileEngines(apps: next)
    }

    // MARK: - 调节接口

    var activeApps: [AudioAppInfo] { apps.filter(\.isPlaying) }
    var routedAppCount: Int { apps.filter { $0.outputDeviceUID != nil }.count }

    var boostUpperBound: Int {
        let settings = AppSettings.shared
        return settings.audioBoostEnabled ? max(100, min(200, settings.audioBoostMaxPercent)) : 100
    }

    /// 音量倍率上限：100% → 1.0，200% → 2.0
    var boostUpperBoundGain: Double { Double(boostUpperBound) / 100 }

    func setVolume(_ volume: Double, for appID: String) {
        let clamped = min(max(volume, 0), boostUpperBoundGain)
        storedVolumes[appID] = clamped
        if let index = apps.firstIndex(where: { $0.id == appID }) {
            apps[index].volume = clamped
            if clamped > 0, apps[index].isMuted {
                apps[index].isMuted = false
                storedMutes[appID] = false
            }
        }
        persistState()
        applyEngineUpdates()
    }

    func setMuted(_ muted: Bool, for appID: String) {
        storedMutes[appID] = muted
        if let index = apps.firstIndex(where: { $0.id == appID }) {
            apps[index].isMuted = muted
        }
        persistState()
        applyEngineUpdates()
    }

    func toggleMute(for appID: String) {
        let current = apps.first { $0.id == appID }?.isMuted ?? false
        setMuted(!current, for: appID)
    }

    func setOutputDevice(_ uid: String?, for appID: String) {
        guard AppSettings.shared.audioRoutingEnabled else { return }
        if let uid {
            storedRoutes[appID] = uid
        } else {
            storedRoutes.removeValue(forKey: appID)
        }
        if let index = apps.firstIndex(where: { $0.id == appID }) {
            apps[index].outputDeviceUID = uid
        }
        persistState()
        reconcileEngines(apps: apps)
    }

    func resetAllApps() {
        storedVolumes.removeAll()
        storedMutes.removeAll()
        storedRoutes.removeAll()
        persistState()
        for index in apps.indices {
            apps[index].volume = 1
            apps[index].isMuted = false
            apps[index].outputDeviceUID = nil
        }
        reconcileEngines(apps: apps)
    }

    func toggleSystemMute() {
        if systemMuted {
            // 静音时曾把音量写为 0，取消静音必须回写原音量，否则设备依旧无声
            let restore = systemVolumeBeforeMute ?? max(systemVolume, 0.25)
            _ = AudioCore.setSystemMuted(false)
            _ = AudioCore.setSystemVolume(restore)
            systemVolume = min(max(restore, 0), 1)
            systemMuted = false
            systemVolumeBeforeMute = nil
        } else {
            systemVolumeBeforeMute = systemVolume
            _ = AudioCore.setSystemMuted(true)
            _ = AudioCore.setSystemVolume(0)
            systemVolume = 0
            systemMuted = true
        }
    }

    func setSystemVolume(_ volume: Double) {
        _ = AudioCore.setSystemVolume(volume)
        systemVolume = min(max(volume, 0), 1)
        if systemVolume > 0.001 {
            systemMuted = false
            systemVolumeBeforeMute = nil
        }
    }

    func setSystemOutputDevice(_ uid: String) {
        _ = AudioCore.setDefaultOutputDevice(uid)
        refresh()
    }

    // MARK: - 引擎协调

    private func needsEngine(_ app: AudioAppInfo) -> Bool {
        guard AppSettings.shared.audioHubEnabled, !app.isProtected else { return false }
        let settings = AppSettings.shared
        if app.isMuted { return true }
        if app.volume != 1.0 { return true }
        if settings.audioRoutingEnabled, let uid = app.outputDeviceUID,
           uid != defaultOutputUID { return true }
        return false
    }

    private var maxRoutedApps: Int {
        max(1, AppSettings.shared.audioRoutingMaxApps)
    }

    private func applyEngineUpdates() {
        guard isRunning, #available(macOS 14.4, *) else { return }
        for app in apps {
            guard let engine = engineStore.engines[app.id] else { continue }
            let gain = app.isMuted ? 0 : app.volume
            engine.update(gain: Float(gain), muted: false)
        }
        reconcileEngines(apps: apps)
    }

    private func reconcileEngines(apps current: [AudioAppInfo]) {
        guard #available(macOS 14.4, *) else { return }
        let allowedRoutes = maxRoutedApps
        var routedCount = 0
        var desiredIDs = Set<String>()
        let now = Date()

        for app in current {
            guard needsEngine(app) else { continue }
            let targetUID: String
            if let uid = app.outputDeviceUID, AppSettings.shared.audioRoutingEnabled,
               uid != defaultOutputUID {
                guard routedCount < allowedRoutes else { continue }
                routedCount += 1
                targetUID = uid
            } else {
                guard let defaultOutputUID else { continue }
                targetUID = defaultOutputUID
            }

            desiredIDs.insert(app.id)
            let key = app.audioObjectIDs.sorted().map(String.init).joined(separator: ",")

            if let existing = engineStore.engines[app.id],
               existing.outputDeviceUID == targetUID,
               existing.objectKey == key {
                engineStore.missingSince.removeValue(forKey: app.id)
                engineStore.pending.removeValue(forKey: app.id)
                existing.update(gain: Float(app.isMuted ? 0 : app.volume), muted: false)
                if isWedged(app: app, engine: existing) {
                    engineStore.engines.removeValue(forKey: app.id)
                    existing.stop()
                }
                continue
            }

            // 睡眠唤醒后聚合设备可能“假运行”：IOProc 不再推进，但 tap 仍在静音应用。
            if let existing = engineStore.engines[app.id], isWedged(app: app, engine: existing) {
                engineStore.engines.removeValue(forKey: app.id)
                existing.stop()
            }
            // 先让旧引擎继续发声，新引擎在后台构建成功后再替换，避免重建间隙的静默。
            scheduleBuild(app: app, targetUID: targetUID, now: now)
        }

        for (id, engine) in Array(engineStore.engines) where !desiredIDs.contains(id) {
            if let app = apps.first(where: { $0.id == id }), !needsEngine(app) {
                discardEngine(id: id, engine: engine)
                continue
            }
            // 应用重建音频单元时对象会短暂消失，宽限一小段时间再销毁，避免反复建拆。
            if let since = engineStore.missingSince[id] {
                let window: TimeInterval = 0.3
                if now.timeIntervalSince(since) >= window {
                    discardEngine(id: id, engine: engine)
                } else {
                    scheduleGraceRecheck(after: window - now.timeIntervalSince(since))
                }
            } else {
                engineStore.missingSince[id] = now
                scheduleGraceRecheck(after: 0.3)
            }
        }
    }

    /// 应用在播放但渲染回调次数没有增长，说明聚合设备已失效。
    @available(macOS 14.4, *)
    private func isWedged(app: AudioAppInfo, engine: AudioTapEngine) -> Bool {
        guard app.isPlaying else {
            engineStore.lastCycles.removeValue(forKey: app.id)
            engineStore.stalledPasses.removeValue(forKey: app.id)
            return false
        }
        let cycles = engine.renderCycles
        if let previous = engineStore.lastCycles[app.id], previous == cycles {
            let passes = (engineStore.stalledPasses[app.id] ?? 0) + 1
            engineStore.stalledPasses[app.id] = passes
            if passes >= 2 { return true }
        } else {
            engineStore.stalledPasses[app.id] = 0
        }
        engineStore.lastCycles[app.id] = cycles
        return false
    }

    @available(macOS 14.4, *)
    private func scheduleBuild(app: AudioAppInfo, targetUID: String, now: Date) {
        let objects = app.audioObjectIDs
        guard !objects.isEmpty else { return }
        if let failedAt = engineStore.failedAt[app.id], now.timeIntervalSince(failedAt) < 10 {
            return
        }
        let key = objects.sorted().map(String.init).joined(separator: ",")
        if let pending = engineStore.pending[app.id],
           pending.objectKey == key, pending.outputUID == targetUID {
            return
        }
        engineStore.token += 1
        let token = engineStore.token
        let appID = app.id
        let name = app.name
        engineStore.pending[appID] = PendingBuild(token: token, objectKey: key, outputUID: targetUID)
        AudioDebug.log("build start app=\(name) key=\(key)")
        Self.buildQueue.async { [weak self] in
            let engine = AudioTapEngine(objects: objects, outputDeviceUID: targetUID, gain: 1, muted: false)
            DispatchQueue.main.async {
                guard let self else {
                    engine?.stop()
                    return
                }
                self.installBuild(appID: appID, name: name, targetUID: targetUID,
                                  token: token, engine: engine)
            }
        }
    }

    @available(macOS 14.4, *)
    private func installBuild(appID: String, name: String, targetUID: String,
                              token: Int, engine: AudioTapEngine?) {
        guard isRunning else {
            engine?.stop()
            return
        }
        guard let pending = engineStore.pending[appID], pending.token == token else {
            engine?.stop()
            return
        }
        engineStore.pending.removeValue(forKey: appID)
        guard let latest = apps.first(where: { $0.id == appID }), needsEngine(latest) else {
            engine?.stop()
            return
        }
        let latestKey = latest.audioObjectIDs.sorted().map(String.init).joined(separator: ",")
        let latestTarget: String?
        if let uid = latest.outputDeviceUID, AppSettings.shared.audioRoutingEnabled, uid != defaultOutputUID {
            latestTarget = uid
        } else {
            latestTarget = defaultOutputUID
        }
        guard latestKey == pending.objectKey, latestTarget == pending.outputUID else {
            // 构建期间目标已改变，按最新状态重新协调
            engine?.stop()
            reconcileEngines(apps: apps)
            return
        }
        guard let engine else {
            AudioDebug.log("build failed app=\(name)")
            engineStore.failedAt[appID] = Date()
            lastError = "无法接管「\(name)」的音频输出，请检查系统音频录制权限"
            return
        }
        AudioDebug.log("build installed app=\(name) gain=\(latest.volume)")
        engineStore.failedAt.removeValue(forKey: appID)
        lastError = nil
        engine.update(gain: Float(latest.isMuted ? 0 : latest.volume), muted: false)
        if let previous = engineStore.engines.updateValue(engine, forKey: appID) {
            previous.stop()
        }
        engineStore.lastCycles.removeValue(forKey: appID)
        engineStore.stalledPasses.removeValue(forKey: appID)
    }

    @available(macOS 14.4, *)
    private func discardEngine(id: String, engine: AudioTapEngine) {
        AudioDebug.log("discard engine id=\(id)")
        engineStore.engines.removeValue(forKey: id)
        engineStore.pending.removeValue(forKey: id)
        engineStore.lastCycles.removeValue(forKey: id)
        engineStore.stalledPasses.removeValue(forKey: id)
        engineStore.missingSince.removeValue(forKey: id)
        engineStore.failedAt.removeValue(forKey: id)
        engine.stop()
    }

    @available(macOS 14.4, *)
    private func scheduleGraceRecheck(after delay: TimeInterval) {
        guard !engineStore.graceScheduled else { return }
        engineStore.graceScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0.05)) { [weak self] in
            guard let self, self.isRunning else { return }
            self.engineStore.graceScheduled = false
            self.reconcileEngines(apps: self.apps)
        }
    }

    // MARK: - 持久化

    private func loadPersistedState() {
        if let dict = defaults.dictionary(forKey: "audio.appVolumes") {
            storedVolumes = dict.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        }
        if let dict = defaults.dictionary(forKey: "audio.appMutes") {
            storedMutes = dict.compactMapValues { ($0 as? NSNumber)?.boolValue }
        }
        if let dict = defaults.dictionary(forKey: "audio.appRoutes") {
            storedRoutes = dict.compactMapValues { $0 as? String }
        }
    }

    private func persistState() {
        defaults.set(storedVolumes, forKey: "audio.appVolumes")
        defaults.set(storedMutes, forKey: "audio.appMutes")
        defaults.set(storedRoutes, forKey: "audio.appRoutes")
    }

    @available(macOS 14.4, *)
    private var engineStore: AudioEngineStore {
        if let existing = engineStoreObject as? AudioEngineStore { return existing }
        let store = AudioEngineStore()
        engineStoreObject = store
        return store
    }

    private func icon(for pid: pid_t) -> NSImage? {
        if let cached = iconCache[pid] { return cached }
        guard let image = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        iconCache[pid] = image
        if iconCache.count > 80 { iconCache.removeAll() }
        return image
    }
}

// MARK: - 自适应用户可见文案

extension AudioMixerService {
    @available(macOS 14.4, *)
    private final class AudioEngineStore {
        var engines: [String: AudioTapEngine] = [:]
        var pending: [String: PendingBuild] = [:]
        var token = 0
        var lastCycles: [String: UInt64] = [:]
        var stalledPasses: [String: Int] = [:]
        var missingSince: [String: Date] = [:]
        var failedAt: [String: Date] = [:]
        var graceScheduled = false

        func removeAll() {
            for engine in engines.values { engine.stop() }
            engines.removeAll()
            pending.removeAll()
            lastCycles.removeAll()
            stalledPasses.removeAll()
            missingSince.removeAll()
            failedAt.removeAll()
        }
    }

    @available(macOS 14.4, *)
    private struct PendingBuild {
        let token: Int
        let objectKey: String
        let outputUID: String
    }

    @available(macOS 14.4, *)
    private static let buildQueue = DispatchQueue(label: "com.chaoeng.CalmBar.audio.build",
                                                  qos: .userInitiated)

    var statusSummary: String {
        if !isRunning { return "已停用" }
        if let lastError { return lastError }
        return "\(apps.count) 个应用 · \(routedAppCount) 个已路由"
    }

    /// 显示用行：按「正在播放优先」排序，最多 limit 行。
    func displayRows(limit: Int) -> [AudioAppInfo] {
        let source = showsInactiveApps
            ? apps
            : (apps.filter(\.isPlaying) + apps.filter { !$0.isPlaying && $0.volume != 1 })
        return Array(source.prefix(limit))
    }
}
