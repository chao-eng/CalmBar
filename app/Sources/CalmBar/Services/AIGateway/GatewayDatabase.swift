import Foundation
import SQLite3

// MARK: - 请求记录

public enum GatewayRequestStatus: String, CaseIterable, Sendable {
    case success
    case failed
    case cancelled
    case rejected

    public var title: String {
        switch self {
        case .success: return "成功"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        case .rejected: return "已拒绝"
        }
    }
}

public enum GatewaySpeedSource: String, Sendable {
    case usage
    case estimated
}

public enum GatewayTokenSource: String, Sendable {
    case usage
    case estimated
}

public struct GatewayRequestRecord: Sendable, Identifiable, Equatable {
    public var id: Int64
    public var createdAt: Date
    public var requestID: String
    public var endpoint: String
    public var protocolName: String
    public var isStream: Bool
    public var requestedModel: String
    public var upstreamModel: String?
    public var channelID: String?
    public var channelName: String?
    public var status: GatewayRequestStatus
    public var errorMessage: String?
    public var httpStatus: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var totalTokens: Int?
    public var tokenSource: GatewayTokenSource?
    public var ttftMs: Int?
    public var generationMs: Int?
    public var durationMs: Int
    public var outputTPS: Double?
    public var speedSource: GatewaySpeedSource?
    public var retryReason: String?
    public var clientCancelled: Bool

    public init(
        id: Int64 = 0,
        createdAt: Date = Date(),
        requestID: String,
        endpoint: String,
        protocolName: String,
        isStream: Bool,
        requestedModel: String,
        upstreamModel: String? = nil,
        channelID: String? = nil,
        channelName: String? = nil,
        status: GatewayRequestStatus,
        errorMessage: String? = nil,
        httpStatus: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        tokenSource: GatewayTokenSource? = nil,
        ttftMs: Int? = nil,
        generationMs: Int? = nil,
        durationMs: Int = 0,
        outputTPS: Double? = nil,
        speedSource: GatewaySpeedSource? = nil,
        retryReason: String? = nil,
        clientCancelled: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.requestID = requestID
        self.endpoint = endpoint
        self.protocolName = protocolName
        self.isStream = isStream
        self.requestedModel = requestedModel
        self.upstreamModel = upstreamModel
        self.channelID = channelID
        self.channelName = channelName
        self.status = status
        self.errorMessage = errorMessage
        self.httpStatus = httpStatus
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.tokenSource = tokenSource
        self.ttftMs = ttftMs
        self.generationMs = generationMs
        self.durationMs = durationMs
        self.outputTPS = outputTPS
        self.speedSource = speedSource
        self.retryReason = retryReason
        self.clientCancelled = clientCancelled
    }
}

// MARK: - 历史筛选

/// 历史分页游标：按 (created_at, id) 倒序翻页，避免 offset 随新记录写入而漂移
public struct GatewayRequestCursor: Sendable, Equatable {
    public let createdAtMilliseconds: Int64
    public let id: Int64

    public init(createdAtMilliseconds: Int64, id: Int64) {
        self.createdAtMilliseconds = createdAtMilliseconds
        self.id = id
    }

    public init(record: GatewayRequestRecord) {
        self.createdAtMilliseconds = Int64((record.createdAt.timeIntervalSince1970 * 1000).rounded())
        self.id = record.id
    }
}

public struct GatewayRequestFilter: Sendable, Equatable {
    public var model: String?
    public var channel: String?
    public var status: GatewayRequestStatus?
    public var since: Date?
    public var until: Date?

    public init(
        model: String? = nil,
        channel: String? = nil,
        status: GatewayRequestStatus? = nil,
        since: Date? = nil,
        until: Date? = nil
    ) {
        self.model = model
        self.channel = channel
        self.status = status
        self.since = since
        self.until = until
    }
}

// MARK: - 图表聚合

