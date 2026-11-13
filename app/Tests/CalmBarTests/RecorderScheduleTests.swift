import CoreGraphics
import Foundation
import Testing
@testable import CalmBar

@Suite("Recorder Schedule Tests")
struct RecorderScheduleTests {

    // MARK: - 工具

    private var shanghai: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    private var newYork: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private func date(_ calendar: Calendar,
                      _ year: Int, _ month: Int, _ day: Int,
                      _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }

    private func makeSchedule(name: String = "测试计划",
                              repeatRule: RecorderScheduleRepeat,
                              source: RecorderScheduleSource = .display(displayID: 1),
                              isEnabled: Bool = true) -> RecorderSchedule {
        RecorderSchedule(
            name: name,
            repeatRule: repeatRule,
            source: source,
            profile: RecorderCaptureProfile(),
            isEnabled: isEnabled
        )
    }

    // MARK: - 每天计划的下次执行

    @Test("每天计划普通日返回当天窗口")
    func dailyNextOccurrenceNormalDay() {
        let calendar = shanghai
        let engine = RecorderScheduleEngine(calendar: calendar)
        let schedule = makeSchedule(repeatRule: .daily(startMinutes: 9 * 60, endMinutes: 11 * 60))
        let now = date(calendar, 2026, 5, 12, 8, 0)

        let window = engine.nextOccurrence(after: now, for: schedule)
        #expect(window?.start == date(calendar, 2026, 5, 12, 9, 0))
        #expect(window?.end == date(calendar, 2026, 5, 12, 11, 0))
    }

    @Test("每天计划跨天回绕到次日结束")
    func dailyNextOccurrenceCrossesMidnight() {
        let calendar = shanghai
        let engine = RecorderScheduleEngine(calendar: calendar)
        let schedule = makeSchedule(repeatRule: .daily(startMinutes: 23 * 60, endMinutes: 60))

        let evening = date(calendar, 2026, 5, 12, 22, 0)
        let window = engine.nextOccurrence(after: evening, for: schedule)
        #expect(window?.start == date(calendar, 2026, 5, 12, 23, 0))
        #expect(window?.end == date(calendar, 2026, 5, 13, 1, 0))

        // 已经进入跨天窗口时，仍返回当前窗口
        let inside = date(calendar, 2026, 5, 13, 0, 30)
        #expect(engine.occurrence(containing: inside, for: schedule)?.start == window?.start)
    }

    @Test("每天计划在 DST 切换日按墙上时间取整点")
    func dailyNextOccurrenceDSTDay() {
        let calendar = newYork
        let engine = RecorderScheduleEngine(calendar: calendar)
        let schedule = makeSchedule(repeatRule: .daily(startMinutes: 1 * 60, endMinutes: 4 * 60))
        let now = date(calendar, 2026, 3, 8, 0, 20)

        let window = engine.nextOccurrence(after: now, for: schedule)
        #expect(window != nil)
        let startComponents = calendar.dateComponents([.hour], from: window!.start)
        let endComponents = calendar.dateComponents([.hour], from: window!.end)
        #expect(startComponents.hour == 1)
        #expect(endComponents.hour == 4)
        // 春季拨快一小时：01:00 EST → 04:00 EDT 实际只有 2 小时
        #expect(window!.duration == 2 * 60 * 60)
    }

    // MARK: - 一次性计划

    @Test("一次性计划过期、进行中与未开始")
    func onceOccurrenceStates() {
        let calendar = shanghai
        let engine = RecorderScheduleEngine(calendar: calendar)
        let start = date(calendar, 2026, 5, 12, 9, 0)
        let end = date(calendar, 2026, 5, 12, 11, 0)
        let schedule = makeSchedule(repeatRule: .once(start: start, end: end))

        #expect(engine.nextOccurrence(after: start.addingTimeInterval(-60), for: schedule)?.start == start)
        #expect(engine.occurrence(containing: start.addingTimeInterval(600), for: schedule)?.end == end)
        #expect(engine.occurrence(containing: end.addingTimeInterval(1), for: schedule) == nil)
        #expect(engine.nextOccurrence(after: end, for: schedule) == nil)
    }

