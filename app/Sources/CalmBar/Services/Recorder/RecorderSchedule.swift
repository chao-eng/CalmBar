import CoreGraphics
import Foundation

// MARK: - 计划限制常量

/// 录制计划的硬性限制。单次上限固定为常量，不做成设置项。
public enum RecorderScheduleLimits {
    /// 单次计划最长 12 小时（一次性按起止差，重复按时间窗长度）
    public static let maxDuration: TimeInterval = 12 * 60 * 60
    /// 补录剩余不足 1 分钟直接跳过
    public static let minimumResumeInterval: TimeInterval = 60
    /// 提前提醒：开始前 5 分钟
    public static let preStartReminder: TimeInterval = 5 * 60
    /// 保持唤醒：开始前 10 分钟到计划结束
    public static let powerAssertionLead: TimeInterval = 10 * 60
    /// 开始与录制中巡检的最低可用磁盘
    public static let minimumDiskBytes: Int64 = 500 * 1024 * 1024
}

// MARK: - 录制参数快照

/// 创建计划时固定下来的完整录制参数，到点后不再读取设置页。
public struct RecorderCaptureProfile: Equatable, Sendable {
    public var quality: RecorderQuality
    public var fps: Int
    public var codec: RecorderCodec
    public var includeCursor: Bool
    public var capturesSystemAudio: Bool
    public var capturesMicrophone: Bool

    public init(quality: RecorderQuality = .p1080,
                fps: Int = 30,
                codec: RecorderCodec = .h264,
                includeCursor: Bool = true,
                capturesSystemAudio: Bool = true,
                capturesMicrophone: Bool = false) {
        self.quality = quality
        self.fps = fps
        self.codec = codec
        self.includeCursor = includeCursor
        self.capturesSystemAudio = capturesSystemAudio
        self.capturesMicrophone = capturesMicrophone
    }

    /// 从当前设置页生成快照，供新建计划时预填。
    @MainActor
    public static func fromSettings(_ settings: AppSettings = .shared) -> RecorderCaptureProfile {
        RecorderCaptureProfile(
            quality: settings.recorderQuality,
            fps: settings.recorderFPS,
            codec: settings.recorderCodec,
            includeCursor: settings.recorderIncludeCursor,
            capturesSystemAudio: settings.recorderCaptureSystemAudio,
            capturesMicrophone: settings.recorderCaptureMicrophone
        )
    }
}

extension RecorderCaptureProfile: Codable {
    private enum CodingKeys: String, CodingKey {
        case quality, fps, codec, includeCursor, capturesSystemAudio, capturesMicrophone
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quality = RecorderQuality(rawValue: try container.decode(String.self, forKey: .quality)) ?? .p1080
        fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? 30
        codec = RecorderCodec(rawValue: try container.decode(String.self, forKey: .codec)) ?? .h264
        includeCursor = try container.decodeIfPresent(Bool.self, forKey: .includeCursor) ?? true
        capturesSystemAudio = try container.decodeIfPresent(Bool.self, forKey: .capturesSystemAudio) ?? true
        capturesMicrophone = try container.decodeIfPresent(Bool.self, forKey: .capturesMicrophone) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(quality.rawValue, forKey: .quality)
        try container.encode(fps, forKey: .fps)
        try container.encode(codec.rawValue, forKey: .codec)
        try container.encode(includeCursor, forKey: .includeCursor)
        try container.encode(capturesSystemAudio, forKey: .capturesSystemAudio)
        try container.encode(capturesMicrophone, forKey: .capturesMicrophone)
    }
}

// MARK: - 录制源

/// 计划固定录制的目标。窗口会额外保存 owning app 的 bundle id 与标题，
/// 避免 CGWindowID 被系统回收后录到错误窗口。
public enum RecorderScheduleSource: Equatable, Sendable {
    case display(displayID: CGDirectDisplayID)
    case window(windowID: CGWindowID, bundleIdentifier: String, title: String)
    case area(displayID: CGDirectDisplayID, rect: CGRect)

