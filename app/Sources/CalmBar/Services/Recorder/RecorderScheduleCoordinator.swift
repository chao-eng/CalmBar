import AppKit
import Combine
import CoreGraphics
import Foundation
import ScreenCaptureKit
import UserNotifications

// MARK: - 计划调度器

/// 统一处理「保持唤醒 / 该开始 / 该结束」：
/// 15 秒 tick 是唯一节拍，睡眠唤醒、解锁、时钟变更与 App 激活时立即重算。
@MainActor
public final class RecorderScheduleCoordinator: ObservableObject {
    public static let shared = RecorderScheduleCoordinator()

    @Published public private(set) var schedules: [RecorderSchedule] = []
    @Published public private(set) var activeRun: RecorderScheduleActiveRun?
    @Published public private(set) var isPendingUnlock: Bool = false
    @Published public private(set) var lastEventMessage: String?

    public let notifier: RecorderScheduleNotifier
    private let store: RecorderScheduleStore
    private let engine: RecorderScheduleEngine
    private let recorder: ScreenRecorderService
    private let powerAssertion = RecorderSchedulePowerAssertion.shared

    private var tickTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var started = false

    private var handledOccurrenceKeys: Set<String> = []
    private var remindedOccurrenceKeys: Set<String> = []
    private var pendingUnlockKey: String?
    private var pendingUnlockScheduleID: UUID?
    private var pendingUnlockWindow: DateInterval?

    private var isEndingScheduledRun = false
    private var isStartingRun = false
    private var didPauseForLock = false
    private var isShuttingDown = false
    private var didRestorePersistedRun = false
    private var awaitingRestartConfirmation = false

    private init(store: RecorderScheduleStore = RecorderScheduleStore(),
                 engine: RecorderScheduleEngine = RecorderScheduleEngine(),
                 recorder: ScreenRecorderService = .shared,
                 notifier: RecorderScheduleNotifier = .shared) {
        self.store = store
        self.engine = engine
        self.recorder = recorder
        self.notifier = notifier
        // 即使功能总开关关闭，也让设置页与计划窗口能看到已保存的计划
        schedules = store.loadSchedules()
    }

    // MARK: 生命周期

    public func start() {
        guard !started else {
            tick()
            return
        }
        started = true
        loadPersistedState()
        observeSystemEvents()
        recorder.onFinished = { [weak self] result in
            self?.handleFinished(result)
        }
        recorder.onDiskSpaceCritical = { [weak self] in
            guard let self else { return }
            // 计划录制由 onFinished(.diskSpaceLow) 统一落结果与通知，这里只补手动录制的提醒
            if self.activeRun != nil { return }
            self.notifier.postDiskSpaceWarningForManualRecording()
        }
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        if let tickTimer {
            RunLoop.main.add(tickTimer, forMode: .common)
        }
        tick()
        Task { await notifier.refreshAuthorization() }
    }

    public func stop() {
        guard started else { return }
        started = false
        // App 正常退出时交给 prepareForTermination 保留现场；其它停止路径直接结束本次计划
        if !isShuttingDown {
            finalizeActiveRunForStop(message: "本次计划录制已停止")
        }
        awaitingRestartConfirmation = false
        tickTimer?.invalidate()
        tickTimer = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
        powerAssertion.release()
        isPendingUnlock = false
        pendingUnlockKey = nil
        pendingUnlockScheduleID = nil
        pendingUnlockWindow = nil
        recorder.onFinished = nil
        recorder.onDiskSpaceCritical = nil
    }

    public func cleanup() {
        stop()
    }

    /// App 退出前调用：先标记计划执行被打断，再交给 RecoveryCoordinator 收尾录制。
    public func prepareForTermination() {
        isShuttingDown = true
        guard var run = activeRun else { return }
        run.wasInterrupted = true
        activeRun = run
        store.saveActiveRun(run)
        powerAssertion.release()
    }

    // MARK: 计划管理

    public var notificationDegraded: Bool {
        notifier.isDegraded
    }