/// 面板统计窗口：最近 1 小时 / 今天 / 近 30 天 / 全部
/// 聚合粒度依次为 分钟 / 小时 / 天 / 天
public enum GatewayRange: String, CaseIterable, Identifiable, Sendable {
    case hour
    case today
    case month
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hour: return "1 小时"
        case .today: return "今天"
        case .month: return "30 天"
        case .all: return "全部"
        }
    }

    /// 指标条、卡片标题与空状态里的窗口描述
    public var windowTitle: String {
        switch self {
        case .hour: return "近 1 小时"
        case .today: return "今天"
        case .month: return "近 30 天"
        case .all: return "全部时间"
        }
    }

    public var bucketSeconds: Int {
        switch self {
        case .hour: return 60
        case .today: return 3600
        case .month, .all: return 86400
        }
    }

    /// 聚合单位，用于提示与无障碍文案
    public var bucketTitle: String {
        switch self {
        case .hour: return "分钟"
        case .today: return "小时"
        case .month, .all: return "天"
        }
    }

    /// 「全部」按天聚合时最多保留的桶数，避免历史很长时柱子挤在一起
    public static let maxDayBuckets = 90

    /// 窗口内的桶起点，升序；`.all` 依赖库内最早记录，缺失时返回空
    public func buckets(now: Date = Date(), earliest: Date? = nil, calendar: Calendar = .current) -> [Date] {
        switch self {
        case .hour:
            // 最近 60 个分钟桶，包含当前这一分钟
            let currentMinute = Self.minuteStart(now)
            return (0..<60).reversed().map { currentMinute.addingTimeInterval(TimeInterval(-$0 * 60)) }
        case .today:
            let start = calendar.startOfDay(for: now)
            let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? start
            return Self.step(from: start, to: currentHour, component: .hour, calendar: calendar)
        case .month:
            let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -29, to: now) ?? now)
            return Self.step(from: start, to: now, component: .day, calendar: calendar)
        case .all:
            guard let earliest else { return [] }
            let all = Self.step(from: calendar.startOfDay(for: earliest), to: now, component: .day, calendar: calendar)
            return all.count > Self.maxDayBuckets ? Array(all.suffix(Self.maxDayBuckets)) : all
        }
    }

    /// 对齐到自然时间边界后的当前桶起点
    public func currentBucketStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .hour:
            return Self.minuteStart(now)
        case .today:
            return calendar.dateInterval(of: .hour, for: now)?.start ?? calendar.startOfDay(for: now)
        case .month, .all:
            return calendar.startOfDay(for: now)
        }
    }

    private static func minuteStart(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }

    private static func step(from start: Date, to end: Date, component: Calendar.Component, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var cursor = start
        let last = component == .day ? calendar.startOfDay(for: end) : end
        while cursor <= last {
            result.append(cursor)
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
}

/// 一次查询的时间窗口：桶起点、桶宽与左闭右开边界
public struct GatewayWindow: Sendable, Equatable {
    public let buckets: [Date]
    public let bucketSeconds: Int

    public init(buckets: [Date], bucketSeconds: Int) {
        self.buckets = buckets
        self.bucketSeconds = bucketSeconds
    }

    public var start: Date? { buckets.first }
    public var end: Date? { buckets.last.map { $0.addingTimeInterval(TimeInterval(bucketSeconds)) } }

    /// 把时间点落到所属桶的起点；早于窗口起点返回 nil
    public func bucket(containing date: Date) -> Date? {
        // 「天」桶按自然日切分（夏令时那天 23 或 25 小时），二分查找桶起点比整除更稳
        guard let first = buckets.first, date >= first else { return nil }
        var low = 0
        var high = buckets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if buckets[mid] <= date {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return buckets[low]
    }
}

/// 渠道排行的排序维度
public enum GatewayRankingMetric: String, CaseIterable, Identifiable, Sendable {
    case requests
    case tokens
    case speed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .requests: return "请求"
        case .tokens: return "Token"
        case .speed: return "速度"
        }
    }

    /// 排行行右侧的主数值口径
    public var unitTitle: String {
        switch self {
        case .requests: return "次"
        case .tokens: return "token"
        case .speed: return "tok/s"
        }
    }
}

/// 图表指标口径：速度取平均 TPS，Token 取总量，请求取次数
public enum GatewayMetric: String, CaseIterable, Identifiable, Sendable {
    case speed
    case tokens
    case requests

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .speed: return "速度"
        case .tokens: return "Token"
        case .requests: return "请求"
        }
    }

    /// 图表坐标轴与卡片单位文案
    public var unitTitle: String {
        switch self {
        case .speed: return "tok/s"
        case .tokens: return "token"
        case .requests: return "次"
        }
    }
}

public struct GatewaySeriesDescriptor: Sendable, Equatable, Identifiable {
    public let key: String
    public let channelName: String
    public let model: String
    public let requestCount: Int

    public var id: String { key }
}