    public var kindTitle: String {
        switch self {
        case .display: return "全屏"
        case .window: return "窗口"
        case .area: return "区域"
        }
    }

    /// 通知与窗口里使用的简短描述。
    public var displayDescription: String {
        switch self {
        case .display(let displayID):
            return "全屏（显示器 \(displayID)）"
        case .window(_, let bundleIdentifier, let title):
            let name = title.isEmpty ? bundleIdentifier : title
            return "窗口：\(name)"
        case .area(_, let rect):
            return "区域 \(Int(rect.width.rounded()))×\(Int(rect.height.rounded()))"
        }
    }

    /// 计划参数完整性检查，不访问屏幕采集接口。
    public var isStructurallyValid: Bool {
        switch self {
        case .display:
            return true
        case .window(_, let bundleIdentifier, let title):
            return !bundleIdentifier.isEmpty || !title.isEmpty
        case .area(_, let rect):
            return rect.width >= 1 && rect.height >= 1
        }
    }
}

extension RecorderScheduleSource: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, displayID, windowID, bundleIdentifier, title, rect
    }

    private enum Kind: String, Codable {
        case display, window, area
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .display:
            self = .display(displayID: try container.decode(CGDirectDisplayID.self, forKey: .displayID))
        case .window:
            self = .window(
                windowID: try container.decode(CGWindowID.self, forKey: .windowID),
                bundleIdentifier: try container.decodeIfPresent(String.self, forKey: .bundleIdentifier) ?? "",
                title: try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            )
        case .area:
            self = .area(
                displayID: try container.decode(CGDirectDisplayID.self, forKey: .displayID),
                rect: try container.decode(CGRect.self, forKey: .rect)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .display(let displayID):
            try container.encode(Kind.display, forKey: .type)
            try container.encode(displayID, forKey: .displayID)
        case .window(let windowID, let bundleIdentifier, let title):
            try container.encode(Kind.window, forKey: .type)
            try container.encode(windowID, forKey: .windowID)
            try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
            try container.encode(title, forKey: .title)
        case .area(let displayID, let rect):
            try container.encode(Kind.area, forKey: .type)
            try container.encode(displayID, forKey: .displayID)
            try container.encode(rect, forKey: .rect)
        }
    }
}

// MARK: - 重复方式

public enum RecorderScheduleRepeat: Equatable, Sendable {
    /// 绝对时间的一次性计划，允许跨天
    case once(start: Date, end: Date)
    /// 每天固定时段；endMinutes <= startMinutes 表示跨天
    case daily(startMinutes: Int, endMinutes: Int)

    public var isOnce: Bool {
        if case .once = self { return true }
        return false
    }

    /// 单次时间窗长度，用于 12 小时上限校验。
    public var duration: TimeInterval {
        switch self {
        case .once(let start, let end):
            return end.timeIntervalSince(start)
        case .daily(let startMinutes, let endMinutes):
            var minutes = endMinutes - startMinutes
            if minutes <= 0 { minutes += 24 * 60 }
            return TimeInterval(minutes * 60)
        }
    }

    public var timeWindowDescription: String {
        switch self {
        case .once(let start, let end):
            return "\(Self.dateFormatter.string(from: start)) – \(Self.dateFormatter.string(from: end))"
        case .daily(let startMinutes, let endMinutes):
            return "\(Self.minuteText(startMinutes)) – \(Self.minuteText(endMinutes))"
        }
    }

    public var repeatDescription: String {
        switch self {
        case .once: return "一次性"
        case .daily: return "每天"
        }
    }

