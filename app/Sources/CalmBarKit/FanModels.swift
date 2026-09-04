import Foundation

public enum SMCFanKey {
    public static let count = "FNum"
    public static let actual = "F%dAc"
    public static let target = "F%dTg"
    public static let minimum = "F%dMn"
    public static let maximum = "F%dMx"
    public static let forceTest = "Ftst"
    public static let modeLower = "F%dmd"
    public static let modeUpper = "F%dMd"

    public static func key(_ template: String, fan: Int) -> String {
        String(format: template, fan)
    }
}

/// 风扇硬件能力 —— 温控模块据此在「被动散热（无风扇）」机型上自动降级
public enum FanCapability: Sendable, Equatable {
    /// SMC 尚未探测或探测失败
    case unknown
    /// 已确认无内置风扇（被动散热机型）
    case fanless
    /// 存在 N 个风扇
    case hasFans(Int)

    public var isFanless: Bool {
        if case .fanless = self { return true }
        return false
    }

    public var fanCount: Int {
        if case .hasFans(let n) = self { return n }
        return 0
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }

    public var supportsFanControl: Bool {
        // 仅 `.hasFans` 视为可控制：`.unknown`（探测失败）与 `.fanless` 都
        // 不应向用户暴露风扇调速 UI / 命令，避免 SMC 暂时不可读时误操作。
        if case .hasFans = self { return true }
        return false
    }
}

/// 无风扇仿真开关 —— 用于在无真机的开发机上验证“被动散热机型”降级路径。
///
/// 仅作用于主 App 探测链路的单点 (`FanController.detectCapability`)，不会影响
/// 特权助手进程（其不会设置 `forced`，也未继承 shell 环境变量 / App 偏好域）。
/// 支持三种触发方式：
///  1. `FanCapabilitySimulation.forced = .fanless`   —— 进程内（测试 / 调试钩子）
///  2. 环境变量 `CALMBAR_SIMULATE_FANLESS=1`          —— 终端启动时临时生效
///  3. `defaults write com.chaoeng.CalmBar CalmBarSimulateFanless -bool YES`
///                                                    —— 打包 App 视觉验证
public enum FanCapabilitySimulation {
    public static let envKey = "CALMBAR_SIMULATE_FANLESS"
    public static let defaultsKey = "CalmBarSimulateFanless"

    /// 进程内强制覆盖（并发不安全的调试钩子，仅测试与开发入口使用）
    public static nonisolated(unsafe) var forced: FanCapability? = nil

    /// 解析当前是否应强制返回某能力；无强制时返回 `nil`（走真实硬件探测）
    public static func resolvedOverride() -> FanCapability? {
        if let f = forced { return f }
        if let env = ProcessInfo.processInfo.environment[envKey] {
            let v = env.lowercased()
            if v == "1" || v == "true" || v == "yes" { return .fanless }
        }
        if UserDefaults.standard.bool(forKey: defaultsKey) { return .fanless }
        return nil
    }
}

public struct SMCHardwareConfig: Sendable {
    public let modeKeyFormat: String
    public let ftstAvailable: Bool
    public let capability: FanCapability

    public init(modeKeyFormat: String, ftstAvailable: Bool, capability: FanCapability = .unknown) {
        self.modeKeyFormat = modeKeyFormat
        self.ftstAvailable = ftstAvailable
        self.capability = capability
    }
}

public enum FanMode: UInt8, Sendable, Codable {
    case auto = 0
    case manual = 1
    case system = 3
    case unknown = 255
}

public enum FanControlStrategy: String, Sendable {
    case direct
    case ftstUnlock
}

public struct FanSnapshot: Sendable, Identifiable, Codable, Equatable {
    public var id: Int { index }
    public let index: Int
    public let actualRPM: Float
    public let targetRPM: Float
    public let minRPM: Float
    public let maxRPM: Float
    public let mode: FanMode

    public init(
        index: Int,
        actualRPM: Float,
        targetRPM: Float,
        minRPM: Float,
        maxRPM: Float,
        mode: FanMode
    ) {
        self.index = index
        self.actualRPM = actualRPM
        self.targetRPM = targetRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.mode = mode
    }

