import Foundation

// MARK: - 计划纯逻辑引擎

/// 下一次执行、进行中窗口、重叠判定、保存校验与保持唤醒区间。
/// 所有计算都显式注入 `Calendar` 与当前时间，便于单元测试覆盖跨天与 DST。
public struct RecorderScheduleEngine: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: 时间窗

    /// 返回包含 `date` 的执行窗口；一次性计划过期或未开始返回 nil。
    public func occurrence(containing date: Date, for schedule: RecorderSchedule) -> DateInterval? {
        guard schedule.isEnabled else { return nil }
        switch schedule.repeatRule {
        case .once(let start, let end):
            guard start <= date, date < end else { return nil }
            return DateInterval(start: start, end: end)
        case .daily(let startMinutes, let endMinutes):
            let today = calendar.startOfDay(for: date)
            for offset in [0, -1] {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      let window = dailyWindow(startingOn: day,
                                               startMinutes: startMinutes,
                                               endMinutes: endMinutes) else { continue }
                if window.start <= date, date < window.end {
                    return window
                }
            }
            return nil
        }
    }

    /// 返回 `after` 之后仍有效的最近窗口：正在进行的窗口会被返回，过期计划返回 nil。
    public func nextOccurrence(after date: Date, for schedule: RecorderSchedule) -> DateInterval? {
        guard schedule.isEnabled else { return nil }
        switch schedule.repeatRule {
        case .once(let start, let end):
            guard end > date else { return nil }
            return DateInterval(start: start, end: end)
        case .daily(let startMinutes, let endMinutes):
            let today = calendar.startOfDay(for: date)
            for offset in -1...8 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      let window = dailyWindow(startingOn: day,
                                               startMinutes: startMinutes,
                                               endMinutes: endMinutes) else { continue }
                if window.end > date {
                    return window
                }
            }
            return nil
        }
    }

    /// 返回严格晚于 `date` 的下一次执行窗口；正在进行中的当前窗口不算“下次”。
    public func upcomingOccurrence(after date: Date, for schedule: RecorderSchedule) -> DateInterval? {
        guard schedule.isEnabled else { return nil }
        switch schedule.repeatRule {
        case .once(let start, let end):
            guard start > date else { return nil }
            return DateInterval(start: start, end: end)
        case .daily(let startMinutes, let endMinutes):
            let today = calendar.startOfDay(for: date)
            for offset in 0...8 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      let window = dailyWindow(startingOn: day,
                                               startMinutes: startMinutes,
                                               endMinutes: endMinutes) else { continue }
                if window.start > date {
                    return window
                }
            }
            return nil
        }
    }

    /// 所有启用计划中最近的下一次执行。
    public func nextOccurrence(after date: Date,
                               for schedules: [RecorderSchedule]) -> (schedule: RecorderSchedule,
                                                                      window: DateInterval)? {
        schedules
            .filter(\.isEnabled)
            .compactMap { schedule -> (RecorderSchedule, DateInterval)? in
                guard let window = nextOccurrence(after: date, for: schedule) else { return nil }
                return (schedule, window)
            }
            .min { $0.1.start < $1.1.start }
    }

    /// 每天计划在某一天的具体窗口。`endMinutes <= startMinutes` 表示跨天。
    public func dailyWindow(startingOn day: Date,
                            startMinutes: Int,
                            endMinutes: Int) -> DateInterval? {
        let startHour = (startMinutes / 60) % 24
        let startMinute = startMinutes % 60
        guard let start = calendar.date(bySettingHour: startHour,
                                        minute: startMinute,
                                        second: 0,
                                        of: day,
                                        matchingPolicy: .nextTimePreservingSmallerComponents) else {
            return nil
        }
        let endDay: Date
        if endMinutes <= startMinutes {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            endDay = next
        } else {
            endDay = day
        }
        let endHour = (endMinutes / 60) % 24
        let endMinute = endMinutes % 60
        guard let end = calendar.date(bySettingHour: endHour,
                                      minute: endMinute,
                                      second: 0,
                                      of: endDay,
                                      matchingPolicy: .nextTimePreservingSmallerComponents),
              end > start else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    // MARK: 保持唤醒

    /// 开始前 10 分钟到计划结束持有断言。锁屏 / 会话非活跃由调用方另行释放。
    public func shouldHoldPowerAssertion(schedules: [RecorderSchedule], at date: Date) -> Bool {
        schedules.contains { schedule in
            guard let window = nextOccurrence(after: date, for: schedule) else { return false }
            return date >= window.start.addingTimeInterval(-RecorderScheduleLimits.powerAssertionLead)
                && date < window.end
        }
    }

    // MARK: 补录阈值

    /// 补录剩余不足 1 分钟时跳过。
    public func canResume(now: Date, until end: Date) -> Bool {
        end.timeIntervalSince(now) >= RecorderScheduleLimits.minimumResumeInterval
    }

    /// 当前窗口是否已到结束时间。
    public func shouldEnd(now: Date, window: DateInterval) -> Bool {
        now >= window.end
    }

    // MARK: 重叠

    /// 两个计划是否时间重叠。调用方负责只传入启用计划。
    public func overlaps(_ lhs: RecorderSchedule, _ rhs: RecorderSchedule) -> Bool {
        switch (lhs.repeatRule, rhs.repeatRule) {
        case (.once(let aStart, let aEnd), .once(let bStart, let bEnd)):
            return aStart < bEnd && bStart < aEnd
        case (.once(let onceStart, let onceEnd), .daily(let startMinutes, let endMinutes)):
            return onceIntersectsDaily(onceStart: onceStart,
                                       onceEnd: onceEnd,
                                       startMinutes: startMinutes,
                                       endMinutes: endMinutes)
        case (.daily(let startMinutes, let endMinutes), .once(let onceStart, let onceEnd)):
            return onceIntersectsDaily(onceStart: onceStart,
                                       onceEnd: onceEnd,
                                       startMinutes: startMinutes,
                                       endMinutes: endMinutes)
        case (.daily(let aStart, let aEnd), .daily(let bStart, let bEnd)):
            let aSegments = dailySegments(startMinutes: aStart, endMinutes: aEnd)
            let bSegments = dailySegments(startMinutes: bStart, endMinutes: bEnd)
            return aSegments.contains { a in
                bSegments.contains { b in a.start < b.end && b.start < a.end }
            }
        }
    }

    /// 编译所有启用计划的冲突关系，返回第一条冲突说明。
    public func overlapConflict(for schedule: RecorderSchedule,
                                among schedules: [RecorderSchedule]) -> RecorderSchedule? {
        schedules.first { other in
            other.isEnabled && other.id != schedule.id && overlaps(schedule, other)
        }
    }

    private func onceIntersectsDaily(onceStart: Date,
                                     onceEnd: Date,
                                     startMinutes: Int,
                                     endMinutes: Int) -> Bool {
        guard onceStart < onceEnd else { return false }
        let firstDay = calendar.startOfDay(for: onceStart)
        // 覆盖一次性计划可能跨越的天数，并向两侧各多取一天以兼容跨天窗口
        let spanDays = Int(ceil(onceEnd.timeIntervalSince(onceStart) / 86_400)) + 2
        for offset in -1...max(1, spanDays) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                  let window = dailyWindow(startingOn: day,
                                           startMinutes: startMinutes,
                                           endMinutes: endMinutes) else { continue }
            if onceStart < window.end, window.start < onceEnd {
                return true
            }
        }
        return false
    }

    /// 把每天的时间窗展开成当天的分钟区间；跨天会拆成两段。
    private func dailySegments(startMinutes: Int,
                               endMinutes: Int) -> [(start: Int, end: Int)] {
        let start = ((startMinutes % 1440) + 1440) % 1440
        let end = ((endMinutes % 1440) + 1440) % 1440
        if start == end {
            return [(0, 1440)]
        }
        if end > start {
            return [(start, end)]
        }
        return [(start, 1440), (0, end)]
    }

    // MARK: 保存校验

    /// 返回 nil 表示校验通过；否则为直接展示给用户的错误文案。
    public func validationError(for schedule: RecorderSchedule,
                                among schedules: [RecorderSchedule]) -> String? {
        guard !schedule.trimmedName.isEmpty else {
            return "请填写计划名称"
        }

        switch schedule.repeatRule {
        case .once(let start, let end):
            guard end > start else {
                return "结束时间必须晚于开始时间"
            }
        case .daily(let startMinutes, let endMinutes):
            guard (0..<1440).contains(startMinutes), (0..<1440).contains(endMinutes) else {
                return "每天计划的时间不合法"
            }
            guard startMinutes != endMinutes else {
                return "开始时间与结束时间不能相同"
            }
        }

        guard schedule.repeatRule.duration <= RecorderScheduleLimits.maxDuration else {
            return "单个计划时长不能超过 12 小时"
        }

        guard schedule.source.isStructurallyValid else {
            return "请选择有效的录制源"
        }

        guard schedule.profile.fps > 0 else {
            return "帧率不合法"
        }

        if schedule.isEnabled,
           let conflict = overlapConflict(for: schedule, among: schedules) {
            return "与计划「\(conflict.trimmedName)」的时间段重叠"
        }
        return nil
    }
}