    @Test("停用的计划不参与执行窗口")
    func disabledScheduleHasNoOccurrence() {
        let calendar = shanghai
        let engine = RecorderScheduleEngine(calendar: calendar)
        let schedule = makeSchedule(
            repeatRule: .daily(startMinutes: 9 * 60, endMinutes: 11 * 60),
            isEnabled: false
        )
        #expect(engine.nextOccurrence(after: date(calendar, 2026, 5, 12, 8, 0), for: schedule) == nil)
    }

    // MARK: - 重叠

    @Test("重复计划与重复计划重叠，包含跨天回绕")
    func dailyOverlapsDailyAcrossMidnight() {
        let engine = RecorderScheduleEngine(calendar: shanghai)
        let overnight = makeSchedule(name: "跨天", repeatRule: .daily(startMinutes: 23 * 60, endMinutes: 60))
        let earlyMorning = makeSchedule(name: "清晨", repeatRule: .daily(startMinutes: 30, endMinutes: 2 * 60))
        let daytime = makeSchedule(name: "白天", repeatRule: .daily(startMinutes: 9 * 60, endMinutes: 11 * 60))

        #expect(engine.overlaps(overnight, earlyMorning))
        #expect(engine.overlaps(earlyMorning, overnight))
        #expect(!engine.overlaps(overnight, daytime))
        #expect(!engine.overlaps(daytime, earlyMorning))
    }

    @Test("重复计划与一次性计划按那一天时段比较")
    func dailyOverlapsOnce() {
        let calendar = shanghai
        let engine = RecorderScheduleEngine(calendar: calendar)
        let daily = makeSchedule(repeatRule: .daily(startMinutes: 9 * 60, endMinutes: 11 * 60))
        let hit = makeSchedule(repeatRule: .once(
            start: date(calendar, 2026, 5, 12, 10, 0),
            end: date(calendar, 2026, 5, 12, 12, 0)
        ))
        let miss = makeSchedule(repeatRule: .once(
            start: date(calendar, 2026, 5, 12, 12, 0),
            end: date(calendar, 2026, 5, 12, 13, 0)
        ))
        #expect(engine.overlaps(daily, hit))
        #expect(engine.overlaps(hit, daily))
        #expect(!engine.overlaps(daily, miss))
    }

    @Test("一次性计划之间按绝对区间比较")
    func onceOverlapsOnce() {
        let calendar = shanghai
        let engine = RecorderScheduleEngine(calendar: calendar)
        let first = makeSchedule(repeatRule: .once(
            start: date(calendar, 2026, 5, 12, 9, 0),
            end: date(calendar, 2026, 5, 12, 11, 0)
        ))
        let overlap = makeSchedule(repeatRule: .once(
            start: date(calendar, 2026, 5, 12, 10, 59),
            end: date(calendar, 2026, 5, 12, 12, 0)
        ))
        let adjacent = makeSchedule(repeatRule: .once(
            start: date(calendar, 2026, 5, 12, 11, 0),
            end: date(calendar, 2026, 5, 12, 12, 0)
        ))
        #expect(engine.overlaps(first, overlap))
        #expect(!engine.overlaps(first, adjacent))
    }

    @Test("保存校验只和启用计划比较")
    func validationIgnoresDisabledSchedules() {
        let calendar = shanghai
        let engine = RecorderScheduleEngine(calendar: calendar)
        let existing = makeSchedule(
            name: "停用计划",
            repeatRule: .once(
                start: date(calendar, 2026, 5, 12, 9, 0),
                end: date(calendar, 2026, 5, 12, 11, 0)
            ),
            isEnabled: false
        )
        let candidate = makeSchedule(repeatRule: .once(
            start: date(calendar, 2026, 5, 12, 9, 30),
            end: date(calendar, 2026, 5, 12, 10, 0)
        ))
        #expect(engine.validationError(for: candidate, among: [existing]) == nil)
    }

