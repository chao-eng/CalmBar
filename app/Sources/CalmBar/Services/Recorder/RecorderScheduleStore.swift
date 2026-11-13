import Foundation

// MARK: - 计划持久化

/// 计划的 UserDefaults JSON 存储，可注入 defaults 便于测试。
@MainActor
public final class RecorderScheduleStore {
    public static let schedulesKey = "recorder.schedules.v1"
    public static let activeRunKey = "recorder.schedule.activeRun.v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadSchedules() -> [RecorderSchedule] {
        guard let data = defaults.data(forKey: Self.schedulesKey) else { return [] }
        // 损坏的 JSON 直接回退为空列表，避免单个坏字段导致整个模块不可用
        return (try? decoder.decode([RecorderSchedule].self, from: data)) ?? []
    }

    public func saveSchedules(_ schedules: [RecorderSchedule]) {
        guard let data = try? encoder.encode(schedules) else { return }
        defaults.set(data, forKey: Self.schedulesKey)
    }

    public func loadActiveRun() -> RecorderScheduleActiveRun? {
        guard let data = defaults.data(forKey: Self.activeRunKey) else { return nil }
        return try? decoder.decode(RecorderScheduleActiveRun.self, from: data)
    }

    public func saveActiveRun(_ run: RecorderScheduleActiveRun?) {
        guard let run else {
            clearActiveRun()
            return
        }
        guard let data = try? encoder.encode(run) else { return }
        defaults.set(data, forKey: Self.activeRunKey)
    }

    public func clearActiveRun() {
        defaults.removeObject(forKey: Self.activeRunKey)
    }
}
