import Foundation

// MARK: - 监控快照（PRD A-4 / UC-M01 数据说明表）

enum MemoryPressureLevel: String, Sendable, Comparable {
    case normal
    case warning
    case critical

    private var rank: Int {
        switch self {
        case .normal: 0
        case .warning: 1
        case .critical: 2
        }
    }

    static func < (lhs: MemoryPressureLevel, rhs: MemoryPressureLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    var titleZH: String {
        switch self {
        case .normal: "正常"
        case .warning: "偏高"
        case .critical: "告急"
        }
    }
}

struct MonitorSample: Identifiable, Sendable {
    let timestamp: Date
    let cpuUsage: Double
    let gpuUsage: Double?
    let memoryUsed: UInt64
    let memoryTotal: UInt64
    let memoryPressure: MemoryPressureLevel
    let diskFree: UInt64
    let diskTotal: UInt64
    let networkIn: Double
    let networkOut: Double
    let localIP: String?
    let cpuTemp: Double?
    let batteryLevel: Int?

    var id: Date { timestamp }

    var memoryUsage: Double {
        guard memoryTotal > 0 else { return 0 }
        return min(1, Double(memoryUsed) / Double(memoryTotal))
    }

    var diskUsage: Double {
        guard diskTotal > 0 else { return 0 }
        return min(1, 1 - Double(diskFree) / Double(diskTotal))
    }
}

// MARK: - 时间窗口（PRD UC-M02）

enum MonitorRange: Int, CaseIterable, Identifiable, Sendable {
    case minute1 = 60
    case minute5 = 300
    case hour1 = 3600

    var id: Int { rawValue }

    var titleZH: String {
        switch self {
        case .minute1: "1 分钟"
        case .minute5: "5 分钟"
        case .hour1: "1 小时"
        }
    }
}

// MARK: - 内存环形缓冲（PRD A-5 / BR-21 / BR-22）

struct MonitorHistory: Sendable {
    private(set) var samples: [MonitorSample] = []
    let capacity: Int

    init(capacity: Int = 3600) {
        self.capacity = max(2, capacity)
    }

    mutating func append(_ sample: MonitorSample) {
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    mutating func removeAll() {
        samples.removeAll(keepingCapacity: true)
    }

    func samples(in range: MonitorRange, now: Date = Date()) -> [MonitorSample] {
        let cutoff = now.addingTimeInterval(-Double(range.rawValue))
        return samples.filter { $0.timestamp >= cutoff }
    }

    /// BR-22：按窗口降采样到不超过 120 个点
    static func downsample(_ raw: [MonitorSample], maxPoints: Int = 120) -> [MonitorSample] {
        guard raw.count > maxPoints, maxPoints > 1 else { return raw }
        let stride = Double(raw.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { index in
            let source = min(raw.count - 1, Int((Double(index) * stride).rounded()))
            return raw[source]
        }
    }

    func downsampled(in range: MonitorRange, maxPoints: Int = 120, now: Date = Date()) -> [MonitorSample] {
        Self.downsample(samples(in: range, now: now), maxPoints: maxPoints)
    }
}