    @Test("停用的候选计划保存时不校验重叠")
    func validationSkipsOverlapForDisabledCandidate() {
        let engine = RecorderScheduleEngine(calendar: shanghai)
        let existing = makeSchedule(name: "启用计划",
                                    repeatRule: .daily(startMinutes: 9 * 60, endMinutes: 11 * 60))
        let candidate = makeSchedule(name: "停用计划",
                                     repeatRule: .daily(startMinutes: 10 * 60, endMinutes: 12 * 60),
                                     isEnabled: false)
        #expect(engine.validationError(for: candidate, among: [existing]) == nil)
    }

    // MARK: - 校验

    @Test("一次性计划结束不晚于开始时拒绝保存")
    func validationRejectsInvalidOnceRange() {
        let calendar = shanghai
        let engine = RecorderScheduleEngine(calendar: calendar)
        let schedule = makeSchedule(repeatRule: .once(
            start: date(calendar, 2026, 5, 12, 11, 0),
            end: date(calendar, 2026, 5, 12, 11, 0)
        ))
        #expect(engine.validationError(for: schedule, among: []) == "结束时间必须晚于开始时间")
    }

    @Test("超过 12 小时的计划拒绝保存")
    func validationRejectsTooLongSchedule() {
        let calendar = shanghai
        let engine = RecorderScheduleEngine(calendar: calendar)
        let schedule = makeSchedule(repeatRule: .once(
            start: date(calendar, 2026, 5, 12, 8, 0),
            end: date(calendar, 2026, 5, 12, 21, 0)
        ))
        #expect(engine.validationError(for: schedule, among: []) == "单个计划时长不能超过 12 小时")

        let daily = makeSchedule(repeatRule: .daily(startMinutes: 8 * 60, endMinutes: 21 * 60))
        #expect(engine.validationError(for: daily, among: []) == "单个计划时长不能超过 12 小时")
    }

    @Test("空白名称拒绝保存")
    func validationRejectsBlankName() {
        let calendar = shanghai
        let engine = RecorderScheduleEngine(calendar: calendar)
        let schedule = makeSchedule(name: "   ", repeatRule: .daily(startMinutes: 9 * 60, endMinutes: 10 * 60))
        #expect(engine.validationError(for: schedule, among: []) == "请填写计划名称")
    }