    public var percentage: Double {
        guard maxRPM > minRPM else { return 0 }
        let clamped = max(minRPM, min(actualRPM, maxRPM))
        return Double((clamped - minRPM) / (maxRPM - minRPM))
    }
}

public struct TemperatureReading: Sendable, Identifiable, Codable, Equatable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let celsius: Float

    public init(key: String, name: String, celsius: Float) {
        self.key = key
        self.name = name
        self.celsius = celsius
    }
}

public enum FanPreset: String, CaseIterable, Sendable, Codable, Identifiable {
    case auto
    case smart
    case manual

    public var id: String { rawValue }

    public var titleZH: String {
        switch self {
        case .auto: return "系统自动"
        case .smart: return "智能温控"
        case .manual: return "自定义转速"
        }
    }

    public var titleEN: String {
        switch self {
        case .auto: return "Auto"
        case .smart: return "Smart Curve"
        case .manual: return "Manual RPM"
        }
    }

    public var iconName: String {
        switch self {
        case .auto: return "gearshape.2"
        case .smart: return "waveform.path.ecg"
        case .manual: return "slider.horizontal.3"
        }
    }
}

public enum SensorCatalog {
    public struct SensorDef: Sendable {
        public let key: String
        public let name: String
        public let isPrimary: Bool
    }

    /// Apple Silicon (M1..M4/M5) primary keys + Intel sensors
    public static let candidates: [SensorDef] = [
        // CPU Sensors
        .init(key: "Tp01", name: "CPU 核心 1", isPrimary: true),
        .init(key: "Tp02", name: "CPU 核心 2", isPrimary: true),
        .init(key: "Tp05", name: "CPU 核心 3", isPrimary: true),
        .init(key: "Tp06", name: "CPU 核心 4", isPrimary: true),
        .init(key: "Tp09", name: "CPU 核心 5", isPrimary: true),
        .init(key: "Tp0f", name: "CPU 核心 6", isPrimary: true),
        .init(key: "Tp0g", name: "CPU 核心 7", isPrimary: true),
        .init(key: "Tp0o", name: "CPU 核心 8", isPrimary: true),
        .init(key: "Tp0O", name: "CPU 综合", isPrimary: true),
        .init(key: "TC0P", name: "CPU Proximity", isPrimary: true),
        
        // GPU Sensors (Apple Silicon M1/M2/M3/M4 + Intel)
        .init(key: "Tg0f", name: "GPU 核心 1", isPrimary: true),
        .init(key: "Tg0e", name: "GPU 核心 2", isPrimary: true),
        .init(key: "Tg0n", name: "GPU 核心 3", isPrimary: true),
        .init(key: "Tg0m", name: "GPU 核心 4", isPrimary: true),
        .init(key: "Tg0r", name: "GPU 核心 5", isPrimary: true),
        .init(key: "Tg0q", name: "GPU 核心 6", isPrimary: true),
        .init(key: "Tg0U", name: "GPU 综合 1", isPrimary: true),
        .init(key: "Tg05", name: "GPU 综合 2", isPrimary: true),
        .init(key: "TG0P", name: "GPU Proximity", isPrimary: true),
        
        // Battery Sensors
        .init(key: "TB1T", name: "电池主传感器", isPrimary: true),
        .init(key: "TB0T", name: "电池次传感器", isPrimary: true),
        .init(key: "TB2T", name: "电池传感器 3", isPrimary: false),
        
        // SoC / Efficiency
        .init(key: "Te05", name: "SoC 能效核心", isPrimary: false),
        .init(key: "Te04", name: "SoC 协同核心", isPrimary: false),
        .init(key: "Te06", name: "SoC 电源管理", isPrimary: false),
        .init(key: "TCMb", name: "SoC 主控模组", isPrimary: false),
        .init(key: "TCMz", name: "SoC 高温热点", isPrimary: false),
        
        // Chassis / Heatsink
        .init(key: "TH0a", name: "散热管 A", isPrimary: false),
        .init(key: "TH0b", name: "散热管 B", isPrimary: false),
        .init(key: "TH0x", name: "散热模组", isPrimary: false),
        .init(key: "TaMP", name: "机身进风/气流", isPrimary: false),
        .init(key: "TCHP", name: "机身掌托", isPrimary: false),
        .init(key: "Tm0p", name: "统一内存", isPrimary: false),
    ]
}