    public var hasScreenPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    public var nextScheduleSummary: String? {
        let now = Date()
        guard let next = engine.nextOccurrence(after: now, for: schedules) else { return nil }

        if next.window.start <= now, now < next.window.end {
            if activeRun?.scheduleID == next.schedule.id {
                return "录制中"
            }
            if let outcome = next.schedule.lastOutcome,
               outcome.date >= next.window.start.addingTimeInterval(-RecorderScheduleLimits.preStartReminder),
               outcome.date < next.window.end {
                switch outcome.kind {
                case .skipped: return "本次已跳过"
                case .failed: return "本次失败"
                case .completed, .stopped: return "本次已结束"
                }
            }
            return "本次待执行"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        let sameDay = Calendar.current.isDate(next.window.start, inSameDayAs: now)
        formatter.dateFormat = sameDay ? "HH:mm" : "M月d日 HH:mm"
        return "下次 \(formatter.string(from: next.window.start))"
    }

    public func schedule(id: UUID) -> RecorderSchedule? {
        schedules.first { $0.id == id }
    }

    /// 返回 nil 表示保存成功；否则为展示给用户的错误。
    @discardableResult
    public func save(_ schedule: RecorderSchedule) -> String? {
        if let error = engine.validationError(for: schedule, among: schedules) {
            return error
        }
        let isNew = !schedules.contains { $0.id == schedule.id }
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
        store.saveSchedules(schedules)
        lastEventMessage = "已保存计划「\(schedule.trimmedName)」"
        if isNew {
            Task { _ = await notifier.requestAuthorizationIfNeeded() }
        }
        tick()
        return nil
    }

    /// 启用开关；启用时若与其它启用计划重叠则拒绝并返回原因。
    @discardableResult
    public func setEnabled(_ enabled: Bool, for id: UUID) -> String? {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return nil }
        var candidate = schedules[index]
        candidate.isEnabled = enabled
        if enabled, let error = engine.validationError(for: candidate, among: schedules) {
            return error
        }
        schedules[index] = candidate
        store.saveSchedules(schedules)
        tick()
        return nil
    }

    /// 执行中的计划不能删除；需要先停止本次录制。
    @discardableResult
    public func delete(id: UUID) -> String? {
        if let run = activeRun, run.scheduleID == id {
            return "计划正在执行，请先停止本次录制"
        }
        schedules.removeAll { $0.id == id }
        store.saveSchedules(schedules)
        tick()
        return nil
    }

    /// 用户在计划窗口点击「停止」：只结束本次，计划保持启用。
    public func stopCurrentRun() {
        guard activeRun != nil, recorder.activeScheduleID != nil else { return }
        isEndingScheduledRun = false
        recorder.stop(reason: .userStopped)
    }

    /// 用户关闭屏幕录制总开关时，结束本次计划并清空现场，避免下次启动误弹补录确认。
    public func cancelActiveRunForFeatureDisable() {
        finalizeActiveRunForStop(message: "屏幕录制已停用，本次计划录制已停止")
    }