    @Test("与启用计划重叠时给出具体冲突名称")
    func validationReportsOverlapConflict() {
        let engine = RecorderScheduleEngine(calendar: shanghai)
        let existing = makeSchedule(name: "晨间录制",
                                    repeatRule: .daily(startMinutes: 9 * 60, endMinutes: 11 * 60))
        let candidate = makeSchedule(name: "新计划",
                                     repeatRule: .daily(startMinutes: 10 * 60, endMinutes: 12 * 60))
        #expect(engine.validationError(for: candidate, among: [existing])
                == "与计划「晨间录制」的时间段重叠")
    }

    // MARK: - 迟到阈值与保持唤醒

    @Test("补录剩余 59 秒跳过、60 秒补录")
    func resumeThreshold() {
        let engine = RecorderScheduleEngine(calendar: shanghai)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!engine.canResume(now: now, until: now.addingTimeInterval(59)))
        #expect(engine.canResume(now: now, until: now.addingTimeInterval(60)))
        #expect(engine.canResume(now: now, until: now.addingTimeInterval(61)))
    }

    @Test("保持唤醒区间为开始前 10 分钟到结束")
    func powerAssertionWindow() {
        let calendar = shanghai
        let engine = RecorderScheduleEngine(calendar: calendar)
        let start = date(calendar, 2026, 5, 12, 9, 0)
        let end = date(calendar, 2026, 5, 12, 11, 0)
        let schedule = makeSchedule(repeatRule: .once(start: start, end: end))
        let schedules = [schedule]

        #expect(!engine.shouldHoldPowerAssertion(schedules: schedules,
                                                 at: start.addingTimeInterval(-11 * 60)))
        #expect(engine.shouldHoldPowerAssertion(schedules: schedules,
                                                at: start.addingTimeInterval(-9 * 60)))
        #expect(engine.shouldHoldPowerAssertion(schedules: schedules,
                                                at: start.addingTimeInterval(30 * 60)))
        #expect(!engine.shouldHoldPowerAssertion(schedules: schedules,
                                                 at: end.addingTimeInterval(1)))
    }

    @Test("每天计划在开始前 10 分钟内持有断言")
    func powerAssertionForDailySchedule() {
        let calendar = shanghai
        let engine = RecorderScheduleEngine(calendar: calendar)
        let schedule = makeSchedule(repeatRule: .daily(startMinutes: 9 * 60, endMinutes: 10 * 60))
        #expect(engine.shouldHoldPowerAssertion(schedules: [schedule],
                                                at: date(calendar, 2026, 5, 12, 8, 51)))
        #expect(!engine.shouldHoldPowerAssertion(schedules: [schedule],
                                                 at: date(calendar, 2026, 5, 12, 8, 49)))
    }

    @Test("下次执行严格晚于当前时间，不返回进行中的窗口")
    func upcomingOccurrenceSkipsCurrentWindow() {
        let calendar = shanghai
        let engine = RecorderScheduleEngine(calendar: calendar)
        let daily = makeSchedule(repeatRule: .daily(startMinutes: 9 * 60, endMinutes: 11 * 60))
        let now = date(calendar, 2026, 5, 12, 9, 30)

        let nextDaily = engine.upcomingOccurrence(after: now, for: daily)
        #expect(nextDaily?.start == date(calendar, 2026, 5, 13, 9, 0))

        let once = makeSchedule(repeatRule: .once(
            start: date(calendar, 2026, 5, 12, 9, 0),
            end: date(calendar, 2026, 5, 12, 11, 0)
        ))
        #expect(engine.upcomingOccurrence(after: now, for: once) == nil)
    }

    // MARK: - 存储

    @Test("计划编码解码往返一致")
    @MainActor
    func storeRoundTrip() {
        let defaults = UserDefaults(suiteName: "RecorderScheduleTests.roundTrip")!
        defaults.removePersistentDomain(forName: "RecorderScheduleTests.roundTrip")
        let store = RecorderScheduleStore(defaults: defaults)
        let schedule = RecorderSchedule(
            name: "会议录制",
            repeatRule: .daily(startMinutes: 9 * 60, endMinutes: 11 * 60),
            source: .window(windowID: 42, bundleIdentifier: "com.apple.Safari", title: "周会"),
            profile: RecorderCaptureProfile(quality: .p4k, fps: 60, codec: .hevc,
                                            includeCursor: false,
                                            capturesSystemAudio: true,
                                            capturesMicrophone: true),
            lastOutcome: RecorderScheduleOutcome(kind: .completed, message: "已完成")
        )

        store.saveSchedules([schedule])
        #expect(store.loadSchedules() == [schedule])
    }

    @Test("损坏的 JSON 回退为空列表")
    @MainActor
    func storeCorruptJSONFallsBack() {
        let suite = "RecorderScheduleTests.corrupt"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(Data("not-json".utf8), forKey: RecorderScheduleStore.schedulesKey)
        let store = RecorderScheduleStore(defaults: defaults)
        #expect(store.loadSchedules().isEmpty)
    }

    @Test("activeRun 保存与清理")
    @MainActor
    func storeActiveRunLifecycle() {
        let suite = "RecorderScheduleTests.activeRun"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = RecorderScheduleStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let run = RecorderScheduleActiveRun(
            scheduleID: UUID(),
            windowStart: now,
            windowEnd: now.addingTimeInterval(3_600),
            startedAt: now,
            filePaths: ["/tmp/a.mp4"],
            wasInterrupted: true
        )

        store.saveActiveRun(run)
        #expect(store.loadActiveRun() == run)
        store.clearActiveRun()
        #expect(store.loadActiveRun() == nil)
    }
}