public struct GatewaySeriesPoint: Sendable, Equatable, Identifiable {
    public let bucketStart: Date
    public let seriesKey: String
    /// 指标值：速度口径为平均 TPS，Token 口径为总量，请求口径为次数
    public let value: Double
    public let requestCount: Int

    public var id: String { "\(seriesKey)@\(bucketStart.timeIntervalSince1970)" }
}

public struct GatewaySeriesResult: Sendable, Equatable {
    public let buckets: [Date]
    public let series: [GatewaySeriesDescriptor]
    public let points: [GatewaySeriesPoint]
    public let metric: GatewayMetric

    public static let empty = GatewaySeriesResult(
        buckets: [],
        series: [],
        points: [],
        metric: .speed
    )

    public init(
        buckets: [Date],
        series: [GatewaySeriesDescriptor],
        points: [GatewaySeriesPoint],
        metric: GatewayMetric = .speed
    ) {
        self.buckets = buckets
        self.series = series
        self.points = points
        self.metric = metric
    }

    public func value(for seriesKey: String, at bucket: Date) -> Double? {
        points.first { $0.seriesKey == seriesKey && $0.bucketStart == bucket }?.value
    }
}

/// 单个「渠道 · 模型」在统计窗口内的汇总，用于面板渠道排行
public struct GatewayChannelSummary: Sendable, Equatable, Identifiable {
    public let key: String
    public let channelName: String
    public let model: String
    public let requestCount: Int
    public let successCount: Int
    public let totalTokens: Int
    /// 成功请求的平均输出速率，无有效样本时为 nil
    public let averageTPS: Double?
    /// 成功请求的首字延迟均值（毫秒）
    public let averageTTFT: Double?

    public var id: String { key }

    public init(
        key: String,
        channelName: String,
        model: String,
        requestCount: Int,
        successCount: Int,
        totalTokens: Int,
        averageTPS: Double?,
        averageTTFT: Double?
    ) {
        self.key = key
        self.channelName = channelName
        self.model = model
        self.requestCount = requestCount
        self.successCount = successCount
        self.totalTokens = totalTokens
        self.averageTPS = averageTPS
        self.averageTTFT = averageTTFT
    }

    public var successRate: Double {
        guard requestCount > 0 else { return 0 }
        return Double(successCount) / Double(requestCount)
    }
}

public struct GatewayWindowSummary: Sendable, Equatable {
    public let requestCount: Int
    public let successCount: Int
    public let failureCount: Int
    public let totalTokens: Int
    /// 窗口内输入 Token 合计
    public let inputTokens: Int
    /// 窗口内输出 Token 合计
    public let outputTokens: Int
    /// 成功请求的平均输出速率，无有效样本时为 nil
    public let averageTPS: Double?

    public init(
        requestCount: Int,
        successCount: Int,
        failureCount: Int,
        totalTokens: Int,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        averageTPS: Double? = nil
    ) {
        self.requestCount = requestCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.averageTPS = averageTPS
    }

    public static let empty = GatewayWindowSummary(
        requestCount: 0,
        successCount: 0,
        failureCount: 0,
        totalTokens: 0
    )
}

// MARK: - SQLite 封装

public enum GatewayDatabaseError: LocalizedError {
    case openFailed(String)
    case statementFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "网关数据库打开失败：\(message)"
        case .statementFailed(let message): return "网关数据库操作失败：\(message)"
        }
    }
}