    static func minuteText(_ minutes: Int) -> String {
        let normalized = ((minutes % (24 * 60)) + 24 * 60) % (24 * 60)
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}

extension RecorderScheduleRepeat: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, start, end, startMinutes, endMinutes
    }

    private enum Kind: String, Codable {
        case once, daily
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .once:
            self = .once(
                start: try container.decode(Date.self, forKey: .start),
                end: try container.decode(Date.self, forKey: .end)
            )
        case .daily:
            self = .daily(
                startMinutes: try container.decode(Int.self, forKey: .startMinutes),
                endMinutes: try container.decode(Int.self, forKey: .endMinutes)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .once(let start, let end):
            try container.encode(Kind.once, forKey: .type)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
        case .daily(let startMinutes, let endMinutes):
            try container.encode(Kind.daily, forKey: .type)
            try container.encode(startMinutes, forKey: .startMinutes)
            try container.encode(endMinutes, forKey: .endMinutes)
        }
    }
}

// MARK: - 执行结果

public enum RecorderScheduleOutcomeKind: String, Codable, Sendable {
    case completed
    case stopped
    case skipped
    case failed
}

public struct RecorderScheduleOutcome: Codable, Equatable, Sendable {
    public var date: Date
    public var kind: RecorderScheduleOutcomeKind
    public var message: String

    public init(date: Date = Date(), kind: RecorderScheduleOutcomeKind, message: String) {
        self.date = date
        self.kind = kind
        self.message = message
    }

    public var statusText: String {
        switch kind {
        case .completed: return "已完成"
        case .stopped: return "已停止"
        case .skipped: return "已跳过"
        case .failed: return "失败"
        }
    }
}

// MARK: - 计划

public struct RecorderSchedule: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var repeatRule: RecorderScheduleRepeat
    public var source: RecorderScheduleSource
    public var profile: RecorderCaptureProfile
    public var isEnabled: Bool
    public var createdAt: Date
    public var lastOutcome: RecorderScheduleOutcome?

    public init(id: UUID = UUID(),
                name: String,
                repeatRule: RecorderScheduleRepeat,
                source: RecorderScheduleSource,
                profile: RecorderCaptureProfile,
                isEnabled: Bool = true,
                createdAt: Date = Date(),
                lastOutcome: RecorderScheduleOutcome? = nil) {
        self.id = id
        self.name = name
        self.repeatRule = repeatRule
        self.source = source
        self.profile = profile
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastOutcome = lastOutcome
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var summary: String {
        "\(repeatRule.repeatDescription) · \(repeatRule.timeWindowDescription) · \(source.kindTitle)"
    }
}

// MARK: - 进行中的计划录制

/// 持久化的计划执行现场：App 退出或崩溃后用于判断是否需要询问补录。
public struct RecorderScheduleActiveRun: Codable, Equatable, Sendable {
    public var scheduleID: UUID
    public var windowStart: Date
    public var windowEnd: Date
    public var startedAt: Date
    public var filePaths: [String]
    /// 上一次退出是否是正常收尾之外的打断（App 退出 / 崩溃）
    public var wasInterrupted: Bool

    public init(scheduleID: UUID,
                windowStart: Date,
                windowEnd: Date,
                startedAt: Date,
                filePaths: [String] = [],
                wasInterrupted: Bool = false) {
        self.scheduleID = scheduleID
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.startedAt = startedAt
        self.filePaths = filePaths
        self.wasInterrupted = wasInterrupted
    }
}

// MARK: - 跳过原因

/// 计划执行与跳过路径共用的事件原因，所有路径都必须落 `lastOutcome`。
public enum RecorderScheduleSkipReason: String, Sendable {
    case disabled
    case manualRecording
    case screenPermission
    case invalidSource
    case diskSpace
    case locked
    case appRestartDeclined
    case userSkipped

    public var message: String {
        switch self {
        case .disabled: return "屏幕录制功能已停用"
        case .manualRecording: return "手动录制进行中，本次计划让路"
        case .screenPermission: return "屏幕权限被拒，本次计划已跳过"
        case .invalidSource: return "录制源已失效，本次计划已跳过"
        case .diskSpace: return "磁盘可用空间不足 500MB，本次计划已跳过"
        case .locked: return "锁屏期间错过计划开始，本次计划已跳过"
        case .appRestartDeclined: return "应用重启后放弃补录，本次计划已跳过"
        case .userSkipped: return "已在提醒中跳过本次计划"
        }
    }
}