    /// 清空执行现场并落结果；App 退出路径不会走到这里。
    private func finalizeActiveRunForStop(message: String) {
        guard let run = activeRun else {
            store.clearActiveRun()
            return
        }
        activeRun = nil
        store.clearActiveRun()
        isEndingScheduledRun = false
        didPauseForLock = false
        if recorder.activeScheduleID == run.scheduleID {
            recorder.stop(reason: .userStopped)
        }
        guard let schedule = schedule(id: run.scheduleID) else { return }
        updateOutcome(for: schedule.id, kind: .stopped, message: message)
        if schedule.repeatRule.isOnce,
           let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index].isEnabled = false
            store.saveSchedules(schedules)
        }
    }

    /// 提前提醒里的「跳过本次」。
    /// `windowStart` 由通知携带，避免用户在开始时间之后点击时误跳过下一次计划。
    public func skipUpcoming(scheduleID: UUID, windowStart: Date? = nil) {
        guard let schedule = schedule(id: scheduleID),
              let window = targetWindow(for: schedule, windowStart: windowStart) else { return }

        let now = Date()
        if window.start <= now {
            if activeRun?.scheduleID == scheduleID,
               recorder.activeScheduleID == scheduleID {
                stopCurrentRun()
                return
            }
            // 开始时间已过但 tick 还没启动：仍要把这次 occurrence 标记为跳过，
            // 否则下一个 15 秒 tick 会照常开录。
            guard now < window.end,
                  !hasRecordedOutcome(for: schedule, in: window) else { return }
            markSkipped(schedule: schedule, window: window)
            return
        }

        guard !hasRecordedOutcome(for: schedule, in: window) else { return }
        markSkipped(schedule: schedule, window: window)
    }

    private func markSkipped(schedule: RecorderSchedule, window: DateInterval) {
        let key = occurrenceKey(schedule, window)
        handledOccurrenceKeys.insert(key)
        remindedOccurrenceKeys.insert(key)
        if pendingUnlockKey == key {
            clearPendingUnlock()
        }
        updateOutcome(for: schedule.id,
                      kind: .skipped,
                      message: RecorderScheduleSkipReason.userSkipped.message)
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }),
           schedules[index].repeatRule.isOnce {
            schedules[index].isEnabled = false
            store.saveSchedules(schedules)
        }
        notifier.postSkipped(for: schedule, reason: .userSkipped)
        lastEventMessage = "已跳过「\(schedule.trimmedName)」的本次计划"
    }

    private func hasRecordedOutcome(for schedule: RecorderSchedule, in window: DateInterval) -> Bool {
        guard let outcome = schedule.lastOutcome else { return false }
        return outcome.date >= window.start.addingTimeInterval(-RecorderScheduleLimits.preStartReminder)
            && outcome.date < window.end
    }

    private func isSkippedOccurrence(_ schedule: RecorderSchedule, _ window: DateInterval) -> Bool {
        guard let outcome = schedule.lastOutcome, outcome.kind == .skipped else { return false }
        return outcome.date >= window.start.addingTimeInterval(-RecorderScheduleLimits.preStartReminder)
            && outcome.date < window.end
    }

    private func targetWindow(for schedule: RecorderSchedule, windowStart: Date?) -> DateInterval? {
        guard let windowStart else {
            return engine.nextOccurrence(after: Date(), for: schedule)
        }
        guard let window = engine.nextOccurrence(after: windowStart.addingTimeInterval(-0.5),
                                                 for: schedule),
              abs(window.start.timeIntervalSince(windowStart)) < 1 else {
            return nil
        }
        return window
    }

    public func refreshAuthorization() async {
        await notifier.refreshAuthorization()
    }

    // MARK: 状态恢复

    private func loadPersistedState() {
        schedules = store.loadSchedules()
        guard let run = store.loadActiveRun() else {
            activeRun = nil
            return
        }
        activeRun = run
        restorePersistedRunIfNeeded(run)
    }

    private func restorePersistedRunIfNeeded(_ persistedRun: RecorderScheduleActiveRun) {
        guard !didRestorePersistedRun else { return }
        didRestorePersistedRun = true
        var run = persistedRun
        // 正常结束会清空 activeRun；启动时还能读到现场，说明上次被退出或崩溃打断
        if !run.wasInterrupted {
            run.wasInterrupted = true
            activeRun = run
            store.saveActiveRun(run)
        }
        let now = Date()
        guard now < run.windowEnd,
              let schedule = schedule(id: run.scheduleID),
              schedule.isEnabled else {
            activeRun = nil
            store.clearActiveRun()
            return
        }

        // 视觉回归与无 UI 环境下不弹窗，保持待确认状态，避免未确认就自动开录
        guard promptAllowed else {
            awaitingRestartConfirmation = true
            return
        }

        let alert = NSAlert()
        alert.messageText = "计划录制仍在进行中"
        alert.informativeText = "「\(schedule.trimmedName)」的录制窗口尚未结束（\(run.windowEnd.formatted(date: .omitted, time: .shortened)) 结束），是否继续录制剩余时间？"
        alert.addButton(withTitle: "继续录制")
        alert.addButton(withTitle: "放弃本次")
        alert.alertStyle = .informational

        if alert.runModal() == .alertFirstButtonReturn {
            lastEventMessage = "已选择继续补录剩余时间"
            tick()
        } else {
            let window = DateInterval(start: run.windowStart, end: run.windowEnd)
            recordSkip(schedule: schedule,
                       window: window,
                       reason: .appRestartDeclined)
        }
    }

    private var promptAllowed: Bool {
        guard NSApp != nil else { return false }
        let args = CommandLine.arguments
        return !args.contains("--visual") && !args.contains("--m8")
    }

    // MARK: 系统事件

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        let center = NotificationCenter.default

        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, var run = self.activeRun else { return }
                run.wasInterrupted = true
                self.activeRun = run
                self.store.saveActiveRun(run)
                self.powerAssertion.release()
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.powerAssertion.release()
                self?.pauseForLockIfNeeded()
            }
        })
        observers.append(center.addObserver(forName: Notification.Name.NSSystemClockDidChange,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        })
    }

    // MARK: 主循环

    private func tick() {
        guard started else { return }
        let now = Date()
        guard AppSettings.shared.screenRecorderEnabled else {
            powerAssertion.release()
            if activeRun != nil, recorder.activeScheduleID != nil {
                isEndingScheduledRun = true
                recorder.stop(reason: .scheduledStop)
            }
            return
        }
        updatePowerAssertion(now: now)
        handlePendingUnlock(now: now)
        handleActiveRun(now: now)
        handleDueSchedules(now: now)
        handleReminders(now: now)
    }

    private func updatePowerAssertion(now: Date) {
        let session = SystemEventCoordinator.shared
        let shouldHold = session.isOperational
            && engine.shouldHoldPowerAssertion(schedules: schedules, at: now)
        if shouldHold {
            powerAssertion.acquire()
        } else {
            powerAssertion.release()
        }
    }

    private func handleDueSchedules(now: Date) {
        guard activeRun == nil, !isStartingRun else { return }
        for schedule in schedules where schedule.isEnabled {
            guard let window = engine.occurrence(containing: now, for: schedule) else { continue }
            let key = occurrenceKey(schedule, window)
            if handledOccurrenceKeys.contains(key) { continue }
            // 跳过的 occurrence 可能发生在 App 重启之前，按 lastOutcome 恢复判断
            if isSkippedOccurrence(schedule, window) {
                handledOccurrenceKeys.insert(key)
                continue
            }
            if !SystemEventCoordinator.shared.isOperational {
                pendingUnlockKey = key
                pendingUnlockScheduleID = schedule.id
                pendingUnlockWindow = window
                isPendingUnlock = true
                return
            }
            handledOccurrenceKeys.insert(key)
            isStartingRun = true
            let recovered = now.timeIntervalSince(window.start) >= RecorderScheduleLimits.minimumResumeInterval
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.attemptStart(schedule: schedule, window: window, recovered: recovered)
                self.isStartingRun = false
            }
            return
        }
    }

    private func handleReminders(now: Date) {
        for schedule in schedules where schedule.isEnabled {
            guard let window = engine.nextOccurrence(after: now, for: schedule) else { continue }
            let reminderStart = window.start.addingTimeInterval(-RecorderScheduleLimits.preStartReminder)
            guard now >= reminderStart, now < window.start else { continue }
            let key = occurrenceKey(schedule, window)
            guard !remindedOccurrenceKeys.contains(key),
                  !handledOccurrenceKeys.contains(key) else { continue }
            guard !recorder.state.isActive else { continue }
            remindedOccurrenceKeys.insert(key)
            notifier.postReminder(for: schedule, window: window)
        }
    }

    private func handlePendingUnlock(now: Date) {
        guard let key = pendingUnlockKey,
              let scheduleID = pendingUnlockScheduleID,
              let window = pendingUnlockWindow else { return }
        guard let schedule = schedule(id: scheduleID), schedule.isEnabled else {
            clearPendingUnlock()
            return
        }
        if now >= window.end {
            handledOccurrenceKeys.insert(key)
            recordSkip(schedule: schedule, window: window, reason: .locked)
            clearPendingUnlock()
        }
    }

    private func handleActiveRun(now: Date) {
        guard !awaitingRestartConfirmation else { return }
        guard let run = activeRun, let schedule = schedule(id: run.scheduleID) else { return }

        if now >= run.windowEnd {
            if recorder.activeScheduleID == run.scheduleID {
                isEndingScheduledRun = true
                recorder.stop(reason: .scheduledStop)
            } else {
                finalizeRunWithoutRecording(schedule: schedule, run: run)
            }
            return
        }

        guard recorder.activeScheduleID == run.scheduleID else {
            // 睡眠 / 中断后的补录：剩余不足 1 分钟直接跳过
            guard SystemEventCoordinator.shared.isOperational else { return }
            let window = DateInterval(start: run.windowStart, end: run.windowEnd)
            guard engine.canResume(now: now, until: run.windowEnd) else {
                handledOccurrenceKeys.insert(occurrenceKey(schedule, window))
                recordSkip(schedule: schedule, window: window,
                           message: "剩余时间不足 1 分钟，本次计划已跳过")
                return
            }
            guard !isStartingRun else { return }
            isStartingRun = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.attemptStart(schedule: schedule, window: window, recovered: true)
                self.isStartingRun = false
            }
            return
        }

        // 锁屏 / 熄屏时暂停，避免写入黑帧；恢复后继续，结束时间不变
        if !SystemEventCoordinator.shared.isOperational {
            pauseForLockIfNeeded()
        } else if didPauseForLock, recorder.state == .paused {
            recorder.resume()
            didPauseForLock = false
        }
    }

    private func pauseForLockIfNeeded() {
        guard activeRun != nil, recorder.state == .recording else { return }
        recorder.pause()
        didPauseForLock = true
    }

    // MARK: 启动

    private func attemptStart(schedule: RecorderSchedule,
                              window: DateInterval,
                              recovered: Bool) async {
        let runKey = occurrenceKey(schedule, window)
        guard started, !isShuttingDown, AppSettings.shared.screenRecorderEnabled else {
            handledOccurrenceKeys.remove(runKey)
            return
        }
        guard SystemEventCoordinator.shared.isOperational else {
            remindPendingUnlock(schedule: schedule, window: window)
            return
        }

        if recorder.state.isActive, recorder.activeScheduleID != schedule.id {
            recordSkip(schedule: schedule, window: window, reason: .manualRecording)
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            recordSkip(schedule: schedule, window: window, reason: .screenPermission)
            return
        }
        guard await validateSource(schedule.source) else {
            recordSkip(schedule: schedule, window: window, reason: .invalidSource)
            return
        }

        // 窗口源校验可能耗时数秒，期间锁屏、关闭功能或修改计划都必须重新判断
        guard started, !isShuttingDown, AppSettings.shared.screenRecorderEnabled else {
            handledOccurrenceKeys.remove(runKey)
            return
        }
        guard SystemEventCoordinator.shared.isOperational else {
            remindPendingUnlock(schedule: schedule, window: window)
            return
        }
        guard let current = self.schedule(id: schedule.id),
              current.isEnabled,
              current.repeatRule == schedule.repeatRule,
              current.source == schedule.source,
              current.profile == schedule.profile else {
            handledOccurrenceKeys.remove(runKey)
            return
        }
        if recorder.state.isActive, recorder.activeScheduleID != schedule.id {
            recordSkip(schedule: current, window: window, reason: .manualRecording)
            return
        }
        guard recorder.hasEnoughDiskSpace() else {
            recordSkip(schedule: current, window: window, reason: .diskSpace)
            return
        }

        let didStart = recorder.startScheduled(region: region(for: current.source),
                                               profile: current.profile,
                                               scheduleID: current.id)
        guard didStart else {
            recordSkip(schedule: current, window: window,
                       message: recorder.lastError ?? "计划录制启动失败")
            return
        }

        let previousFiles = activeRun?.scheduleID == current.id ? (activeRun?.filePaths ?? []) : []
        activeRun = RecorderScheduleActiveRun(scheduleID: current.id,
                                              windowStart: window.start,
                                              windowEnd: window.end,
                                              startedAt: Date(),
                                              filePaths: previousFiles,
                                              wasInterrupted: false)
        store.saveActiveRun(activeRun)
        isEndingScheduledRun = false
        didPauseForLock = false
        handledOccurrenceKeys.insert(runKey)
        clearPendingUnlock()
        lastEventMessage = "计划「\(current.trimmedName)」已开始录制"

        if recovered {
            notifier.postResumed(for: current, window: window)
        } else {
            notifier.postStarted(for: current, window: window)
        }
    }

    private func remindPendingUnlock(schedule: RecorderSchedule, window: DateInterval) {
        let key = occurrenceKey(schedule, window)
        // 启动校验期间被锁屏/熄屏打断时，撤销本轮的已处理标记，解锁后还能重新开录
        handledOccurrenceKeys.remove(key)
        pendingUnlockKey = key
        pendingUnlockScheduleID = schedule.id
        pendingUnlockWindow = window
        isPendingUnlock = true
    }

    // MARK: 结束与结果

    private func handleFinished(_ result: RecorderFinishedSession) {
        guard var run = activeRun, result.scheduleID == run.scheduleID else { return }
        if let recording = result.recording {
            run.filePaths.append(recording.filePath)
            activeRun = run
            store.saveActiveRun(run)
        }

        // App 退出 / 系统睡眠触发的收尾：保留现场，唤醒或下次启动后再续录
        let interrupted = isShuttingDown || SystemEventCoordinator.shared.isSystemSleeping
        if interrupted, result.reason == .userStopped || result.reason == .runtimeFailure {
            run.wasInterrupted = true
            activeRun = run
            store.saveActiveRun(run)
            return
        }

        guard let schedule = schedule(id: run.scheduleID) else {
            activeRun = nil
            store.clearActiveRun()
            return
        }

        switch result.reason {
        case .scheduledStop:
            if isEndingScheduledRun, result.state == .done {
                finishRun(schedule: schedule,
                          kind: .completed,
                          message: "计划录制已完成",
                          recording: result.recording)
            } else {
                finishRun(schedule: schedule,
                          kind: .failed,
                          message: result.error ?? "计划录制收尾失败")
            }
        case .diskSpaceLow:
            finishRun(schedule: schedule,
                      kind: .failed,
                      message: "磁盘可用空间不足 500MB，录制已停止")
        case .userStopped:
            finishRun(schedule: schedule,
                      kind: .stopped,
                      message: "已手动停止本次计划录制")
        case .runtimeFailure:
            finishRun(schedule: schedule,
                      kind: .failed,
                      message: result.error ?? "计划录制异常结束")
        case .startFailed:
            finishRun(schedule: schedule,
                      kind: .failed,
                      message: result.error ?? "计划录制启动失败")
        }
    }

    private func finalizeRunWithoutRecording(schedule: RecorderSchedule, run: RecorderScheduleActiveRun) {
        let recording = recorder.recentRecordings.first { run.filePaths.contains($0.filePath) }
        if recording != nil || !run.filePaths.isEmpty {
            finishRun(schedule: schedule,
                      kind: .completed,
                      message: "计划录制已结束",
                      recording: recording)
        } else {
            let window = DateInterval(start: run.windowStart, end: run.windowEnd)
            handledOccurrenceKeys.insert(occurrenceKey(schedule, window))
            recordSkip(schedule: schedule, window: window, reason: .locked)
        }
    }

    private func finishRun(schedule: RecorderSchedule,
                           kind: RecorderScheduleOutcomeKind,
                           message: String,
                           recording: RecorderRecording? = nil) {
        activeRun = nil
        store.clearActiveRun()
        isEndingScheduledRun = false
        didPauseForLock = false

        updateOutcome(for: schedule.id, kind: kind, message: message)
        var updated = schedule
        if let latest = self.schedule(id: schedule.id) {
            updated = latest
        }
        if updated.repeatRule.isOnce {
            if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
                schedules[index].isEnabled = false
                store.saveSchedules(schedules)
            }
        }

        switch kind {
        case .completed:
            notifier.postFinished(for: updated, recording: recording)
        case .skipped, .failed:
            notifier.postSkipped(for: updated, message: message)
        case .stopped:
            break
        }
        lastEventMessage = message
    }

    private func recordSkip(schedule: RecorderSchedule,
                            window: DateInterval,
                            reason: RecorderScheduleSkipReason) {
        recordSkip(schedule: schedule, window: window, message: reason.message)
    }

    private func recordSkip(schedule: RecorderSchedule,
                            window: DateInterval,
                            message: String) {
        handledOccurrenceKeys.insert(occurrenceKey(schedule, window))
        clearPendingUnlock()
        if let run = activeRun, run.scheduleID == schedule.id {
            activeRun = nil
            store.clearActiveRun()
        }
        updateOutcome(for: schedule.id, kind: .skipped, message: message)
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }),
           schedules[index].repeatRule.isOnce {
            // 一次性计划只有这一次窗口，跳过后保留在列表但停用
            schedules[index].isEnabled = false
            store.saveSchedules(schedules)
        }
        if let latest = self.schedule(id: schedule.id) {
            notifier.postSkipped(for: latest, message: message)
        }
        lastEventMessage = message
    }

    private func updateOutcome(for scheduleID: UUID,
                               kind: RecorderScheduleOutcomeKind,
                               message: String) {
        guard let index = schedules.firstIndex(where: { $0.id == scheduleID }) else { return }
        schedules[index].lastOutcome = RecorderScheduleOutcome(date: Date(),
                                                              kind: kind,
                                                              message: message)
        store.saveSchedules(schedules)
    }

    private func clearPendingUnlock() {
        pendingUnlockKey = nil
        pendingUnlockScheduleID = nil
        pendingUnlockWindow = nil
        isPendingUnlock = false
    }

    // MARK: 录制源校验

    private func region(for source: RecorderScheduleSource) -> RecorderRegion {
        switch source {
        case .display(let displayID):
            return .display(displayID)
        case .window(let windowID, _, _):
            return .window(windowID)
        case .area(let displayID, let rect):
            return .area(displayID, rect)
        }
    }

    /// 显示器在线、区域仍在屏内、窗口 ID + owning app bundle id + 标题一致。
    private func validateSource(_ source: RecorderScheduleSource) async -> Bool {
        switch source {
        case .display(let displayID):
            return CGDisplayIsOnline(displayID) != 0
        case .area(let displayID, let rect):
            guard CGDisplayIsOnline(displayID) != 0 else { return false }
            let bounds = CGDisplayBounds(displayID)
            guard bounds.width > 0, bounds.height > 0,
                  rect.width >= 1, rect.height >= 1 else { return false }
            return CGRect(origin: .zero, size: bounds.size).contains(rect)
        case .window(let windowID, let bundleIdentifier, let title):
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false,
                                                                                      onScreenWindowsOnly: true),
                  let window = content.windows.first(where: { $0.windowID == windowID }) else {
                return false
            }
            let appBundleID = window.owningApplication?.bundleIdentifier ?? ""
            let windowTitle = window.title ?? ""
            return appBundleID == bundleIdentifier && windowTitle == title
        }
    }

    // MARK: 工具

    private func occurrenceKey(_ schedule: RecorderSchedule, _ window: DateInterval) -> String {
        "\(schedule.id.uuidString)-\(Int(window.start.timeIntervalSince1970))"
    }
}