public actor GatewayDatabase {
    public static let shared = GatewayDatabase()

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private var db: OpaquePointer?
    private let queueLabel = "com.calmbar.aigateway.db"

    public init(path: String? = nil) {
        let resolved: String
        if let path {
            resolved = path
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let directory = support.appendingPathComponent("CalmBar", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            resolved = directory.appendingPathComponent("aigateway.db").path
        }
        self.db = Self.openDatabase(path: resolved)
    }

    private static func openDatabase(path: String) -> OpaquePointer? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        sqlite3_busy_timeout(handle, 2000)
        execute(handle, "PRAGMA journal_mode=WAL;")
        execute(handle, "PRAGMA synchronous=NORMAL;")
        execute(handle, """
        CREATE TABLE IF NOT EXISTS requests (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at INTEGER NOT NULL,
            request_id TEXT NOT NULL,
            endpoint TEXT NOT NULL,
            protocol TEXT NOT NULL,
            stream INTEGER NOT NULL,
            requested_model TEXT NOT NULL,
            upstream_model TEXT,
            channel_id TEXT,
            channel_name TEXT,
            status TEXT NOT NULL,
            error_message TEXT,
            http_status INTEGER,
            input_tokens INTEGER,
            output_tokens INTEGER,
            total_tokens INTEGER,
            token_source TEXT,
            ttft_ms INTEGER,
            generation_ms INTEGER,
            duration_ms INTEGER NOT NULL,
            output_tps REAL,
            speed_source TEXT,
            retry_reason TEXT,
            client_cancelled INTEGER NOT NULL DEFAULT 0
        );
        """)
        execute(handle, "CREATE INDEX IF NOT EXISTS idx_requests_created_at ON requests(created_at);")
        execute(handle, "CREATE INDEX IF NOT EXISTS idx_requests_status ON requests(status);")
        return handle
    }

    private static func execute(_ db: OpaquePointer, _ sql: String) {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            if let error { sqlite3_free(error) }
        }
    }

    // MARK: 写入

    public func insert(_ record: GatewayRequestRecord) throws {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }
        let sql = """
        INSERT INTO requests (
            created_at, request_id, endpoint, protocol, stream, requested_model, upstream_model,
            channel_id, channel_name, status, error_message, http_status,
            input_tokens, output_tokens, total_tokens, token_source,
            ttft_ms, generation_ms, duration_ms, output_tps, speed_source,
            retry_reason, client_cancelled
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        bind(stmt, 1, Int64(record.createdAt.timeIntervalSince1970 * 1000))
        bind(stmt, 2, record.requestID)
        bind(stmt, 3, record.endpoint)
        bind(stmt, 4, record.protocolName)
        bind(stmt, 5, record.isStream ? 1 : 0)
        bind(stmt, 6, record.requestedModel)
        bind(stmt, 7, record.upstreamModel)
        bind(stmt, 8, record.channelID)
        bind(stmt, 9, record.channelName)
        bind(stmt, 10, record.status.rawValue)
        bind(stmt, 11, record.errorMessage)
        bind(stmt, 12, record.httpStatus)
        bind(stmt, 13, record.inputTokens)
        bind(stmt, 14, record.outputTokens)
        bind(stmt, 15, record.totalTokens)
        bind(stmt, 16, record.tokenSource?.rawValue)
        bind(stmt, 17, record.ttftMs)
        bind(stmt, 18, record.generationMs)
        bind(stmt, 19, record.durationMs)
        bind(stmt, 20, record.outputTPS)
        bind(stmt, 21, record.speedSource?.rawValue)
        bind(stmt, 22, record.retryReason)
        bind(stmt, 23, record.clientCancelled ? 1 : 0)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: 查询

    public func recent(
        filter: GatewayRequestFilter = GatewayRequestFilter(),
        before: GatewayRequestCursor? = nil,
        limit: Int,
        offset: Int = 0
    ) throws -> [GatewayRequestRecord] {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }

        var clauses: [String] = []
        var bindings: [Any] = []
        if let model = filter.model {
            clauses.append("requested_model = ?")
            bindings.append(model)
        }
        if let channel = filter.channel {
            clauses.append("channel_name = ?")
            bindings.append(channel)
        }
        if let status = filter.status {
            clauses.append("status = ?")
            bindings.append(status.rawValue)
        }
        if let since = filter.since {
            clauses.append("created_at >= ?")
            bindings.append(Int64(since.timeIntervalSince1970 * 1000))
        }
        if let until = filter.until {
            clauses.append("created_at <= ?")
            bindings.append(Int64(until.timeIntervalSince1970 * 1000))
        }
        if let before {
            clauses.append("(created_at < ? OR (created_at = ? AND id < ?))")
            bindings.append(before.createdAtMilliseconds)
            bindings.append(before.createdAtMilliseconds)
            bindings.append(before.id)
        }
        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")

        let sql = """
        SELECT id, created_at, request_id, endpoint, protocol, stream, requested_model, upstream_model,
               channel_id, channel_name, status, error_message, http_status,
               input_tokens, output_tokens, total_tokens, token_source,
               ttft_ms, generation_ms, duration_ms, output_tps, speed_source,
               retry_reason, client_cancelled
        FROM requests
        \(whereClause)
        ORDER BY created_at DESC, id DESC
        LIMIT ? OFFSET ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var index: Int32 = 1
        for value in bindings {
            switch value {
            case let text as String:
                sqlite3_bind_text(stmt, index, text, -1, Self.transient)
            case let number as Int64:
                sqlite3_bind_int64(stmt, index, number)
            default:
                sqlite3_bind_null(stmt, index)
            }
            index += 1
        }
        sqlite3_bind_int(stmt, index, Int32(max(0, limit)))
        sqlite3_bind_int(stmt, index + 1, Int32(max(0, offset)))

        var rows: [GatewayRequestRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(mapRow(stmt))
        }
        return rows
    }

    public func distinctModels() throws -> [String] {
        try distinctValues(column: "requested_model")
    }

    public func distinctChannels() throws -> [String] {
        try distinctValues(column: "channel_name")
    }

    private func distinctValues(column: String) throws -> [String] {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }
        var stmt: OpaquePointer?
        let sql = "SELECT DISTINCT \(column) FROM requests WHERE \(column) IS NOT NULL ORDER BY \(column) ASC;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        var values: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = columnText(stmt, 0), !text.isEmpty {
                values.append(text)
            }
        }
        return values
    }

    public func delete(id: Int64) throws {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM requests WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func count() throws -> Int {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM requests;", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    public func deleteAll() throws {
        try execute("DELETE FROM requests;")
        try execute("VACUUM;")
    }

    public func delete(olderThan date: Date) throws {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM requests WHERE created_at < ?;", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(date.timeIntervalSince1970 * 1000))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    public func summary(since: Date, until: Date? = nil) throws -> GatewayWindowSummary {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }
        // 本地拒绝（rejected）不计入任何口径，与图表和渠道排行保持一致
        // total_tokens 可能缺失（失败请求通常只有输入计数），此时回退为 input + output
        let sql = """
        SELECT COUNT(*),
               SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END),
               SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END),
               SUM(COALESCE(total_tokens, COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0))),
               SUM(COALESCE(input_tokens, 0)),
               SUM(COALESCE(output_tokens, 0)),
               AVG(CASE WHEN status = 'success' AND output_tps IS NOT NULL THEN output_tps END)
        FROM requests
        WHERE created_at >= ? AND (? IS NULL OR created_at < ?)
          AND status != 'rejected';
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(since.timeIntervalSince1970 * 1000))
        if let until {
            sqlite3_bind_int64(stmt, 2, Int64(until.timeIntervalSince1970 * 1000))
            sqlite3_bind_int64(stmt, 3, Int64(until.timeIntervalSince1970 * 1000))
        } else {
            sqlite3_bind_null(stmt, 2)
            sqlite3_bind_null(stmt, 3)
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return .empty }
        let tps = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 6)
        return GatewayWindowSummary(
            requestCount: Int(sqlite3_column_int64(stmt, 0)),
            successCount: Int(sqlite3_column_int64(stmt, 1)),
            failureCount: Int(sqlite3_column_int64(stmt, 2)),
            totalTokens: Int(sqlite3_column_int64(stmt, 3)),
            inputTokens: Int(sqlite3_column_int64(stmt, 4)),
            outputTokens: Int(sqlite3_column_int64(stmt, 5)),
            averageTPS: tps
        )
    }

    /// 与图表同一时间窗口的汇总，供面板指标条使用
    public func summary(range: GatewayRange, now: Date = Date()) throws -> GatewayWindowSummary {
        let window = try resolveWindow(range: range, now: now)
        guard let start = window.start else { return .empty }
        return try summary(since: start, until: window.end)
    }

    /// 按窗口与口径聚合指标值，只保留请求量最高的若干系列
    /// - 速度：仅统计成功请求的平均 Output TPS
    /// - Token：统计成功与失败请求的 Token 总量（本地拒绝不计入）
    /// - 请求：统计请求次数（本地拒绝不计入）
    public func series(
        range: GatewayRange,
        metric: GatewayMetric = .speed,
        now: Date = Date(),
        seriesLimit: Int = 4
    ) throws -> GatewaySeriesResult {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }

        let window = try resolveWindow(range: range, now: now)
        guard let windowStart = window.start, let windowEnd = window.end else {
            return GatewaySeriesResult(buckets: [], series: [], points: [], metric: metric)
        }
        let buckets = window.buckets

        let sql = """
        SELECT created_at, channel_name, requested_model, status, output_tps,
               COALESCE(total_tokens, COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0)) AS tokens
        FROM requests
        WHERE created_at >= ? AND created_at < ? AND status != 'rejected';
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        // 窗口右边界取当前桶的结束时刻，避免与查询同一毫秒写入的记录被 `< now` 排除
        sqlite3_bind_int64(stmt, 1, Int64(windowStart.timeIntervalSince1970 * 1000))
        sqlite3_bind_int64(stmt, 2, Int64(windowEnd.timeIntervalSince1970 * 1000))

        struct Sample {
            let bucket: Date
            let key: String
            /// 该样本对当前口径的贡献值
            let value: Double
        }

        var samples: [Sample] = []
        var counts: [String: Int] = [:]
        var names: [String: (channel: String, model: String)] = [:]

        while sqlite3_step(stmt) == SQLITE_ROW {
            let milliseconds = sqlite3_column_int64(stmt, 0)
            guard let channel = columnText(stmt, 1), !channel.isEmpty else { continue }
            guard let model = columnText(stmt, 2), !model.isEmpty else { continue }
            let status = columnText(stmt, 3) ?? GatewayRequestStatus.success.rawValue

            let contribution: Double
            switch metric {
            case .speed:
                guard status == GatewayRequestStatus.success.rawValue else { continue }
                let tps = sqlite3_column_double(stmt, 4)
                guard tps.isFinite, tps > 0 else { continue }
                contribution = tps
            case .tokens:
                // 失败请求也可能已有部分 Token 消耗，照常计入
                contribution = Double(sqlite3_column_int64(stmt, 5))
            case .requests:
                contribution = 1
            }

            let createdAt = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
            // 按桶起点查表而非整除：跨时区与夏令时的「天」桶长度不固定
            guard let bucketStart = window.bucket(containing: createdAt) else { continue }
            let key = "\(channel)|\(model)"
            counts[key, default: 0] += 1
            names[key] = (channel, model)
            samples.append(Sample(bucket: bucketStart, key: key, value: contribution))
        }

        let topKeys = counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.prefix(seriesLimit).map(\.key)

        guard !topKeys.isEmpty else {
            return GatewaySeriesResult(buckets: buckets, series: [], points: [], metric: metric)
        }

        var sums: [String: (sum: Double, count: Int)] = [:]
        for sample in samples where topKeys.contains(sample.key) {
            let composite = "\(sample.key)#\(Int(sample.bucket.timeIntervalSince1970))"
            var entry = sums[composite] ?? (0, 0)
            entry.sum += sample.value
            entry.count += 1
            sums[composite] = entry
        }

        var points: [GatewaySeriesPoint] = []
        for key in topKeys {
            for bucket in buckets {
                let composite = "\(key)#\(Int(bucket.timeIntervalSince1970))"
                guard let entry = sums[composite], entry.count > 0 else { continue }
                // 速度取桶内均值，Token 与请求取桶内累计
                let value = metric == .speed ? entry.sum / Double(entry.count) : entry.sum
                points.append(GatewaySeriesPoint(
                    bucketStart: bucket,
                    seriesKey: key,
                    value: value,
                    requestCount: entry.count
                ))
            }
        }

        let series = topKeys.compactMap { key -> GatewaySeriesDescriptor? in
            guard let info = names[key] else { return nil }
            return GatewaySeriesDescriptor(
                key: key,
                channelName: info.channel,
                model: info.model,
                requestCount: counts[key] ?? 0
            )
        }

        return GatewaySeriesResult(buckets: buckets, series: series, points: points, metric: metric)
    }

    /// 统计窗口内的渠道排行，按 `metric` 降序返回前 limit 个「渠道 · 模型」组合
    public func channelSummaries(
        range: GatewayRange,
        now: Date = Date(),
        limit: Int = 3,
        metric: GatewayRankingMetric = .requests
    ) throws -> [GatewayChannelSummary] {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }

        let window = try resolveWindow(range: range, now: now)
        guard let windowStart = window.start, let windowEnd = window.end else { return [] }

        // 速度口径无有效样本时排到最后，避免 NULL 抢先
        let order: String
        switch metric {
        case .requests: order = "total DESC"
        case .tokens: order = "tokens DESC"
        case .speed: order = "tps IS NULL, tps DESC"
        }

        let sql = """
        SELECT channel_name,
               requested_model,
               COUNT(*) AS total,
               SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS success,
               SUM(COALESCE(total_tokens, COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0))) AS tokens,
               AVG(CASE WHEN status = 'success' AND output_tps IS NOT NULL THEN output_tps END) AS tps,
               AVG(CASE WHEN status = 'success' AND ttft_ms IS NOT NULL THEN ttft_ms END) AS ttft
        FROM requests
        WHERE created_at >= ? AND created_at < ?
          AND status != 'rejected'
          AND channel_name IS NOT NULL AND channel_name != ''
        GROUP BY channel_name, requested_model
        ORDER BY \(order), total DESC, channel_name ASC, requested_model ASC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(windowStart.timeIntervalSince1970 * 1000))
        sqlite3_bind_int64(stmt, 2, Int64(windowEnd.timeIntervalSince1970 * 1000))
        sqlite3_bind_int64(stmt, 3, Int64(limit))

        var result: [GatewayChannelSummary] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let channel = columnText(stmt, 0), let model = columnText(stmt, 1) else { continue }
            let tps = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 5)
            let ttft = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 6)
            result.append(GatewayChannelSummary(
                key: "\(channel)|\(model)",
                channelName: channel,
                model: model,
                requestCount: Int(sqlite3_column_int64(stmt, 2)),
                successCount: Int(sqlite3_column_int64(stmt, 3)),
                totalTokens: Int(sqlite3_column_int64(stmt, 4)),
                averageTPS: tps,
                averageTTFT: ttft
            ))
        }
        return result
    }

    /// 库内最早一条记录的时间，供「全部」窗口计算桶范围
    public func earliestRecordDate() throws -> Date? {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT MIN(created_at) FROM requests;", -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw GatewayDatabaseError.statementFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, sqlite3_column_type(stmt, 0) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 0)) / 1000)
    }

    /// 解析统计窗口；「全部」需要先查最早记录
    public func resolveWindow(range: GatewayRange, now: Date = Date()) throws -> GatewayWindow {
        let earliest = range == .all ? try earliestRecordDate() : nil
        return GatewayWindow(
            buckets: range.buckets(now: now, earliest: earliest),
            bucketSeconds: range.bucketSeconds
        )
    }

    // MARK: 工具

    private func execute(_ sql: String) throws {
        guard let db else { throw GatewayDatabaseError.openFailed("数据库未就绪") }
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown"
            if let error { sqlite3_free(error) }
            throw GatewayDatabaseError.statementFailed(message)
        }
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, Self.transient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int64(stmt, index, Int64(value))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Int64) {
        sqlite3_bind_int64(stmt, index, value)
    }

    private func bind(_ stmt: OpaquePointer, _ index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: pointer)
    }

    private func columnInt(_ stmt: OpaquePointer, _ index: Int32) -> Int? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(stmt, index))
    }

    private func columnDouble(_ stmt: OpaquePointer, _ index: Int32) -> Double? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(stmt, index)
    }

    private func mapRow(_ stmt: OpaquePointer) -> GatewayRequestRecord {
        let createdAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 1)) / 1000)
        return GatewayRequestRecord(
            id: sqlite3_column_int64(stmt, 0),
            createdAt: createdAt,
            requestID: columnText(stmt, 2) ?? "",
            endpoint: columnText(stmt, 3) ?? "",
            protocolName: columnText(stmt, 4) ?? "",
            isStream: sqlite3_column_int(stmt, 5) != 0,
            requestedModel: columnText(stmt, 6) ?? "",
            upstreamModel: columnText(stmt, 7),
            channelID: columnText(stmt, 8),
            channelName: columnText(stmt, 9),
            status: GatewayRequestStatus(rawValue: columnText(stmt, 10) ?? "") ?? .failed,
            errorMessage: columnText(stmt, 11),
            httpStatus: columnInt(stmt, 12),
            inputTokens: columnInt(stmt, 13),
            outputTokens: columnInt(stmt, 14),
            totalTokens: columnInt(stmt, 15),
            tokenSource: columnText(stmt, 16).flatMap(GatewayTokenSource.init(rawValue:)),
            ttftMs: columnInt(stmt, 17),
            generationMs: columnInt(stmt, 18),
            durationMs: Int(sqlite3_column_int64(stmt, 19)),
            outputTPS: columnDouble(stmt, 20),
            speedSource: columnText(stmt, 21).flatMap(GatewaySpeedSource.init(rawValue:)),
            retryReason: columnText(stmt, 22),
            clientCancelled: sqlite3_column_int(stmt, 23) != 0
        )
    }
}
