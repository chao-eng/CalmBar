import Foundation

public enum CrontabScope: String, CaseIterable, Identifiable, Sendable {
    case user = "user"
    case system = "system"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .user: return "用户定时任务 (crontab -l)"
        case .system: return "系统定时任务 (/etc/crontab)"
        }
    }

    public var systemImage: String {
        switch self {
        case .user: return "person.crop.circle"
        case .system: return "gearshape.2"
        }
    }
}

public struct CronJob: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var scope: CrontabScope
    public var minute: String
    public var hour: String
    public var dayOfMonth: String
    public var month: String
    public var weekday: String
    public var runAsUser: String?
    public var command: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        scope: CrontabScope = .user,
        minute: String,
        hour: String,
        dayOfMonth: String,
        month: String,
        weekday: String,
        runAsUser: String? = nil,
        command: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.scope = scope
        self.minute = minute
        self.hour = hour
        self.dayOfMonth = dayOfMonth
        self.month = month
        self.weekday = weekday
        self.runAsUser = runAsUser
        self.command = command
        self.isEnabled = isEnabled
    }

    public var cronExpression: String {
        "\(minute) \(hour) \(dayOfMonth) \(month) \(weekday)"
    }

    public var scheduleDescription: String {
        CronScheduleDescriber.describe(
            minute: minute,
            hour: hour,
            dayOfMonth: dayOfMonth,
            month: month,
            weekday: weekday
        )
    }
}

public enum CronScheduleDescriber {
    public static func describe(
        minute: String,
        hour: String,
        dayOfMonth: String,
        month: String,
        weekday: String
    ) -> String {
        let m = minute, h = hour, dom = dayOfMonth, mon = month, dow = weekday

        if m == "*" && h == "*" && dom == "*" && mon == "*" && dow == "*" {
            return "每分钟执行"
        }
        if m.starts(with: "*/") && h == "*" && dom == "*" && mon == "*" && dow == "*" {
            let step = m.dropFirst(2)
            return "每 \(step) 分钟执行一次"
        }
        if m == "0" && h == "*" && dom == "*" && mon == "*" && dow == "*" {
            return "每小时整点执行"
        }
        if dom == "*" && mon == "*" && dow == "*" && h != "*" && m != "*" {
            return "每天 \(pad(h)):\(pad(m)) 执行"
        }
        if dom == "*" && mon == "*" && h != "*" && m != "*" && dow != "*" {
            let day = weekdayName(dow) ?? "周\(dow)"
            return "每\(day) \(pad(h)):\(pad(m)) 执行"
        }
        if dow == "*" && mon == "*" && h != "*" && m != "*" && dom != "*" {
            return "每月 \(dom) 日 \(pad(h)):\(pad(m)) 执行"
        }
        return "\(m) \(h) \(dom) \(mon) \(dow)"
    }

    private static func pad(_ value: String) -> String {
        value.count == 1 ? "0\(value)" : value
    }

    private static func weekdayName(_ value: String) -> String? {
        switch value {
        case "0", "7": return "周日"
        case "1": return "周一"
        case "2": return "周二"
        case "3": return "周三"
        case "4": return "周四"
        case "5": return "周五"
        case "6": return "周六"
        default: return nil
        }
    }
}

public enum CrontabLine: Identifiable, Hashable, Sendable {
    case blank(id: UUID)
    case comment(id: UUID, text: String)
    case environment(id: UUID, key: String, value: String)
    case job(CronJob)
    case raw(id: UUID, line: String)

    public var id: UUID {
        switch self {
        case .blank(let id): return id
        case .comment(let id, _): return id
        case .environment(let id, _, _): return id
        case .job(let job): return job.id
        case .raw(let id, _): return id
        }
    }
}
